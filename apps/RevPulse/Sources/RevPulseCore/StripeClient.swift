import Foundation

/// Stripe REST client. HTTPS to api.stripe.com only; restricted read-only key from Keychain.
public struct StripeClient: Sendable {
    public static let host = "api.stripe.com"
    private let key: String
    private let session: URLSession

    public init(key: String, session: URLSession = StripeClient.privateSession()) {
        self.key = key
        self.session = session
    }

    public static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func looksRestricted(_ key: String) -> Bool {
        key.hasPrefix("rk_")
    }

    func request(path: String, query: [String: String]) async throws -> Data {
        guard var components = URLComponents(string: "https://\(Self.host)/v1/\(path)") else {
            throw StripeAPIError(.http(0, "bad path"))
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }
        }
        var req = URLRequest(url: components.url!, timeoutInterval: 30)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("RevPulse/1.0 (Mac App Store)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw StripeAPIError(.network("no HTTP response")) }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 { throw StripeAPIError(.unauthorized) }
                throw StripeAPIError(.http(http.statusCode, Self.message(from: data)))
            }
            return data
        } catch let e as StripeAPIError { throw e }
        catch { throw StripeAPIError(.network(error.localizedDescription)) }
    }

    static func message(from data: Data) -> String {
        struct Body: Decodable { let error: Msg?; struct Msg: Decodable { let message: String? } }
        return (try? JSONDecoder().decode(Body.self, from: data).error?.message) ?? "HTTP error"
    }

    // MARK: Endpoints

    public func account() async throws -> StripeAccount {
        let data = try await request(path: "account", query: [:])
        return try JSONDecoder().decode(StripeAccount.self, from: data)
    }

    public static func privateConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }
    public static func privateSession() -> URLSession { URLSession(configuration: privateConfiguration()) }

    private func pages<T>(path: String, query: [String: String], id: (T) -> String,
                          decode: ([String: Any]) throws -> T) async throws -> [T] {
        var all: [T] = [], cursor: String?, seen = Set<String>()
        while true {
            try Task.checkCancellation()
            var params = query; params["limit"] = "100"
            if let cursor { params["starting_after"] = cursor }
            let page = try StripeDecoder.page(try await request(path: path, query: params), decode: decode)
            all += page.items
            if !page.hasMore { return all }
            guard let last = page.items.last, seen.insert(id(last)).inserted else {
                throw StripeAPIError(.http(0, "Incomplete pagination. No totals displayed; please retry."))
            }
            cursor = id(last)
        }
    }
    public func charges(createdGTE: Int) async throws -> [StripeCharge] {
        try await pages(path: "charges", query: ["created[gte]": String(createdGTE), "expand[]": "data.balance_transaction"], id: { $0.id }, decode: StripeDecoder.charge)
    }
    public func customers(createdGTE: Int) async throws -> [StripeCustomer] {
        try await pages(path: "customers", query: ["created[gte]": String(createdGTE)], id: { $0.id }) { json in
            try JSONDecoder().decode(StripeCustomer.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }
    public func subscriptions(createdGTE: Int) async throws -> [StripeSubscription] {
        try await pages(path: "subscriptions", query: ["created[gte]": String(createdGTE), "status": "all"], id: { $0.id }) { json in
            try JSONDecoder().decode(StripeSubscription.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }
    public func refunds(createdGTE: Int) async throws -> [StripeRefund] {
        try await pages(path: "refunds", query: ["created[gte]": String(createdGTE)], id: { $0.id }) { json in
            try JSONDecoder().decode(StripeRefund.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }
    public func balanceTransactions(createdGTE: Int) async throws -> [StripeBalanceTransaction] {
        try await pages(path: "balance_transactions", query: ["created[gte]": String(createdGTE)], id: { $0.id }) { json in
            try JSONDecoder().decode(StripeBalanceTransaction.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }
}
