import Foundation
import ServiceManagement
import Testing
import CostBarCore
@testable import CostBarApp

private let appRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private func json(_ path: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: appRoot.appendingPathComponent(path))) as? [String: Any])
}
private struct EmptyCredentials: CredentialStore {
    func read(_ account: String) throws -> String? { nil }
    func save(_ value: String, account: String) throws { throw SpendError.invalidKey }
    func delete(_ account: String) throws {}
}
private struct DeniedCredentials: CredentialStore {
    func read(_ account: String) throws -> String? { throw KeychainError(status: -25293) }
    func save(_ value: String, account: String) throws { throw SpendError.invalidKey }
    func delete(_ account: String) throws {}
}

@Test func privacyAndSupportSubmissionURLsMatch() throws {
    let manifest = try json("mas.json"), listing = try json("store/listing.json")
    let info = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: appRoot.appendingPathComponent("Resources/Info.plist")), format: nil) as? [String: Any])
    #expect(manifest["bundle_id"] as? String == "com.michaellip.costbar")
    #expect(manifest["bundle_id"] as? String == info["CFBundleIdentifier"] as? String)
    for (manifestKey, listingKey, uploadKey, suffix) in [("privacy_url", "privacy_policy", "privacyPolicyUrl", "privacy/"), ("support_url", "support", "supportUrl", "support/")] {
        let expected = "https://barframe.com/apps/costbar/" + suffix
        #expect(manifest[manifestKey] as? String == expected)
        #expect(listing[listingKey] as? String == expected)
        #expect(listing[uploadKey] as? String == expected)
    }
}

@Test func privacyLinksRemainInBothUIRoutes() throws {
    let views = try String(contentsOf: appRoot.appendingPathComponent("Sources/CostBarApp/Views.swift"), encoding: .utf8)
    #expect(views.components(separatedBy: "DocumentLinksView()").count == 3)
    let documents = try String(contentsOf: appRoot.appendingPathComponent("Sources/CostBarApp/PrivacyPolicyView.swift"), encoding: .utf8)
    #expect(documents.contains("CostBarLinks.privacyPolicy()"))
    #expect(documents.contains("CostBarLinks.support()"))
}

@Test @MainActor func sampleModeCoversEveryProviderAndRestoresLiveState() throws {
    let model = AppModel(keys: AsyncKeyStore(store: EmptyCredentials()))
    let original = model.preferences
    model.enterSample {
        try SampleData.load(fixture: { name in
            try Data(contentsOf: appRoot.appendingPathComponent("Tests/CostBarCoreTests/Fixtures/\(name).json"))
        })
    }
    #expect(model.sample)
    #expect(model.state == "Sample data")
    for provider in Provider.allCases {
        model.select(provider)
        let snapshot = try #require(model.snapshot)
        #expect(snapshot.provider == provider)
        #expect(snapshot.isCurrentMonth(at: Date()))
        #expect(snapshot.monthlyUSD > 0)
        #expect(snapshot.hourlyUSD >= 0)
        #expect(snapshot.projectedUSD.map { $0 >= snapshot.monthlyUSD } ?? true)
        #expect(model.refreshing.isEmpty)
    }
    #expect(model.snapshots[.openRouter]?.remainingCredits == Decimal(string: "74.75"))
    model.saveBudget("20", threshold: 80, provider: .openRouter)
    model.setAlerts(true)
    #expect(model.notificationMessage?.hasPrefix("Sample ·") == true)
    #expect(model.preferences.deliveredAlertIDs.count == 1)
    model.saveBudget("10", threshold: 80, provider: .openRouter)
    #expect(model.preferences.deliveredAlertIDs.count == 1)
    model.leaveSample()
    model.stop()
    #expect(!model.sample)
    #expect(model.preferences.selected == original.selected)
    #expect(model.preferences.budgets == original.budgets)
    #expect(model.preferences.alertsEnabled == original.alertsEnabled)
    #expect(model.preferences.deliveredAlertIDs == original.deliveredAlertIDs)
}

@Test @MainActor func sampleRejectsRealProviderKeys() async {
    let model = AppModel(sample: true, keys: AsyncKeyStore(store: DeniedCredentials()))
    #expect(await model.saveKey("test-only", provider: .openRouter) == false)
    #expect(model.settingsMessage?.contains("Use Fill sample key") == true)
    await model.removeKey(.openRouter)
    #expect(model.connected.isEmpty)
}

@Test @MainActor func keychainDenialAppearsWithoutBlockingInitialization() async throws {
    let model = AppModel(keys: AsyncKeyStore(store: DeniedCredentials()))
    #expect(model.errors.isEmpty)
    model.start()
    for _ in 0..<100 where model.errors.count < Provider.allCases.count {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    model.stop()
    #expect(model.errors.count == Provider.allCases.count)
    #expect(model.state == "Needs attention")
    #expect(model.errors.values.allSatisfy { $0.contains("Keychain access was not authorized") })
}

@Test @MainActor func pendingLoginApprovalRemainsOnAndCancelable() {
    #expect(AppModel.loginRequested(.requiresApproval))
    #expect(AppModel.loginRequested(.enabled))
    #expect(!AppModel.loginRequested(.notRegistered))
    #expect(!AppModel.loginRequested(.notFound))
}

@Test func reviewRouteUsesSampleUIWithoutPrivateFiles() throws {
    let notes = try #require(json("store/listing.json")["review_notes"] as? String)
    #expect(notes.contains("Try with sample data"))
    #expect(notes.contains("Command-comma"))
    #expect(notes.contains("Account credits left"))
    #expect(!notes.contains("Tests/"))
    #expect(!notes.contains("--smoke"))
}

@Test func storeOpeningSentenceIsNotDuplicated() throws {
    let description = try #require(json("store/listing.json")["description"] as? String)
    let opening = "CostBar shows reported AI API costs in your menu bar."
    #expect(description.components(separatedBy: opening).count == 2)
    #expect(!description.contains("reported or projected spending crosses"))
}

@Test func localPrivacyMatchesStorePolicyAndIsOfferedInBothRoutes() throws {
    let storePolicy = try String(contentsOf: appRoot.appendingPathComponent("store/privacy.md"), encoding: .utf8)
    let bundledPolicy = try String(contentsOf: appRoot.appendingPathComponent("Sources/CostBarApp/PrivacyPolicy.txt"), encoding: .utf8)
    #expect(bundledPolicy == storePolicy)
    let views = try String(contentsOf: appRoot.appendingPathComponent("Sources/CostBarApp/Views.swift"), encoding: .utf8)
    #expect(views.components(separatedBy: "DocumentLinksView()").count == 3)
    #expect(try LocalPrivacyPolicy.load() == storePolicy)
    #expect(try LocalSupport.load().contains("Fill sample key"))
}
