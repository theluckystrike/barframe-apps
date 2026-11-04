import Foundation
import Testing
@testable import CostBarCore

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
}
private func date(_ text: String) throws -> Date { try UTCClock.parse(text) }
private actor RecordedTransport: HTTPTransport {
    private var replies: [HTTPResult]
    private var requests: [URLRequest] = []
    init(_ replies: [HTTPResult]) { self.replies = replies }
    func get(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !replies.isEmpty else { throw SpendError.invalidResponse }
        return replies.removeFirst()
    }
    func captured() -> [URLRequest] { requests }
}

@Test func openRouterDoesNotDoubleCountBYOK() throws {
    let snapshot = try CostParser.openRouterKey(fixture("openrouter-key"), now: date("2026-10-12T12:00:00Z"))
    #expect(snapshot.monthlyUSD == Decimal(string: "25.5"))
    #expect(snapshot.dailyUSD == Decimal(string: "25.5"))
}
@Test func creditsUseAccountTotals() throws {
    #expect(try CostParser.openRouterCredits(fixture("openrouter-credits")) == Decimal(string: "74.75"))
}
@Test func anthropicConvertsFractionalCentsAndPreservesPagination() throws {
    let page = try CostParser.anthropic(fixture("anthropic"))
    #expect(page.buckets.count == 1)
    #expect(page.buckets[0].usd == Decimal(string: "1.2378912"))
    #expect(page.nextPage == "page_MjAyNS0wNS0xNFQwMDowMDowMFo=")
}
@Test func openAIUsesDollarsAndUnixTime() throws {
    let page = try CostParser.openAI(fixture("openai"))
    #expect(page.buckets[0].usd == Decimal(string: "0.06"))
    #expect(page.buckets[0].start == Date(timeIntervalSince1970: 1730419200))
    #expect(page.nextPage == nil)
}
@Test func rejectsBrokenMoneyAndForeignCurrency() throws {
    let original = String(decoding: try fixture("anthropic"), as: UTF8.self)
    #expect(throws: SpendError.invalidResponse) { try CostParser.anthropic(Data(original.replacingOccurrences(of: "123.78912", with: "invalid").utf8)) }
    #expect(throws: SpendError.unsupportedCurrency) { try CostParser.anthropic(Data(original.replacingOccurrences(of: "USD", with: "EUR").utf8)) }
    #expect(throws: SpendError.invalidResponse) { try CostParser.openAI(Data("{}".utf8)) }
    #expect(throws: SpendError.invalidResponse) { try CostParser.openRouterKey(Data("{\"data\":{\"usage_daily\":-1,\"usage_monthly\":2}}".utf8), now: Date()) }
}
@Test func monthAndTodayExcludeOlderBuckets() throws {
    let now = try date("2025-08-02T12:00:00Z")
    let buckets = try CostParser.anthropic(fixture("anthropic")).buckets + [CostBucket(start: date("2025-07-31T00:00:00Z"), end: date("2025-08-01T00:00:00Z"), usd: 100)]
    let snapshot = try SpendSnapshot.aggregate(provider: .anthropic, buckets: buckets, now: now)
    #expect(snapshot.monthlyUSD == Decimal(string: "1.2378912"))
    #expect(snapshot.dailyUSD == 0)
}
@Test func duplicateBucketsCannotInflateCosts() throws {
    let bucket = try CostParser.openAI(fixture("openai")).buckets[0]
    #expect(throws: SpendError.invalidResponse) {
        try SpendSnapshot.aggregate(provider: .openAI, buckets: [bucket, bucket], now: date("2024-11-02T12:00:00Z"))
    }
}
@Test func leapMonthProjectionAndMidnightClamp() throws {
    let middle = SpendSnapshot(provider: .openAI, fetchedAt: try date("2024-02-15T12:00:00Z"), dailyUSD: 12, monthlyUSD: 29)
    #expect(middle.projectedUSD == 58)
    #expect(middle.hourlyUSD == 1)
    let midnight = SpendSnapshot(provider: .openAI, fetchedAt: try date("2024-02-01T00:00:01Z"), dailyUSD: 1, monthlyUSD: 1)
    #expect(midnight.hourlyUSD == 1)
    #expect(midnight.projectedUSD == nil)
}
@Test func cacheFreshnessChangesAcrossUTCRollover() throws {
    let snapshot = SpendSnapshot(provider: .anthropic, fetchedAt: try date("2026-09-30T23:59:00Z"), dailyUSD: 1, monthlyUSD: 30)
    #expect(snapshot.isStale(at: try date("2026-10-01T00:00:00Z")))
    #expect(!snapshot.isCurrentMonth(at: try date("2026-10-01T00:00:00Z")))
    #expect(!snapshot.isStale(at: try date("2026-09-30T23:59:30Z")))
}
@Test func budgetAlertsUseThresholdAndMonthIdentity() throws {
    let budget = Budget(monthlyUSD: 100, thresholdPercent: 80)
    let early = SpendSnapshot(provider: .openAI, fetchedAt: try date("2026-10-10T12:00:00Z"), dailyUSD: 10, monthlyUSD: 79)
    let reached = SpendSnapshot(provider: .openAI, fetchedAt: early.fetchedAt, dailyUSD: 10, monthlyUSD: 80)
    #expect(budget.alertID(snapshot: early) == nil)
    #expect(budget.alertID(snapshot: reached) == "openAI-2026-10-80")
    #expect(budget.fraction(spend: 120) == 1.2)
    #expect(Budget(monthlyUSD: 0).alertID(snapshot: reached) == nil)
}
@Test func rejectsInvalidBudgetsAndHeaderInjection() throws {
    #expect(Money.parseBudget("100.25") == Decimal(string: "100.25"))
    for bad in ["0", "-1", "NaN", "1,000", "1.234", "abc", "1000000000"] { #expect(Money.parseBudget(bad) == nil) }
    #expect(try ProviderClient.normalizedKey("  test-key\n") == "test-key")
    #expect(throws: SpendError.invalidKey) { try ProviderClient.normalizedKey("key\r\nx-api-key:bad") }
}
@Test func providerRequestsHaveCorrectAuthAndUTCRange() throws {
    let now = try date("2026-10-12T12:00:00Z")
    let request = try ProviderClient.request(provider: .anthropic, key: "test-only-key", now: now, page: "cursor+/=")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-only-key")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    let requestURL = try #require(request.url)
    let query = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first(where: { $0.name == "starting_at" })?.value == "2026-10-01T00:00:00Z")
    #expect(query.first(where: { $0.name == "ending_at" })?.value == "2026-10-13T00:00:00Z")
    #expect(query.first(where: { $0.name == "page" })?.value == "cursor+/=")
    let openAI = try ProviderClient.request(provider: .openAI, key: "test-only-key", now: now)
    #expect(openAI.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-key")
    #expect(openAI.url?.path == "/v1/organization/costs")
}
@Test func usefulErrorsDoNotIncludeServerBodyOrCredentials() {
    for (status, expected) in [(401, SpendError.authentication), (403, .forbidden), (429, .rateLimited), (503, .http(503))] {
        #expect(throws: expected) { try ProviderClient.validateStatus(status) }
    }
}
@Test func openRouterCanTrackSpendWithoutManagementKey() async throws {
    let transport = RecordedTransport([HTTPResult(data: try fixture("openrouter-key"), status: 200), HTTPResult(data: Data(), status: 403)])
    let snapshot = try await ProviderClient(transport: transport).fetch(provider: .openRouter, key: "test-only-key")
    #expect(snapshot.monthlyUSD == Decimal(string: "25.5"))
    #expect(snapshot.remainingCredits == nil)
    #expect(snapshot.creditNote == "Account credits require a management key.")
    let requests = await transport.captured()
    #expect(requests.map { $0.url?.path } == ["/api/v1/key", "/api/v1/credits"])
}
@Test func paginationFetchesAllPagesWithCursor() async throws {
    let final = Data("{\"data\":[],\"has_more\":false,\"next_page\":null}".utf8)
    let transport = RecordedTransport([HTTPResult(data: try fixture("anthropic"), status: 200), HTTPResult(data: final, status: 200)])
    let snapshot = try await ProviderClient(transport: transport).fetch(provider: .anthropic, key: "test-only-key", now: date("2025-08-01T12:00:00Z"))
    #expect(snapshot.monthlyUSD == Decimal(string: "1.2378912"))
    let requests = await transport.captured()
    #expect(requests.count == 2)
    let last = try #require(requests.last?.url)
    #expect(URLComponents(url: last, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "page" }) == true)
}
@Test func repeatedPaginationFailsInsteadOfShowingPartialTotal() async throws {
    let data = try fixture("anthropic")
    let transport = RecordedTransport([HTTPResult(data: data, status: 200), HTTPResult(data: data, status: 200)])
    await #expect(throws: SpendError.pagination) {
        try await ProviderClient(transport: transport).fetch(provider: .anthropic, key: "test-only-key")
    }
}
@Test func missingCursorFails() {
    let payload = Data("{\"data\":[],\"has_more\":true,\"next_page\":null}".utf8)
    #expect(throws: SpendError.pagination) { try CostParser.anthropic(payload) }
}
@Test func localStorePersistsTotalsAndClearsDisconnectedProvider() throws {
    let suite = "CostBarTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = LocalStore(defaults: defaults)
    #expect(store.preferences().alertsEnabled == false)
    let snapshot = try CostParser.openRouterKey(fixture("openrouter-key"), now: Date())
    try store.save(snapshot)
    #expect(store.snapshot(for: .openRouter) == snapshot)
    store.removeSnapshot(for: .openRouter)
    #expect(store.snapshot(for: .openRouter) == nil)
    var prefs = Preferences()
    prefs.selected = .anthropic
    prefs.budgets[Provider.anthropic.rawValue] = Budget(monthlyUSD: 250, thresholdPercent: 90)
    try store.save(prefs)
    #expect(store.preferences().selected == .anthropic)
    #expect(store.preferences().budget(for: .anthropic).monthlyUSD == 250)
}
@Test func publicModelsCheckValidatesRealResponseShapeWithoutNetwork() async throws {
    let transport = RecordedTransport([HTTPResult(data: Data("{\"data\":[{\"id\":\"documented-model-id\"}]}".utf8), status: 200)])
    let result = try await ProviderClient(transport: transport).publicModelsCheck()
    #expect(result.status == 200)
    #expect(result.modelCount == 1)
    let requests = await transport.captured()
    #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func menuBarValueFitsSixCharactersIncludingCredits() {
    for value in [-1000000, -999999, -999, 0, 999, 999999, 1000000] {
        #expect(Money.short(Decimal(value)).count <= 6)
    }
    #expect(Money.short(-999999) == "$-999k")
    #expect(Money.short(-1000000) == "$-1M+")
}

@Test func changingBudgetAmountDoesNotResetAlertIdentity() throws {
    let snapshot = SpendSnapshot(provider: .openAI, fetchedAt: try date("2026-10-12T12:00:00Z"), dailyUSD: 10, monthlyUSD: 90)
    let id = try #require(Budget(monthlyUSD: 100, thresholdPercent: 80).alertID(snapshot: snapshot))
    #expect(Budget(monthlyUSD: 50, thresholdPercent: 80).alertID(snapshot: snapshot) == id)
    #expect(Budget(monthlyUSD: 50, thresholdPercent: 90).alertID(snapshot: snapshot) != id)
    let nextMonth = SpendSnapshot(provider: .openAI, fetchedAt: try date("2026-11-12T12:00:00Z"), dailyUSD: 10, monthlyUSD: 90)
    #expect(Budget(monthlyUSD: 50).alertID(snapshot: nextMonth) != id)
    let otherProvider = SpendSnapshot(provider: .anthropic, fetchedAt: snapshot.fetchedAt, dailyUSD: 10, monthlyUSD: 90)
    #expect(Budget(monthlyUSD: 50).alertID(snapshot: otherProvider) != id)
}

private struct WorkerCredentialStore: CredentialStore {
    func read(_ account: String) throws -> String? { Thread.isMainThread ? "main" : "worker" }
    func save(_ value: String, account: String) throws { if Thread.isMainThread { throw SpendError.invalidKey } }
    func delete(_ account: String) throws { if Thread.isMainThread { throw SpendError.invalidKey } }
}
@Test @MainActor func keychainOperationsLeaveTheUIThread() async throws {
    let keys = AsyncKeyStore(store: WorkerCredentialStore())
    #expect(try await keys.read("test") == "worker")
    try await keys.save("test-only", account: "test")
    try await keys.delete("test")
}
