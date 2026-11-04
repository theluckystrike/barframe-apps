import Foundation
import Vision
import ImageIO
import Testing
@testable import RevPulseCore

/// Synthetic fixtures; no merchant credentials or business measurements.
private final class FixtureProtocol: URLProtocol {
    static let lock = NSLock()
    static var fixtures: [String: NetworkFixture] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let fixture = Self.lock.withLock { Self.fixtures[key] }
        let (status, body) = fixture?.response(request) ?? (500, ["error": ["message": "missing fixture"]])
        let data = try! JSONSerialization.data(withJSONObject: body)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class NetworkFixture: @unchecked Sendable {
    let key = "rk_test_" + UUID().uuidString
    let lock = NSLock()
    var requests: [URLRequest] = []
    var intervals: [Double] = []
    let manyPages: Bool
    let fail: Bool
    let brokenPagination: Bool
    init(manyPages: Bool = false, fail: Bool = false, brokenPagination: Bool = false) {
        self.manyPages = manyPages; self.fail = fail; self.brokenPagination = brokenPagination
        FixtureProtocol.lock.withLock { FixtureProtocol.fixtures["Bearer " + key] = self }
    }
    func session() -> URLSession {
        let config = StripeClient.privateConfiguration(); config.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: config)
    }
    func response(_ request: URLRequest) -> (Int, [String: Any]) {
        lock.withLock { requests.append(request) }
        if fail { return (401, ["error": ["message": "invalid key"]]) }
        let endpoint = request.url!.lastPathComponent
        if endpoint == "account" { return (200, ["id": "acct_fixture", "default_currency": "usd"]) }
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        let cursor = query.first { $0.name == "starting_after" }?.value
        if brokenPagination { return (200, ["data": [], "has_more": true]) }
        if manyPages && endpoint == "charges" {
            let page = cursor.flatMap { Int($0.split(separator: "_").last!) }.map { $0 / 100 } ?? 0
            let items = (1...100).map { charge(id: "ch_" + String(page * 100 + $0)) }
            return (200, ["data": items, "has_more": page < 20])
        }
        let item: [String: Any]
        switch endpoint {
        case "charges": item = charge(id: cursor == nil ? "ch_1" : "ch_2")
        case "customers": item = ["id": cursor == nil ? "cus_1" : "cus_2", "created": 1]
        case "subscriptions": item = ["id": cursor == nil ? "sub_1" : "sub_2", "created": 1, "status": "canceled"]
        case "refunds": item = ["id": cursor == nil ? "re_1" : "re_2", "created": 1, "amount": 1]
        case "balance_transactions": item = ["id": cursor == nil ? "txn_1" : "txn_2", "created": 1, "amount": 100, "net": 90, "currency": "usd", "type": "charge"]
        default: item = [:]
        }
        return (200, ["data": [item], "has_more": cursor == nil])
    }
    func charge(id: String) -> [String: Any] {
        ["id": id, "amount": 100, "created": 1, "currency": "usd", "status": "succeeded", "balance_transaction": ["net": 90, "currency": "usd", "created": 1]]
    }
    func accountRequests() -> Int { lock.withLock { requests.filter { $0.url!.lastPathComponent == "account" }.count } }
    func recordInterval(_ value: Double) { lock.withLock { intervals.append(value) } }
}
struct AuditRegressionTests {
    let now = Date(timeIntervalSince1970: 1_792_001_000)
    func snapshot(_ transactions: [StripeBalanceTransaction]?, charges: [StripeCharge] = []) -> Revenue.Snapshot {
        Revenue.snapshot(charges: charges, customers: [], subscriptions: [], refunds: [], currency: "usd", goalCents: 10000, now: now, balanceTransactions: transactions)
    }
    func transaction(_ id: String, _ net: Int, currency: String = "usd", type: String = "charge") -> StripeBalanceTransaction {
        StripeBalanceTransaction(id: id, amount: net, net: net, currency: currency, created: Int(now.timeIntervalSince1970), type: type)
    }
    @Test func missingNetNeverFallsBackToGross() throws {
        let charge = try StripeDecoder.charge(["id": "ch_missing", "amount": 10000, "currency": "usd", "created": Int(now.timeIntervalSince1970), "status": "succeeded"])
        let result = snapshot(nil, charges: [charge])
        #expect(!result.netComplete); #expect(result.monthToDateNetCents == 0)
        #expect(!snapshot([], charges: [charge]).netComplete)
        #expect(Formatting.menuBarTitle(snapshot: result) == "Net unavailable")
    }
    @Test func mixedSettlementCurrencyNotCombined() {
        let result = snapshot([transaction("usd", 200), transaction("eur", 200, currency: "eur")])
        #expect(!result.netComplete); #expect(result.monthToDateNetCents == 0)
    }
    @Test func refundOfOlderSaleDeductsCurrentMonthOnce() {
        let result = snapshot([transaction("refund_prior_month", -500, type: "refund")])
        #expect(result.netComplete); #expect(result.monthToDateNetCents == -500)
        #expect(result.today.netCents == -500); #expect(result.refundsMTDCents == 500)
        #expect(result.goalProgress == 0)
    }
    @Test func paymentCurrencyDoesNotAlterSettlementNet() throws {
        let charge = try StripeDecoder.charge(["id": "ch_fx", "amount": 900, "amount_refunded": 900, "currency": "eur", "created": Int(now.timeIntervalSince1970), "status": "succeeded", "balance_transaction": ["net": 1000, "currency": "usd", "created": Int(now.timeIntervalSince1970)]])
        #expect(charge.settlementCurrency == "usd")
        let result = snapshot([transaction("settled", 1000), transaction("refund", -1050, type: "refund")], charges: [charge])
        #expect(result.monthToDateNetCents == -50)
    }
    @Test func priorSaleDoesNotSuppressTodaysFirstSale() throws {
        let charges = try SampleData.charges(now: now)
        #expect(Revenue.events(charges: charges, now: now).contains { if case .firstSaleToday = $0 { return true }; return false })
    }
    @Test func notificationDatesResetAndControlsAreIndependent() throws {
        let today = Revenue.dayKey(Int(now.timeIntervalSince1970)).addingTimeInterval(18 * 3600)
        let charges = try SampleData.charges(now: today)
        var history = NotificationHistory()
        let first = history.pending(charges: charges, now: today, firstSale: true, failedPayment: false)
        #expect(first.count == 1)
        #expect(history.pending(charges: charges, now: today, firstSale: true, failedPayment: false).isEmpty)
        #expect(history.pending(charges: charges, now: today, firstSale: false, failedPayment: true).count == 1)
        let tomorrow = today.addingTimeInterval(86400)
        #expect(history.pending(charges: try SampleData.charges(now: tomorrow), now: tomorrow, firstSale: true, failedPayment: false).count == 1)
    }
    @Test func everyEndpointFollowsPagination() async throws {
        let fixture = NetworkFixture(); let client = StripeClient(key: fixture.key, session: fixture.session())
        #expect(try await client.charges(createdGTE: 0).count == 2)
        #expect(try await client.customers(createdGTE: 0).count == 2)
        #expect(try await client.subscriptions(createdGTE: 0).count == 2)
        #expect(try await client.refunds(createdGTE: 0).count == 2)
        #expect(try await client.balanceTransactions(createdGTE: 0).count == 2)
        #expect(fixture.lock.withLock { fixture.requests.count } == 10)
    }
    @Test func chargePaginationExceedsFormerCap() async throws {
        let fixture = NetworkFixture(manyPages: true); let client = StripeClient(key: fixture.key, session: fixture.session())
        #expect(try await client.charges(createdGTE: 0).count == 2100)
    }
    @Test func stalledPaginationThrowsInsteadOfReturningPartialTotals() async {
        let fixture = NetworkFixture(brokenPagination: true); let client = StripeClient(key: fixture.key, session: fixture.session())
        await #expect(throws: Error.self) { try await client.customers(createdGTE: 0) }
    }
    @Test func noPersistentSessionCache() {
        let config = StripeClient.privateConfiguration()
        #expect(config.urlCache == nil); #expect(config.httpCookieStorage == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }
    @Test @MainActor func displayedWindowStartsBeforeMonthBoundary() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let first = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let start = AppModel.fetchStartUnix(now: first)
        #expect(start < AppModel.monthStartUnix(now: first))
        #expect(Revenue.dayKey(start) == cal.date(from: DateComponents(year: 2026, month: 10, day: 26)))
    }
    @Test func unresolvedPolicyURLFallsBackToLocalDocument() {
        #expect(PublicLink.webURL("https://{DOMAIN}/revpulse/privacy/", path: "/revpulse/privacy/") == nil)
        #expect(PublicLink.webURL("https://%7BDOMAIN%7D/revpulse/privacy/", path: "/revpulse/privacy/") == nil)
        #expect(PublicLink.webURL("https://barframe.com/apps/revpulse/privacy/", path: "/revpulse/privacy/") != nil)
    }
    @Test @MainActor func notificationsStartDisabledAndSampleGoalFollowsControl() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(defaults: defaults, keyStore: KeyStore(service: UUID().uuidString), start: false, loginStatus: false)
        #expect(!model.notificationsEnabled); #expect(!model.failedPaymentNotificationsEnabled)
        model.goalCents = 25000
        #expect(model.snapshot?.goalCents == 25000)
    }
    @Test @MainActor func loginRequiresUserActionAndReportsFailures() {
        var actions: [Bool] = []
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, keyStore: KeyStore(service: UUID().uuidString), start: false, loginStatus: false, loginAction: {
            actions.append($0); if !$0 { throw StripeAPIError(.network("fixture failure")) }
        })
        #expect(actions.isEmpty); model.setLaunchAtLogin(true)
        #expect(actions == [true]); #expect(model.launchAtLogin)
        model.setLaunchAtLogin(false)
        #expect(model.launchAtLogin); #expect(model.errorText?.contains("fixture failure") == true)
    }
    @Test @MainActor func connectionFailureNeverShowsSampleAsRevenueAndCanReturnLive() async throws {
        let fixture = NetworkFixture(fail: true), ks = KeyStore(service: UUID().uuidString)
        defer { ks.delete() }
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, keyStore: ks, start: false, clientFactory: { StripeClient(key: $0, session: fixture.session()) }, loginStatus: false)
        defer { model.stop() }
        try model.setKey(fixture.key)
        #expect(!model.sampleMode); #expect(model.snapshot == nil)
        for _ in 0..<50 { if model.errorText != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.errorText != nil); #expect(model.snapshot == nil)
        model.loadSample(); #expect(model.hasKey()); #expect(model.sampleMode)
        model.goalCents = 30000; #expect(model.snapshot?.goalCents == 30000)
        model.useSavedKey(); #expect(!model.sampleMode); #expect(model.snapshot == nil)
    }
    @Test @MainActor func launchFetchesAndScheduleChangesAndCancels() async throws {
        let fixture = NetworkFixture(), ks = KeyStore(service: UUID().uuidString)
        try ks.save(fixture.key); defer { ks.delete() }
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, keyStore: ks,
            clientFactory: { StripeClient(key: $0, session: fixture.session()) },
            sleep: { interval in fixture.recordInterval(interval); try await Task.sleep(for: .milliseconds(20)) }, loginStatus: false)
        defer { model.stop() }
        for _ in 0..<100 { if fixture.accountRequests() >= 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(fixture.accountRequests() >= 2); #expect(model.snapshot != nil)
        model.refreshInterval = 900
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.lock.withLock { fixture.intervals.contains(900) })
        model.loadSample()
        // A URLSession request already queued before cancellation may reach URLProtocol.
        // The cancelled scheduler must not tick again or replace Sample with that response.
        let ticks = fixture.lock.withLock { fixture.intervals.count }
        try await Task.sleep(for: .milliseconds(80))
        #expect(fixture.lock.withLock { fixture.intervals.count } == ticks)
        #expect(model.sampleMode)
        #expect(model.snapshot?.today.netCents == 2295)
    }
    @Test @MainActor func sampleNotificationButtonsNeedNoCredentials() async {
        var titles: [String] = []
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, keyStore: KeyStore(service: UUID().uuidString), start: false, loginStatus: false, post: { title, _ in titles.append(title) })
        await model.sendSampleNotification(failedPayment: false)
        await model.sendSampleNotification(failedPayment: true)
        #expect(titles == ["Sample first sale", "Sample failed payment"])
    }
    @Test func screenshotsContainRenderedNativeInterface() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for index in 1...3 {
            let url = root.appendingPathComponent(String(format: "store/screenshots/screenshot-%02d.png", index))
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 2880 && image.height == 1800)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
            #expect(text.contains("sample"))
            let required = index == 3 ? ["save key", "monthly goal", "failed payments", "send sample"] : ["yesterday", "refunds", "privacy policy", "quit"]
            for label in required { #expect(text.contains(label), "Missing native interface label: \(label)") }
        }
    }
    @Test func nativeCaptureAndVisiblePanelActionsRegression() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let panel = try String(contentsOf: root.appendingPathComponent("Sources/RevPulse/PopoverView.swift"))
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/RevPulse/SettingsView.swift"))
        let screenshots = try String(contentsOf: root.appendingPathComponent("Sources/RevPulse/NativeScreenshots.swift"))
        #expect(panel.contains("SettingsLink")); #expect(panel.contains("Quit RevPulse"))
        #expect(settings.contains("Return to live data")); #expect(settings.contains("PolicySupportLinks"))
        #expect(screenshots.contains("cacheDisplay(in:")); #expect(!screenshots.contains("scaleEffect"))
        #expect(screenshots.contains("SettingsView(model: model)")); #expect(screenshots.contains("Sample data"))
    }
}
