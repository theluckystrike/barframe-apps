import Foundation
import AppKit
import Testing
import NameWeaveCore
@testable import NameWeave

@MainActor @Test func liveDoesNotReuseSampleResults() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json")); model.toggleSample(true)
    #expect(model.sample); #expect(model.scan?.entries.count == Weave.sample.entries.count)
    model.resolve(); #expect(model.ready)
    model.toggleSample(false); #expect(!model.sample); #expect(model.scan == nil); #expect(!model.ready)
}
@MainActor @Test func sampleDoesNotOverwriteSavedLiveState() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json")
    var state = SavedState(); state.rootLabel = "Live fixture"; state.scan = Scan(entries: [Entry("real.txt")]); state.policy.prefix = "Chosen prefix"
    try StateStore.save(state, to: url)
    let model = AppModel(stateURL: url); model.toggleSample(true); model.policy.prefix = "Sample prefix"; model.updatePolicy(); model.resolve()
    let saved = try StateStore.load(url)
    #expect(saved.rootLabel == state.rootLabel); #expect(saved.scan?.entries == state.scan?.entries); #expect(saved.policy == state.policy)
    model.toggleSample(false); #expect(model.rootLabel == "Live fixture"); #expect(model.policy.prefix == "Chosen prefix"); #expect(model.stale)
}
@MainActor @Test func restoredResultStartsStale() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json"); var state = SavedState(); state.scan = Scan(entries: [Entry("real.txt")]); try StateStore.save(state, to: url)
    let model = AppModel(stateURL: url); #expect(model.stale); #expect(!model.ready); #expect(model.badge == "?")
}
@MainActor @Test func corruptStateHasRecoveryMessage() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json"); try Data("bad".utf8).write(to: url)
    let model = AppModel(stateURL: url); #expect(model.error != nil); #expect(!model.ready)
}
@MainActor @Test func forgetRemovesBookmarkAndPlan() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json"); var state = SavedState(); state.bookmark = Data([1,2]); state.scan = Scan(entries: [Entry("old.txt")]); state.rootLabel = "Old"; try StateStore.save(state, to: url)
    let model = AppModel(stateURL: url); model.forget()
    let loaded = try StateStore.load(url); #expect(loaded.bookmark == nil); #expect(loaded.scan == nil); #expect(loaded.edits.isEmpty); #expect(model.rootLabel.isEmpty)
}
@MainActor @Test func policyChangeRecomputesWithoutStalingLive() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json")); model.scan = Scan(entries: [Entry("safe.txt")]); model.policy.prefix = "new"; model.updatePolicy(); #expect(!model.stale); #expect(model.ready); #expect(model.plan.rows.first?.length == "new\\safe.txt".utf16.count)
}

@MainActor @Test func rescanKeepsEditsOnlyForExistingPaths() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json"))
    model.scan = Scan(entries: [Entry("safe.txt"), Entry("gone.txt")])
    model.edits = [Entry("safe.txt").id: "chosen.txt", Entry("gone.txt").id: "old.txt"]
    model.acceptScan(Scan(entries: [Entry("safe.txt"), Entry("bad?.txt")]))
    #expect(model.edits[Entry("safe.txt").id] == "chosen.txt")
    #expect(model.edits[Entry("gone.txt").id] == nil)
    #expect(model.edits[Entry("bad?.txt").id] == "bad_.txt")
    #expect(!model.stale)
}
@MainActor @Test func proposalConflictsSetMenuWarning() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json"))
    model.scan = Scan(entries: [Entry("safe.txt")]); model.edit(Entry("safe.txt"), value: "bad?")
    #expect(model.plan.issueCount == 0); #expect(model.plan.unresolvedCount == 1)
    #expect(model.status == model.l("Issues", "Problemas")); #expect(model.badge == "!"); #expect(!model.ready)
    model.persist()
}
@MainActor @Test func sampleExclusionsRequireRescanAndBlockReady() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json")); model.toggleSample(true)
    model.edit(Entry("notes.txt"), value: "handwritten.txt")
    model.exclusionsText = "archive"; #expect(model.stale)
    model.rescan(); model.resolve()
    #expect(!model.scan!.entries.contains { $0.path.hasPrefix("archive") })
    #expect(model.scan!.coverage.omissions.contains("Excluded directory archive")); #expect(!model.ready)
    #expect(model.edits[Entry("notes.txt").id] == "handwritten.txt")
}
@MainActor @Test func policyFieldsFollowResetModeSwitchAndDeletion() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json"); var state = SavedState()
    state.policy.legacyBudget = 90; state.policy.exclusions = ["live"]
    try StateStore.save(state, to: url)
    let model = AppModel(stateURL: url); model.toggleSample(true); model.budgetText = "5"; model.exclusionsText = "archive"
    model.resetSample(); #expect(model.budgetText.isEmpty); #expect(model.exclusionsText.isEmpty)
    model.toggleSample(false); #expect(model.budgetText == "90"); #expect(model.exclusionsText == "live")
    model.clearLocalData(); #expect(model.budgetText.isEmpty); #expect(model.exclusionsText.isEmpty); #expect(model.shortcutKey.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
@MainActor @Test func nonExclusionPoliciesPreserveEditableResult() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json"))
    model.acceptScan(Scan(entries: [Entry("safe.txt")]))
    model.edit(Entry("safe.txt"), value: "custom.txt")
    model.budgetText = "5"; model.policy.normalize = false; model.policy.prefix = "destination"; model.updatePolicy()
    #expect(!model.stale); #expect(model.edits[Entry("safe.txt").id] == "custom.txt"); #expect(!model.ready)
    model.exclusionsText = "subtree"; #expect(model.stale)
    model.persist()
}
@MainActor @Test func planReadsAreCachedAndEditsAreDebounced() async throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json"))
    model.acceptScan(Scan(entries: (0..<20_000).map { Entry("file\($0).txt") }))
    let builds = model.planBuildCount
    for _ in 0..<8 { _ = model.plan.rows.count; _ = model.status; _ = model.badge }
    #expect(model.planBuildCount == builds)
    let saves = model.saveCount
    model.edit(Entry("file0.txt"), value: "one.txt"); model.edit(Entry("file0.txt"), value: "two.txt")
    #expect(model.saveCount == saves)
    try await Task.sleep(for: .milliseconds(550))
    #expect(model.saveCount == saves + 1)
    #expect(try StateStore.load(root.appendingPathComponent("state.json")).edits[Entry("file0.txt").id] == "two.txt")
}
@MainActor @Test func bookmarkRenewalKeepsResolvedAccessAndPersistsRefresh() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json"); var state = SavedState(); state.bookmark = Data([1]); state.scan = Scan(entries: [Entry("old.txt")])
    try StateStore.save(state, to: url)
    var renewals = 0
    let refreshed = try BookmarkAccess.refreshIfStale(Data([1]), stale: true) { renewals += 1; return Data([2]) }
    let model = AppModel(stateURL: url, restoreBookmark: { _ in (root, refreshed) })
    #expect(renewals == 1); #expect(model.error == nil); #expect(model.stale)
    #expect(try StateStore.load(url).bookmark == Data([2]))
    let unchanged = try BookmarkAccess.refreshIfStale(Data([2]), stale: false) { renewals += 1; return Data([3]) }
    #expect(unchanged == Data([2])); #expect(renewals == 1)
}
@MainActor @Test func unavailableBookmarkHasFolderRecoveryMessage() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json"); var state = SavedState(); state.bookmark = Data([1]); state.scan = Scan(entries: [Entry("old.txt")])
    try StateStore.save(state, to: url)
    let model = AppModel(stateURL: url, restoreBookmark: { _ in throw CocoaError(.fileNoSuchFile) })
    #expect(model.error?.contains("Saved folder") == true); #expect(model.error?.contains("Saved state") == false)
    #expect(model.scan?.entries == state.scan?.entries); #expect(model.stale)
}
@MainActor @Test func activationInvalidatesLiveButKeepsSample() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json"))
    model.acceptScan(Scan(entries: [Entry("safe.txt")]))
    model.markStaleOnReturn(); #expect(model.stale); #expect(model.badge == "?")
    model.toggleSample(true); model.markStaleOnReturn(); #expect(!model.stale)
}
@Test func hiddenChurnDoesNotInvalidateVisibleNames() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent("visible.txt"))
    let names = try InputMonitor.fingerprint(root)
    try Data("Finder".utf8).write(to: root.appendingPathComponent(".DS_Store"))
    #expect(!InputMonitor.namesChanged(root, since: names))
    try Data().write(to: root.appendingPathComponent("new.txt"))
    #expect(InputMonitor.namesChanged(root, since: names))
}
@Test func incompleteObservationIsExposed() {
    #expect(InputMonitor.isLimited(129, watched: 129))
    #expect(InputMonitor.isLimited(2, watched: 2))
    #expect(!InputMonitor.isLimited(2, watched: 3))
}
@MainActor @Test func launchInstallsStatusWithoutDetailWindow() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    _ = NSApplication.shared
    let delegate = AppDelegate(model: AppModel(stateURL: root.appendingPathComponent("state.json")))
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    #expect(delegate.isStatusInstalled); #expect(!delegate.hasDetailWindow)
    delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
}
@MainActor @Test func defaultShortcutDoesNotRegisterAKey() { #expect(AppModel.defaultShortcutKey.isEmpty) }
@Test func provisionalLinksUseLocalFallback() {
    #expect(PolicyButton.usableURL("https://{DOMAIN}/apps/nameweave/privacy/") == nil)
    #expect(PolicyButton.usableURL(nil) == nil)
    #expect(PolicyButton.usableURL("https://barframe.com/apps/nameweave/privacy/") != nil)
}
func temporaryAppDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor @Test func policyEditorsAllowIncompleteInputAndResetIt() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(stateURL: root.appendingPathComponent("state.json")); model.toggleSample(true)
    model.exclusionsText = "archive,"; #expect(model.exclusionsText == "archive,")
    model.exclusionsText += "Design."; #expect(model.policy.exclusions == ["archive", "Design."])
    model.budgetText = "invalid"; #expect(model.budgetText == "invalid"); #expect(model.policy.legacyBudget == nil)
    model.resetSample(); #expect(model.budgetText.isEmpty); #expect(model.exclusionsText.isEmpty)
}

@Test func initialReleaseNeverOffersLoginLaunch() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sources = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Sources/NameWeave"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
    for source in sources {
        let text = try String(contentsOf: source)
        #expect(!text.contains("SMAppService")); #expect(!text.contains("Launch at login"))
    }
    for file in ["store/listing.json", "store/privacy.md", "store/review_notes.md"] {
        #expect(!(try String(contentsOf: root.appendingPathComponent(file))).localizedCaseInsensitiveContains("launch at login"))
    }
}

@Test func bundledPoliciesLoadFromShippingResourcesDirectory() throws {
    let root = try temporaryAppDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let bundle = root.appendingPathComponent("NameWeave_NameWeave.bundle")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try Data("Bundled privacy fixture".utf8).write(to: bundle.appendingPathComponent("privacy.md"))
    #expect(PolicyButton.bundledText("privacy", resourceDirectory: root) == "Bundled privacy fixture")
    #expect(PolicyButton.bundledText("support", resourceDirectory: nil).contains("Michael Lip"))
}
