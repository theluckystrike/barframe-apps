import Foundation
import Testing
import CostBarCore
@testable import CostBarApp

private let auditRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private func sampleReports() throws -> [Provider: SpendSnapshot] {
    try SampleData.load(fixture: { try Data(contentsOf: auditRoot.appendingPathComponent("Tests/CostBarCoreTests/Fixtures/\($0).json")) })
}
private final class RecordingCredentials: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    private var actions: [String] = []
    var recorded: [String] { lock.lock(); defer { lock.unlock() }; return actions }
    var count: Int { lock.lock(); defer { lock.unlock() }; return storage.count }
    func read(_ account: String) throws -> String? { lock.lock(); defer { lock.unlock() }; actions.append("read"); return storage[account] }
    func save(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; actions.append(storage[account] == nil ? "add" : "update"); storage[account] = value }
    func delete(_ account: String) throws { lock.lock(); defer { lock.unlock() }; actions.append("delete"); storage[account] = nil }
}

@Test @MainActor func expandedCreditsNeverHideOtherProviderMetrics() throws {
    let model = AppModel()
    model.enterSample(load: sampleReports)
    model.focusCredits = true
    #expect(model.showingExpandedCredits)
    model.select(.anthropic)
    #expect(!model.focusCredits)
    #expect(!model.showingExpandedCredits)
    #expect(model.snapshot?.dailyUSD != nil)
    #expect(model.snapshot?.hourlyUSD != nil)
    // Even a stale view state cannot conceal metrics for a provider without a balance.
    model.focusCredits = true
    #expect(!model.showingExpandedCredits)
    model.select(.openAI)
    #expect(!model.showingExpandedCredits)
    model.select(.openRouter)
    #expect(!model.focusCredits)
}

@Test @MainActor func sampleConnectionExercisesVaultWithoutLiveCredentialsOrNetwork() async throws {
    let live = RecordingCredentials(), demo = RecordingCredentials()
    let model = AppModel(keys: AsyncKeyStore(store: live), sampleKeys: AsyncKeyStore(store: demo), fetch: { _, _, _ in
        Issue.record("Sample must never call the live transport")
        throw SpendError.invalidResponse
    })
    model.connected = [.openAI]
    model.enterSample(load: sampleReports)
    #expect(model.connected.isEmpty)
    #expect(!(await model.saveKey("private-real-key", provider: .openRouter)))
    #expect(demo.count == 0)
    for provider in Provider.allCases {
        #expect(await model.saveKey(AppModel.sampleKey, provider: provider))
        #expect(await model.saveKey(AppModel.sampleKey, provider: provider))
        model.select(provider)
        model.snapshots[provider] = nil
        model.refresh(provider)
        #expect(model.snapshot?.provider == provider)
        await model.removeKey(provider)
        #expect(model.snapshot == nil)
        #expect(!model.connected.contains(provider))
    }
    #expect(demo.recorded == Array(repeating: ["add", "read", "update", "read", "delete"], count: 3).flatMap { $0 })
    #expect(live.recorded.isEmpty)
    #expect(demo.count == 0)
    #expect(await model.saveKey(AppModel.sampleKey, provider: .openRouter))
    model.leaveSample()
    model.stop()
    #expect(model.connected.contains(.openAI))
    for _ in 0..<100 where demo.count != 0 { try await Task.sleep(nanoseconds: 5_000_000) }
    #expect(demo.count == 0)
    #expect(!model.sample)
}

@Test @MainActor func sampleOSNotificationUsesRealActionAndPreservesLivePreferences() async throws {
    let model = AppModel(requestSampleNotification: { true })
    model.preferences.alertsEnabled = false
    let originalIDs = model.preferences.deliveredAlertIDs
    model.enterSample(load: sampleReports)
    await model.testSampleNotification()
    #expect(model.notificationMessage?.contains("notification sent to macOS") == true)
    #expect(!model.sampleNotificationInFlight)
    model.leaveSample(); model.stop()
    #expect(!model.preferences.alertsEnabled)
    #expect(model.preferences.deliveredAlertIDs == originalIDs)
}
@Test @MainActor func sampleNotificationDenialAndFailureRemainRecoverable() async throws {
    let denied = AppModel(requestSampleNotification: { false })
    denied.enterSample(load: sampleReports)
    await denied.testSampleNotification()
    #expect(denied.notificationMessage?.contains("System Settings") == true)
    #expect(!denied.sampleNotificationInFlight)
    let failed = AppModel(requestSampleNotification: { throw CocoaError(.userCancelled) })
    failed.enterSample(load: sampleReports)
    await failed.testSampleNotification()
    #expect(failed.notificationMessage?.hasPrefix("Sample notification failed:") == true)
    #expect(!failed.sampleNotificationInFlight)
}

@Test func bothDocumentRoutesRejectUnresolvedDomainsAndOpenFinalConfiguredURLs() throws {
    func withBundle(_ privacy: String, _ support: String, check: (Bundle) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let info = ["CFBundleIdentifier": "com.test." + UUID().uuidString, "MASPrivacyPolicyURL": privacy, "MASSupportURL": support]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: folder.appendingPathComponent("Info.plist"))
        try check(#require(Bundle(url: folder)))
    }
    try withBundle("https://{DOMAIN}/costbar/privacy/", "https://{DOMAIN}/costbar/support/") {
        #expect(CostBarLinks.privacyPolicy($0) == nil)
        #expect(CostBarLinks.support($0) == nil)
    }
    try withBundle("https://example.org/costbar/privacy/", "https://example.org/costbar/support/") {
        #expect(CostBarLinks.privacyPolicy($0)?.absoluteString == "https://example.org/costbar/privacy/")
        #expect(CostBarLinks.support($0)?.absoluteString == "https://example.org/costbar/support/")
    }
    try withBundle("https://barframe.com/apps/costbar/privacy/", "https://barframe.com/apps/costbar/support/") {
        #expect(CostBarLinks.privacyPolicy($0)?.absoluteString == "https://barframe.com/apps/costbar/privacy/")
        #expect(CostBarLinks.support($0)?.absoluteString == "https://barframe.com/apps/costbar/support/")
    }
    try withBundle("http://example.org/costbar/privacy/", "https://example.org/other/support/") {
        #expect(CostBarLinks.privacyPolicy($0) == nil)
        #expect(CostBarLinks.support($0) == nil)
    }
    #expect(try LocalPrivacyPolicy.load().count > 300)
    #expect(try LocalSupport.load().contains("Michael Lip"))
}

@Test func reviewNotesNeedNoPrivateCredentialsAndSelectedFieldsMatch() throws {
    let listing = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: auditRoot.appendingPathComponent("store/listing.json"))) as? [String: Any])
    let selectedFile = auditRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("store-drafts/SELECTED.json")
    let selected = try #require((JSONSerialization.jsonObject(with: Data(contentsOf: selectedFile)) as? [String: [String: Any]])?["api-spend-meter"])
    for field in ["subtitle", "keywords", "promotional_text"] {
        #expect(listing[field] as? String == (selected[field] as? String)?.replacingOccurrences(of: "{APP}", with: "CostBar"))
    }
    let notes = try #require(listing["review_notes"] as? String)
    #expect(notes.contains("Fill sample key"))
    #expect(notes.contains("Send Sample notification"))
    #expect(!notes.contains("use your own"))
    #expect(listing["copyright"] as? String == "2026 Michael Lip")
    let source = try String(contentsOf: auditRoot.appendingPathComponent("Sources/CostBarApp/Verification.swift"), encoding: .utf8)
    #expect(source.contains("See when budget thresholds are reached."))
    #expect(!source.contains("Stay ahead"))
}
