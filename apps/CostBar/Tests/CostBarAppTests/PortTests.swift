import Foundation
import Testing
import UserNotifications
import MASKit
import CostBarCore
@testable import CostBarApp

private struct TestCredentials: CredentialStore {
    func read(_ account: String) throws -> String? { "test-only" }
    func save(_ value: String, account: String) throws {}
    func delete(_ account: String) throws {}
}
@MainActor private final class HeldReports {
    var now: Date
    var requests: [(Provider, Date, CheckedContinuation<SpendSnapshot, Error>)] = []
    init(_ date: Date) { now = date }
    func fetch(_ provider: Provider, _ key: String, _ date: Date) async throws -> SpendSnapshot {
        try await withCheckedThrowingContinuation { requests.append((provider, date, $0)) }
    }
    func complete(_ index: Int, spend: Decimal) {
        let request = requests[index]
        request.2.resume(returning: SpendSnapshot(provider: request.0, fetchedAt: request.1, dailyUSD: spend, monthlyUSD: spend))
    }
    func waitFor(_ count: Int) async throws {
        for _ in 0..<200 where requests.count < count { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(requests.count >= count)
        guard requests.count >= count else { throw SpendError.invalidResponse }
    }
}
@MainActor private func waitUntilIdle(_ model: AppModel) async throws {
    for _ in 0..<200 where !model.refreshing.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
    #expect(model.refreshing.isEmpty)
}
@Test func dailyCacheExpiresAtMidnightWithinOneMinute() throws {
    let before = try UTCClock.parse("2026-10-15T23:59:50Z")
    let after = try UTCClock.parse("2026-10-16T00:00:05Z")
    let value = SpendSnapshot(provider: .openAI, fetchedAt: before, dailyUSD: 99, monthlyUSD: 100)
    #expect(value.isCurrentMonth(at: after))
    #expect(!value.isCurrentDay(at: after))
    #expect(value.isStale(at: after))
}
@Test @MainActor func dailyDisplayDisappearsBeforePeriodTimerFires() throws {
    let held = HeldReports(try UTCClock.parse("2026-10-15T23:59:50Z"))
    let model = AppModel(clock: { held.now })
    model.preferences.selected = .openAI
    model.snapshots[.openAI] = SpendSnapshot(provider: .openAI, fetchedAt: held.now, dailyUSD: 99, monthlyUSD: 100)
    #expect(model.snapshot != nil)
    held.now = try UTCClock.parse("2026-10-16T00:00:05Z")
    #expect(model.snapshot == nil)
    #expect(model.forecast == nil)
}
@Test @MainActor func heldPreWakeResponseCannotOverwriteNewReport() async throws {
    let held = HeldReports(try UTCClock.parse("2026-10-16T12:00:00Z"))
    let model = AppModel(keys: AsyncKeyStore(store: TestCredentials()), clock: { held.now }, fetch: held.fetch)
    defer { model.stop() }
    model.preferences.selected = .openAI
    model.connected = [.openAI]
    model.refresh(.openAI)
    try await held.waitFor(1)
    model.reportingBoundaryChanged(wake: true)
    #expect(model.snapshot == nil)
    try await held.waitFor(2)
    held.complete(1, spend: 7)
    try await waitUntilIdle(model)
    held.complete(0, spend: 99)
    try await Task.sleep(nanoseconds: 20_000_000)
    #expect(model.snapshot?.dailyUSD == 7)
}
@Test @MainActor func heldResponseAcrossMidnightStartsANewReport() async throws {
    let held = HeldReports(try UTCClock.parse("2026-10-15T23:59:50Z"))
    let model = AppModel(keys: AsyncKeyStore(store: TestCredentials()), clock: { held.now }, fetch: held.fetch)
    defer { model.stop() }
    model.preferences.selected = .openAI
    model.connected = [.openAI]
    model.refresh(.openAI)
    try await held.waitFor(1)
    held.now = try UTCClock.parse("2026-10-16T00:00:05Z")
    held.complete(0, spend: 99)
    try await held.waitFor(2)
    #expect(model.snapshot == nil)
    held.complete(1, spend: 0)
    try await waitUntilIdle(model)
    #expect(model.snapshot?.dailyUSD == 0)
    #expect(model.snapshot?.fetchedAt == held.now)
}
@Test func forecastGuardUsesThreeDaysAndTenPercentOfMonth() throws {
    for text in ["2026-10-01T00:00:01Z", "2026-10-04T00:00:00Z", "2024-02-03T23:59:59Z"] {
        #expect(SpendSnapshot(provider: .openAI, fetchedAt: try UTCClock.parse(text), dailyUSD: 1, monthlyUSD: 10).projectedUSD == nil)
    }
    let sufficient = SpendSnapshot(provider: .openAI, fetchedAt: try UTCClock.parse("2026-10-04T02:24:00Z"), dailyUSD: 1, monthlyUSD: 10)
    #expect(sufficient.projectedUSD == 100)
    #expect(Budget(monthlyUSD: 10).alertID(snapshot: sufficient) != nil)
    let earlyReached = SpendSnapshot(provider: .openAI, fetchedAt: try UTCClock.parse("2026-10-01T12:00:00Z"), dailyUSD: 10, monthlyUSD: 10)
    #expect(earlyReached.projectedUSD == nil)
    #expect(Budget(monthlyUSD: 10).alertID(snapshot: earlyReached) != nil)
}
@Test @MainActor func forecastHiddenDuringRefreshFailureAndStaleness() throws {
    let now = try UTCClock.parse("2026-10-16T12:00:00Z")
    let model = AppModel(clock: { now })
    model.preferences.selected = .openAI
    model.snapshots[.openAI] = SpendSnapshot(provider: .openAI, fetchedAt: now, dailyUSD: 10, monthlyUSD: 50)
    #expect(model.forecast == 100)
    model.refreshing.insert(.openAI)
    #expect(model.forecast == nil)
    #expect(model.forecastText == "Updating…")
    model.refreshing = []
    model.errors[.openAI] = "Report incomplete"
    #expect(model.forecast == nil)
    #expect(model.forecastText == "Incomplete report")
    model.errors = [:]
    model.snapshots[.openAI] = SpendSnapshot(provider: .openAI, fetchedAt: now.addingTimeInterval(-901), dailyUSD: 10, monthlyUSD: 50)
    #expect(model.forecast == nil)
}
@Test func foregroundAlertsPresentBannerAndSound() {
    #expect(AppDelegate.foregroundOptions.contains(.banner))
    #expect(AppDelegate.foregroundOptions.contains(.sound))
}
@Test func weeklyAndLifetimeRemainSeparateFromCredits() throws {
    let input = Data(#"{"data":{"usage_daily":1,"usage_monthly":20,"usage_weekly":7,"usage":90,"byok_usage":1000}}"#.utf8)
    let snapshot = try CostParser.openRouterKey(input, now: Date())
    #expect(snapshot.weeklyUSD == 7)
    #expect(snapshot.lifetimeUSD == 90)
    #expect(snapshot.monthlyUSD == 20)
    #expect(snapshot.remainingCredits == nil)
    let absent = try CostParser.openRouterKey(Data(#"{"data":{"usage_daily":1,"usage_monthly":20}}"#.utf8), now: Date())
    #expect(absent.weeklyUSD == nil)
    #expect(absent.lifetimeUSD == nil)
    #expect(throws: SpendError.invalidResponse) {
        try CostParser.openRouterKey(Data(#"{"data":{"usage_daily":1,"usage_monthly":20,"usage_weekly":-1}}"#.utf8), now: Date())
    }
}
@Test @MainActor func coverageNamesFailuresAndNeverSumsScopes() throws {
    let now = try UTCClock.parse("2026-10-16T12:00:00Z")
    let model = AppModel(clock: { now })
    model.preferences.selected = .openAI
    model.connected = [.openAI, .anthropic]
    model.snapshots[.openAI] = SpendSnapshot(provider: .openAI, fetchedAt: now, dailyUSD: 1, monthlyUSD: 10)
    model.errors[.anthropic] = "Key rejected"
    #expect(model.coverageText == "1 of 2 connected providers current")
    #expect(model.connectionIssues == "Anthropic: Key rejected")
    #expect(model.snapshot?.monthlyUSD == 10)
}
@Test func nullCostsRemainRejectedRatherThanInventingZero() {
    let input = Data(#"{"data":[{"start_time":0,"end_time":86400,"results":[{"amount":{"value":null,"currency":"usd"}}]}],"has_more":false}"#.utf8)
    #expect(throws: SpendError.invalidResponse) { try CostParser.openAI(input) }
}
@Test @MainActor func privacyRouteUsesKitConfigurationAndRejectsWrongPath() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let info: [String: Any] = ["CFBundleIdentifier": "com.test.links", "MASPrivacyPolicyURL": "https://example.org/costbar/privacy/"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: folder.appendingPathComponent("Info.plist"))
    let bundle = try #require(Bundle(url: folder))
    #expect(CostBarLinks.privacyPolicy(bundle)?.absoluteString == "https://example.org/costbar/privacy/")
    let wrongFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
    try FileManager.default.createDirectory(at: wrongFolder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: wrongFolder) }
    let wrongInfo: [String: Any] = ["CFBundleIdentifier": "com.test.wronglinks", "MASPrivacyPolicyURL": "https://example.org/wrong/privacy/"]
    try PropertyListSerialization.data(fromPropertyList: wrongInfo, format: .xml, options: 0).write(to: wrongFolder.appendingPathComponent("Info.plist"))
    #expect(CostBarLinks.privacyPolicy(try #require(Bundle(url: wrongFolder))) == nil)
}
