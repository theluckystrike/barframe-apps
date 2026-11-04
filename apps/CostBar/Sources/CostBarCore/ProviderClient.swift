import Foundation

public struct HTTPResult: Sendable {
    public let data: Data
    public let status: Int
    public init(data: Data, status: Int) { self.data = data; self.status = status }
}
public protocol HTTPTransport: Sendable {
    func get(_ request: URLRequest) async throws -> HTTPResult
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not forward an Admin credential to a redirected endpoint.
        completionHandler(nil)
    }
}
public final class SecureHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init(timeout: TimeInterval = 12) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func get(_ request: URLRequest) async throws -> HTTPResult {
        guard request.url?.scheme == "https" else { throw SpendError.insecureURL }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 8 * 1024 * 1024 else { throw SpendError.invalidResponse }
        return HTTPResult(data: data, status: http.statusCode)
    }
}

public struct ProviderClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = SecureHTTPTransport()) { self.transport = transport }
    public static func normalizedKey(_ input: String) throws -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 4096,
              key.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { throw SpendError.invalidKey }
        return key
    }
    public static func request(provider: Provider, key: String, now: Date, page: String? = nil, credits: Bool = false) throws -> URLRequest {
        let key = try normalizedKey(key)
        let month = UTCClock.month(now)
        var components: URLComponents
        switch provider {
        case .openRouter:
            components = URLComponents(string: "https://openrouter.ai/api/v1/\(credits ? "credits" : "key")")!
        case .anthropic:
            components = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")!
            components.queryItems = [
                .init(name: "starting_at", value: UTCClock.iso(month.start)),
                .init(name: "ending_at", value: UTCClock.iso(UTCClock.calendar.date(byAdding: .day, value: 1, to: UTCClock.day(now))!)),
                .init(name: "bucket_width", value: "1d"), .init(name: "limit", value: "31")
            ]
        case .openAI:
            components = URLComponents(string: "https://api.openai.com/v1/organization/costs")!
            components.queryItems = [
                .init(name: "start_time", value: String(Int(month.start.timeIntervalSince1970))),
                .init(name: "end_time", value: String(Int(now.timeIntervalSince1970))),
                .init(name: "bucket_width", value: "1d"), .init(name: "limit", value: "31")
            ]
        }
        if let page { components.queryItems = (components.queryItems ?? []) + [.init(name: "page", value: page)] }
        guard let url = components.url else { throw SpendError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CostBar/1.0.0", forHTTPHeaderField: "User-Agent")
        if provider == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }
    public static func validateStatus(_ status: Int) throws {
        switch status {
        case 200: break
        case 401: throw SpendError.authentication
        case 403: throw SpendError.forbidden
        case 429: throw SpendError.rateLimited
        default: throw SpendError.http(status)
        }
    }
    private func data(_ request: URLRequest) async throws -> Data {
        let response = try await transport.get(request)
        try Self.validateStatus(response.status)
        return response.data
    }
    public func fetch(provider: Provider, key: String, now: Date = Date()) async throws -> SpendSnapshot {
        if provider == .openRouter {
            let snapshot = try CostParser.openRouterKey(await data(Self.request(provider: provider, key: key, now: now)), now: now)
            var balance: Decimal?, note: String?
            do { balance = try CostParser.openRouterCredits(await data(Self.request(provider: provider, key: key, now: now, credits: true))) }
            catch {
                if error is CancellationError { throw error }
                note = (error as? SpendError) == .forbidden ? "Account credits require a management key." : "Account credits are unavailable; key spend is current."
            }
            return .init(provider: provider, fetchedAt: now, dailyUSD: snapshot.dailyUSD, monthlyUSD: snapshot.monthlyUSD, remainingCredits: balance, creditNote: note, weeklyUSD: snapshot.weeklyUSD, lifetimeUSD: snapshot.lifetimeUSD)
        }
        var buckets: [CostBucket] = [], next: String?, seen = Set<String>()
        for _ in 0..<100 {
            try Task.checkCancellation()
            let payload = try await data(Self.request(provider: provider, key: key, now: now, page: next))
            let page = try provider == .anthropic ? CostParser.anthropic(payload) : CostParser.openAI(payload)
            buckets += page.buckets
            guard let cursor = page.nextPage else { return try .aggregate(provider: provider, buckets: buckets, now: now) }
            guard seen.insert(cursor).inserted else { throw SpendError.pagination }
            next = cursor
        }
        throw SpendError.pagination
    }
    public func publicModelsCheck() async throws -> (status: Int, modelCount: Int) {
        let response = try await transport.get(URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!))
        try Self.validateStatus(response.status)
        guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let models = object["data"] as? [[String: Any]], !models.isEmpty,
              models.allSatisfy({ $0["id"] is String }) else { throw SpendError.invalidResponse }
        return (response.status, models.count)
    }
}
