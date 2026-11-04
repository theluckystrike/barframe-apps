import Foundation
import Testing
import LedgerCore
@testable import NativeLedger

// MARK: fakes

final class FakeWatch: FolderWatching {
    private(set) var stopped = false
    let onChange: @Sendable () -> Void
    init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func stop() { stopped = true }
    func fire() { onChange() }
}

/// A synthetic app in a fake watched folder.
struct FakeApp: Sendable {
    var name: String
    var bundleID: String
    var sha = String(repeating: "b", count: 64)
    var fingerprint = "f1"
    var validity: SignatureValidity = .valid
    var background: [String] = []
}

/// Folder access that never touches the file system. Scans run AutoRecorder.step over FakeApps.
final class FakeFolderAccess: FolderAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var _apps: [String: [FakeApp]] = [:]
    private var _unavailable = false
    private var _scans = 0
    private(set) var watches: [FakeWatch] = []
    let gate: DispatchSemaphore?
    var progressSteps: [(Int, Int)] = []
    var appResult: InspectionResult = .failed(.accessUnavailable)
    /// Extra ledgers a scan returns, to check that the model ignores ledgers of other folders.
    var smuggled: [AppLedger] = []

    init(gated: Bool = false) { gate = gated ? DispatchSemaphore(value: 0) : nil }

    func setApps(_ apps: [FakeApp], for folder: URL) { lock.lock(); _apps[folder.standardizedFileURL.path] = apps; lock.unlock() }
    var unavailable: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _unavailable }
        set { lock.lock(); _unavailable = newValue; lock.unlock() }
    }
    var scans: Int { lock.lock(); defer { lock.unlock() }; return _scans }

    func bookmark(for folder: URL) throws -> Data { Data(folder.standardizedFileURL.path.utf8) }
    func resolvesToSameFolder(_ bookmark: Data, _ folder: URL) -> Bool { bookmark == Data(folder.standardizedFileURL.path.utf8) }

    func scan(_ request: ScanRequest, progress: @escaping @Sendable (Int, Int) -> Void) -> ScanOutcome {
        for (done, total) in progressSteps { progress(done, total) }
        gate?.wait()
        lock.lock()
        _scans += 1
        let apps = _apps[String(decoding: request.bookmark, as: UTF8.self)] ?? []
        let unavailable = _unavailable
        lock.unlock()
        if unavailable { return .unavailable }
        let discovered = apps.map { app in
            DiscoveredApp(key: AutoRecorder.appKey(folderID: request.folderID, relativePath: app.name + ".app", bundleID: app.bundleID),
                          url: URL(fileURLWithPath: "/nonexistent/\(app.name).app"), displayName: app.name,
                          fingerprint: Fingerprint(app.fingerprint))
        }.filter { !request.excluded.contains($0.key) }
        let byName = Dictionary(uniqueKeysWithValues: apps.map { ($0.name + ".app", $0) })
        var result = AutoRecorder(folderID: request.folderID).step(previous: request.previous, discovered: discovered, inspector: { url in
            guard let app = byName[url.lastPathComponent] else { return .failed(.bundleUnreadable) }
            var o = observation(app.bundleID, sha: app.sha, at: request.now)
            o.signatureValidity = app.validity
            o.backgroundItems = app.background
            return .complete(o)
        }, now: request.now)
        result.ledgers += smuggled
        return .recorded(result, refreshedBookmark: nil)
    }
    func inspectApp(folderID: UUID, folderBookmark: Data, appKey: String?, ledgerID: UUID) -> InspectionResult { appResult }
    @MainActor func watch(_ bookmark: Data, onChange: @escaping @Sendable () -> Void) -> FolderWatching? {
        let watch = FakeWatch(onChange: onChange)
        watches.append(watch)
        return watch
    }
}

final class FakeNotifier: NotificationPosting, @unchecked Sendable {
    private let lock = NSLock()
    let answer: AlertAuthorization
    private var _posted: [AlertNote] = []
    private var _requests = 0
    init(answer: AlertAuthorization = .granted) { self.answer = answer }
    var posted: [AlertNote] { lock.lock(); defer { lock.unlock() }; return _posted }
    var requests: Int { lock.lock(); defer { lock.unlock() }; return _requests }
    private func countRequest() { lock.lock(); _requests += 1; lock.unlock() }
    func requestAuthorization() async -> AlertAuthorization {
        countRequest()
        return answer
    }
    func post(identifier: String, title: String, body: String) {
        lock.lock(); _posted.append(AlertNote(identifier: identifier, title: title, body: body)); lock.unlock()
    }
}

func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "NativeLedgerAppTests-\(UUID().uuidString)")! }

/// Waits up to two seconds for a main-actor condition.
@MainActor func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
}

let alphaApp = FakeApp(name: "Alpha", bundleID: "com.example.alpha")
let betaApp = FakeApp(name: "Beta", bundleID: "com.example.beta")

// MARK: watched folders

@MainActor @Suite struct WatchedFolderTests {
    @Test func watchingAFolderSavesItStartsAWatcherAndRecordsItsApps() async throws {
        let dir = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: dir) }
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp, betaApp], for: apps)
        let model = LedgerModel(store: LedgerStore(directory: dir), folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        await model.currentScan(id)?.value
        #expect(access.scans == 1)
        #expect(model.folders.map(\.id) == [id])
        #expect(model.watcherCount == 1 && access.watches.count == 1)
        #expect(model.folderLedgers(id).count == 2 && model.appCount(id) == 2)
        #expect(model.ledgers.allSatisfy { $0.source == .folder(id) && $0.entries.count == 1 })
        #expect(model.folderStatus[id] == .idle)
        #expect(model.showingRecent)
        // Both files are written next to each other and reload.
        guard case .loaded(let saved) = FolderStore(directory: dir).load() else { Issue.record("folders.json unreadable"); return }
        #expect(saved.map(\.id) == [id] && saved[0].name == FileManager.default.displayName(atPath: apps.path))
        guard case .loaded(let ledgers) = LedgerStore(directory: dir).load() else { Issue.record("ledgers.json unreadable"); return }
        #expect(ledgers.count == 2)
    }

    @Test func choosingTheSameFolderAgainRenewsAccessWithoutADuplicate() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        await model.currentScan(id)?.value
        #expect(model.watch(urls: [apps]) == [id])
        await model.currentScan(id)?.value
        #expect(model.folders.count == 1 && model.ledgers.count == 1)
        #expect(access.watches.first?.stopped == true && model.watcherCount == 1)
        #expect(model.watch(urls: [apps.appendingPathComponent("Alpha.app")]).isEmpty)
        #expect(model.notice.contains("Add App"))
    }

    @Test func removingAFolderStopsItsWatcherAndDeletesOnlyItsLedgers() async throws {
        let dir = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = try temporaryFolder(), b = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp, betaApp], for: a)
        access.setApps([FakeApp(name: "Gamma", bundleID: "com.example.gamma")], for: b)
        let picked = AppLedger(displayName: "Picked")
        let store = LedgerStore(directory: dir); _ = store.load(); try store.save([picked])
        let model = LedgerModel(store: LedgerStore(directory: dir), folderAccess: access)
        let ids = model.watch(urls: [a, b])
        for id in ids { await model.currentScan(id)?.value }
        #expect(model.ledgers.count == 4)
        model.removeFolder(ids[0])
        #expect(model.folders.map(\.id) == [ids[1]])
        #expect(access.watches[0].stopped && !access.watches[1].stopped)
        #expect(Set(model.ledgers.map(\.displayName)) == ["Picked", "Gamma"])
        #expect(model.folderStatus[ids[0]] == nil)
        guard case .loaded(let saved) = LedgerStore(directory: dir).load(),
              case .loaded(let folders) = FolderStore(directory: dir).load() else { Issue.record("unreadable"); return }
        #expect(Set(saved.map(\.displayName)) == ["Picked", "Gamma"] && folders.map(\.id) == [ids[1]])
    }

    @Test func anUnreadableFolderMarksNoAppRemoved() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp, betaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        await model.currentScan(id)?.value
        let before = model.ledgers
        access.unavailable = true
        await model.scanFolder(id)?.value
        #expect(model.ledgers == before)
        #expect(model.ledgers.allSatisfy { !$0.isRemoved && $0.entries.count == 1 })
        #expect(model.folderStatus[id] == .unavailable)
        #expect(model.ledgers.allSatisfy { model.badge($0) == .unavailable })
        // Choosing the folder again clears the state and the next scan reads it.
        access.unavailable = false
        _ = model.watch(urls: [apps])
        await model.currentScan(id)?.value
        #expect(model.folderStatus[id] == .idle && model.ledgers.allSatisfy { model.badge($0) == .intact })
    }

    @Test func folderScanStepsOnlyWhenDiscoveryReturnedAList() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let alpha = try fakeApp(in: root, named: "Alpha")
        _ = try fakeApp(in: root, named: "Beta")
        let folderID = UUID()
        let read: (URL) -> InspectionResult = { url in
            .complete(observation("com.example.\(url.deletingPathExtension().lastPathComponent.lowercased())"))
        }
        var seen: [(Int, Int)] = []
        let first = try #require(FolderScan.run(root: root, folderID: folderID, previous: [], now: appT0, inspector: read,
                                                progress: { seen.append(($0, $1)) }))
        #expect(first.ledgers.count == 2 && first.newEntries.count == 2)
        #expect(seen.map(\.0) == [0, 1, 2] && seen.allSatisfy { $0.1 == 2 })
        try FileManager.default.removeItem(at: alpha)
        let second = try #require(FolderScan.run(root: root, folderID: folderID, previous: first.ledgers, now: appT0, inspector: read))
        #expect(second.ledgers.filter(\.isRemoved).count == 1)
        try FileManager.default.removeItem(at: root)
        #expect(FolderScan.run(root: root, folderID: folderID, previous: second.ledgers, now: appT0, inspector: read) == nil)
    }

    @Test func systemAccessReportsADeletedFolderAsUnavailable() throws {
        let root = try temporaryFolder()
        _ = try fakeApp(in: root, named: "Alpha")
        let access = SystemFolderAccess()
        let bookmark = try access.bookmark(for: root)
        #expect(access.resolvesToSameFolder(bookmark, root))
        try FileManager.default.removeItem(at: root)
        let outcome = access.scan(ScanRequest(folderID: UUID(), bookmark: bookmark, previous: [], now: appT0)) { _, _ in }
        #expect(outcome == .unavailable)
        #expect(access.inspectApp(folderID: UUID(), folderBookmark: bookmark, appKey: "k1-x", ledgerID: UUID()).failure == .accessUnavailable)
    }

    @Test func changesWithinTheDebounceIntervalGiveOneScan() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        model.debounceInterval = 0.2
        let id = try #require(model.watch(urls: [apps]).first)
        await model.currentScan(id)?.value
        #expect(access.scans == 1)
        var updated = alphaApp; updated.sha = String(repeating: "c", count: 64); updated.fingerprint = "f2"
        access.setApps([updated], for: apps)
        let watch = try #require(access.watches.last)
        watch.fire(); watch.fire()
        try? await Task.sleep(nanoseconds: 30_000_000)   // the watcher hops to the main actor
        let last = model.folderDidChange(id)
        #expect(access.scans == 1)
        await last?.value
        #expect(access.scans == 2)
        let ledger = try #require(model.ledgers.first)
        #expect(ledger.entries.count == 2 && ledger.latest?.anomalies == [.silentRebuild])
    }

    @Test func aScanResultChangesOnlyItsOwnFolder() async throws {
        let a = try temporaryFolder(), b = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp], for: a)
        access.setApps([betaApp], for: b)
        let picked = AppLedger(displayName: "Picked")
        let model = LedgerModel(store: nil, seed: [picked], folderAccess: access)
        let ids = model.watch(urls: [a, b])
        for id in ids { await model.currentScan(id)?.value }
        let other = try #require(model.folderLedgers(ids[1]).first)
        // A result for folder A that also carries changed copies of folder B's ledger and the picked ledger.
        var tamperedOther = other; tamperedOther.displayName = "Changed"
        var tamperedPicked = picked; tamperedPicked.displayName = "Changed"
        access.smuggled = [tamperedOther, tamperedPicked, AppLedger(displayName: "Stray", source: .folder(ids[1]), appKey: "k1-stray")]
        var updated = alphaApp; updated.fingerprint = "f2"; updated.sha = String(repeating: "d", count: 64)
        access.setApps([updated], for: a)
        await model.folderDidChange(ids[0])?.value
        #expect(model.ledger(other.id) == other)
        #expect(model.ledger(picked.id) == picked)
        #expect(!model.ledgers.contains { $0.displayName == "Stray" || $0.displayName == "Changed" })
        #expect(model.folderLedgers(ids[0]).first?.entries.count == 2)
    }

    @Test func aLateScanResultAfterTheFolderIsRemovedIsDropped() async throws {
        let dir = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: dir) }
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess(gated: true)
        access.setApps([alphaApp, betaApp], for: apps)
        let model = LedgerModel(store: LedgerStore(directory: dir), folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        let task = try #require(model.currentScan(id))
        model.removeFolder(id)
        access.gate?.signal()
        await task.value
        #expect(model.ledgers.isEmpty && model.folders.isEmpty)
        #expect(model.folderStatus.isEmpty && !model.isScanning(id))
        guard case .loaded(let saved) = LedgerStore(directory: dir).load() else { Issue.record("unreadable"); return }
        #expect(saved.isEmpty)
    }

    @Test func aLateScanResultAfterTheFolderIsWatchedAgainIsDropped() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess(gated: true)
        access.setApps([alphaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let old = try #require(model.watch(urls: [apps]).first)
        let oldTask = try #require(model.currentScan(old))
        model.removeFolder(old)
        let new = try #require(model.watch(urls: [apps]).first)
        #expect(new != old)
        let newTask = try #require(model.currentScan(new))
        access.gate?.signal(); access.gate?.signal()
        await oldTask.value; await newTask.value
        #expect(model.ledgers.count == 1)
        #expect(model.ledgers.allSatisfy { $0.source == .folder(new) })
    }

    @Test func aLedgerChangedDuringAScanKeepsItsNewEntry() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess(gated: true)
        access.setApps([alphaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        access.gate?.signal()
        await model.currentScan(id)?.value
        let ledger = try #require(model.ledgers.first)
        var changed = alphaApp; changed.fingerprint = "f2"; changed.sha = String(repeating: "e", count: 64)
        access.setApps([changed], for: apps)
        let scan = try #require(model.scanFolder(id))
        await waitUntil { model.folderStatus[id] == .checking }
        // While the scan is blocked, Inspect now records a different rebuild.
        let manualSHA = String(repeating: "9", count: 64)
        access.appResult = .complete(observation("com.example.alpha", sha: manualSHA, at: appT0.addingTimeInterval(30)))
        await model.inspect(ledger.id)?.value
        #expect(model.ledger(ledger.id)?.entries.count == 2)
        access.gate?.signal()
        await scan.value
        let kept = try #require(model.ledger(ledger.id))
        #expect(kept.entries.count == 2 && kept.latest?.observation.binary.executableSHA256 == manualSHA)
        #expect(kept.lastFingerprint == Fingerprint("f1"))
        // The next scan reads the app again because its fingerprint was not updated.
        access.gate?.signal()
        await model.scanFolder(id)?.value
        let after = try #require(model.ledger(ledger.id))
        #expect(after.entries.count == 3 && after.lastFingerprint == Fingerprint("f2"))
        #expect(LedgerChain.verify(after).isIntact)
    }

    @Test func progressShowsRecordingCountWhileTheScanRuns() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess(gated: true)
        access.progressSteps = [(0, 120), (37, 120)]
        access.setApps([alphaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        let task = try #require(model.currentScan(id))
        await waitUntil { model.folderStatus[id] == .recording(done: 37, total: 120) }
        #expect(model.folderStatus[id]?.progressText == "Recording 37 of 120")
        #expect(model.scanProgress?.text.hasPrefix("Recording 37 of 120 in ") == true)
        #expect(model.isScanning(id))
        access.gate?.signal()
        await task.value
        #expect(model.folderStatus[id] == .idle && model.scanProgress == nil)
    }

    @Test func launchScansSavedFoldersAndManualInspectReadsThroughTheFolder() async throws {
        let dir = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: dir) }
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp], for: apps)
        let first = LedgerModel(store: LedgerStore(directory: dir), folderAccess: access)
        let id = try #require(first.watch(urls: [apps]).first)
        await first.currentScan(id)?.value
        // Relaunch: the saved folder is watched and scanned again.
        access.setApps([alphaApp, betaApp], for: apps)
        let relaunched = LedgerModel(store: LedgerStore(directory: dir), folderAccess: access)
        #expect(relaunched.folders.map(\.id) == [id] && relaunched.watcherCount == 0)
        relaunched.startWatching()
        #expect(relaunched.watcherCount == 1)
        await relaunched.currentScan(id)?.value
        #expect(relaunched.ledgers.count == 2)
        let alpha = try #require(relaunched.ledgers.first { $0.displayName == "Alpha" })
        access.appResult = .failed(.accessUnavailable)
        await relaunched.inspect(alpha.id)?.value
        #expect(relaunched.notices[alpha.id] == LedgerModel.folderAccessMessage)
        #expect(relaunched.badge(try #require(relaunched.ledger(alpha.id))) == .unavailable)
    }
}

// MARK: removed

@MainActor @Suite struct RemovedLedgerTests {
    @Test func aRemovedAppShowsRemovedAndCannotBeInspectedOrAcknowledged() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp, betaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        await model.currentScan(id)?.value
        access.setApps([betaApp], for: apps)
        await model.scanFolder(id)?.value
        let alpha = try #require(model.ledgers.first { $0.displayName == "Alpha" })
        #expect(alpha.isRemoved && alpha.latest?.kind == .removed && alpha.entries.count == 2)
        #expect(model.badge(alpha) == .removed && model.badge(alpha).label == "Removed")
        #expect(!model.canInspect(alpha) && !model.canAcknowledge(alpha))
        #expect(model.inspect(alpha.id) == nil && model.acknowledge(alpha.id) == nil)
        #expect(model.appCount(id) == 1 && model.removedCount(id) == 1)
        #expect(model.recentChanges().first?.entry.kind == .removed)
        #expect(LedgerChain.verify(alpha).isIntact)
    }
}

// MARK: alerts

@MainActor @Suite struct AlertTests {
    private func entry(_ anomalies: [Anomaly], name: String = "Alpha", seq: Int = 2) -> RecordedEntry {
        var e = LedgerEntry(seq: seq, kind: .observed, observation: observation(), changes: [], anomalies: anomalies,
                            previousHash: LedgerChain.genesisHash, entryHash: "x")
        e.entryHash = String(repeating: "a", count: 64)
        return RecordedEntry(ledgerID: UUID(), displayName: name, entry: e)
    }

    @Test func alertsAreOffByDefaultAndPostNothing() {
        let notifier = FakeNotifier()
        let alerts = AlertController(poster: notifier, defaults: freshDefaults())
        #expect(!alerts.enabled)
        #expect(alerts.handle([entry([.signatureInvalid])]).isEmpty)
        #expect(notifier.posted.isEmpty && notifier.requests == 0)
        #expect(SettingsForm.alertToggleLabel == "Alert me about high-severity changes")
    }

    @Test func onePostPerEntryWithAHighSeverityAnomaly() async {
        let notifier = FakeNotifier()
        let defaults = freshDefaults()
        let alerts = AlertController(poster: notifier, defaults: defaults)
        await alerts.setEnabled(true)
        #expect(alerts.enabled && notifier.requests == 1 && defaults.bool(forKey: AlertController.enabledKey))
        let notes = alerts.handle([
            entry([.signatureInvalid, .newBackgroundItem], name: "Alpha"),
            entry([.teamChange], name: "Beta"),
            entry([.silentRebuild, .versionRegression, .newEntitlement, .newPrivacyUsage, .updateFeedChanged, .architectureChange], name: "Gamma"),
            entry([], name: "Delta"),
        ])
        #expect(notifier.posted.count == 2 && notes == notifier.posted)
        #expect(notifier.posted[0].title == "Alpha" && notifier.posted[0].body.contains("Signature invalid")
                && notifier.posted[0].body.contains("New background item"))
        #expect(notifier.posted[1].title == "Beta" && notifier.posted[1].body.contains("Team change"))
        #expect(notifier.posted.allSatisfy { !$0.title.contains("/") && !$0.body.contains("/") })
        #expect(AlertController.note(for: entry([.signatureInvalid], name: "/Applications/Thing.app"))?.title == "An app")
        // Turning it off stops the posts.
        await alerts.setEnabled(false)
        alerts.handle([entry([.teamChange])])
        #expect(notifier.posted.count == 2 && !defaults.bool(forKey: AlertController.enabledKey))
    }

    @Test func deniedOrUnavailableAuthorizationTurnsTheToggleOffWithTheReason() async {
        let defaults = freshDefaults()
        let denied = AlertController(poster: FakeNotifier(answer: .denied), defaults: defaults)
        await denied.setEnabled(true)
        #expect(!denied.enabled && denied.message == AlertController.deniedMessage)
        #expect(denied.message.contains("System Settings") && denied.message.contains("Allow notifications"))
        #expect(!defaults.bool(forKey: AlertController.enabledKey))
        let unavailable = AlertController(poster: FakeNotifier(answer: .unavailable), defaults: freshDefaults())
        await unavailable.setEnabled(true)
        #expect(!unavailable.enabled && unavailable.message == AlertController.unavailableMessage)
    }

    @Test func automaticEntriesFromAScanReachTheAlerts() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp, betaApp], for: apps)
        let notifier = FakeNotifier()
        let alerts = AlertController(poster: notifier, defaults: freshDefaults())
        await alerts.setEnabled(true)
        let state = AppState(live: LedgerModel(store: nil, folderAccess: access), alerts: alerts)
        let id = try #require(state.live.watch(urls: [apps]).first)
        await state.live.currentScan(id)?.value
        #expect(notifier.posted.isEmpty)
        var bad = alphaApp; bad.fingerprint = "f2"; bad.validity = .invalid(code: -67061); bad.background = ["com.example.alpha.helper"]
        bad.sha = String(repeating: "7", count: 64)
        var quiet = betaApp; quiet.fingerprint = "f2"; quiet.sha = String(repeating: "8", count: 64)
        access.setApps([bad, quiet], for: apps)
        await state.live.scanFolder(id)?.value
        #expect(notifier.posted.count == 1)
        #expect(notifier.posted.first?.title == "Alpha")
        #expect(notifier.posted.first?.body.contains("Signature invalid") == true)
        // Manual inspections are not automatic entries.
        let beta = try #require(state.live.ledgers.first { $0.displayName == "Beta" })
        access.appResult = .complete(observation("com.example.beta", team: "TEAMZZZZZZ", at: appT0.addingTimeInterval(99)))
        await state.live.inspect(beta.id)?.value
        #expect(state.live.ledger(beta.id)?.latest?.anomalies.contains(.teamChange) == true)
        #expect(notifier.posted.count == 1)
    }
}

// MARK: recent changes

@MainActor @Suite struct RecentChangesTests {
    @Test func feedIsNewestFirstAndLimitedToSevenDays() {
        let now = appT0
        var a = AppLedger(displayName: "Alpha")
        LedgerChain.append(observation("com.example.alpha", at: now.addingTimeInterval(-10 * 86400)), kind: .observed, to: &a)
        LedgerChain.append(observation("com.example.alpha", version: "1.1", at: now.addingTimeInterval(-6 * 86400)), kind: .observed, to: &a)
        LedgerChain.append(observation("com.example.alpha", version: "1.2", at: now.addingTimeInterval(-3600)), kind: .observed, to: &a)
        var b = AppLedger(displayName: "Beta")
        LedgerChain.append(observation("com.example.beta", at: now.addingTimeInterval(-7 * 86400 - 60)), kind: .observed, to: &b)
        LedgerChain.append(observation("com.example.beta", version: "2.0", at: now.addingTimeInterval(-2 * 86400)), kind: .observed, to: &b)
        let model = LedgerModel(store: nil, seed: [a, b], now: { now })
        let feed = model.recentChanges()
        #expect(feed.map(\.displayName) == ["Alpha", "Beta", "Alpha"])
        #expect(feed.map(\.entry.seq) == [3, 2, 2])
        #expect(zip(feed, feed.dropFirst()).allSatisfy { $0.date >= $1.date })
        #expect(feed.allSatisfy { now.timeIntervalSince($0.date) <= LedgerModel.recentWindow })
        #expect(model.recentChanges(now: now.addingTimeInterval(30 * 86400)).isEmpty)
    }

    @Test func openingAFeedRowSelectsItsLedger() throws {
        var a = AppLedger(displayName: "Alpha"), b = AppLedger(displayName: "Beta")
        LedgerChain.append(observation("com.example.alpha", at: appT0), kind: .observed, to: &a)
        LedgerChain.append(observation("com.example.beta", at: appT0.addingTimeInterval(60)), kind: .observed, to: &b)
        let model = LedgerModel(store: nil, seed: [a, b], now: { appT0.addingTimeInterval(120) })
        model.showRecentChanges()
        #expect(model.showingRecent && model.selectedLedger == nil)
        let row = try #require(model.recentChanges().first)
        #expect(row.ledgerID == b.id)
        model.open(row)
        #expect(!model.showingRecent && model.selection == b.id && model.selectedLedger?.id == b.id)
    }
}

// MARK: sample

@MainActor @Suite struct SampleWatchTests {
    private func stamp(_ name: String) -> Date? {
        let file = LedgerModel.defaultDirectory.appendingPathComponent(name)
        return (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    @Test func sampleShowsAWatchedFolderRecentChangesAndTheNewAnomalies() throws {
        let sample = LedgerModel.sample()
        #expect(sample.ledgers.count == 4)
        #expect(sample.folders.map(\.name) == [AppSample.folderName])
        #expect(sample.appCount(AppSample.folderID) == 3)
        #expect(sample.showingRecent)
        let feed = sample.recentChanges()
        #expect(!feed.isEmpty && feed.first?.displayName == "Sample Editor")
        let viewer = try #require(sample.ledger(SampleLedger.viewerID))
        let latest = try #require(viewer.latest)
        #expect(latest.anomalies.contains(.newBackgroundItem) && latest.anomalies.contains(.signatureInvalid))
        #expect(Anomaly.bySeverity(latest.anomalies).first == .signatureInvalid)
        #expect(latest.observation.signatureValidity.label == "Invalid (code -67061)")
        #expect(sample.ledgers.allSatisfy { sample.verdicts[$0.id]?.isIntact == true })
        #expect(TimelineEntryView.opensByDefault(latest))
    }

    @Test func sampleNeverWritesTheStoreOrWatches() async throws {
        let ledgersBefore = stamp(LedgerStore.fileName), foldersBefore = stamp(FolderStore.fileName)
        let sample = LedgerModel.sample()
        #expect(!sample.hasStore && !sample.canWatchFolders)
        #expect(sample.watch(urls: [FileManager.default.temporaryDirectory]).isEmpty)
        sample.startWatching()
        #expect(sample.watcherCount == 0)
        #expect(sample.scanFolder(AppSample.folderID) == nil)
        #expect(sample.folderDidChange(AppSample.folderID) == nil)
        await sample.inspect(SampleLedger.viewerID)?.value
        #expect(sample.ledger(SampleLedger.viewerID)?.entries.count == 3)
        sample.removeFolder(AppSample.folderID)
        #expect(sample.folders.isEmpty && sample.ledgers.count == 1)
        #expect(stamp(LedgerStore.fileName) == ledgersBefore && stamp(FolderStore.fileName) == foldersBefore)
    }
}

// MARK: removing one watched-folder app

@MainActor @Suite struct FolderExclusionTests {
    @Test func removingAFolderAppKeepsItRemovedAcrossRescansAndRelaunch() async throws {
        let dir = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: dir) }
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp, betaApp], for: apps)
        let model = LedgerModel(store: LedgerStore(directory: dir), folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        await model.currentScan(id)?.value
        let alpha = try #require(model.ledgers.first { $0.displayName == "Alpha" })
        model.remove(alpha.id)
        #expect(model.folder(id)?.excludedAppKeys == [alpha.appKey!])
        await model.scanFolder(id)?.value
        #expect(model.ledgers.map(\.displayName) == ["Beta"])
        #expect(!model.ledgers.contains { $0.isRemoved })
        // The exclusion is saved in folders.json and survives a relaunch scan.
        guard case .loaded(let saved) = FolderStore(directory: dir).load() else { Issue.record("folders.json unreadable"); return }
        #expect(saved.first?.excludedAppKeys == [alpha.appKey!])
        let relaunched = LedgerModel(store: LedgerStore(directory: dir), folderAccess: access)
        relaunched.startWatching()
        await relaunched.currentScan(id)?.value
        #expect(relaunched.ledgers.map(\.displayName) == ["Beta"])
    }

    @Test func watchingTheFolderAgainClearsItsExclusions() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp, betaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        await model.currentScan(id)?.value
        let alpha = try #require(model.ledgers.first { $0.displayName == "Alpha" })
        model.remove(alpha.id)
        #expect(model.watch(urls: [apps]) == [id])
        #expect(model.folder(id)?.excludedAppKeys.isEmpty == true)
        await model.currentScan(id)?.value
        let back = try #require(model.ledgers.first { $0.displayName == "Alpha" })
        #expect(back.id != alpha.id && back.entries.count == 1)
    }

    @Test func aScanThatStartedBeforeRemoveDoesNotRecreateTheApp() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess(gated: true)
        access.setApps([alphaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        access.gate?.signal()
        await model.currentScan(id)?.value
        let alpha = try #require(model.ledgers.first)
        var changed = alphaApp; changed.fingerprint = "f2"; changed.sha = String(repeating: "c", count: 64)
        access.setApps([changed], for: apps)
        let task = try #require(model.scanFolder(id))
        model.remove(alpha.id)
        access.gate?.signal()
        await task.value
        #expect(model.ledgers.isEmpty)
    }

    @Test func removingAPickedAppAddsNoExclusion() async throws {
        let apps = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: apps) }
        let access = FakeFolderAccess()
        access.setApps([alphaApp], for: apps)
        let model = LedgerModel(store: nil, folderAccess: access)
        let id = try #require(model.watch(urls: [apps]).first)
        await model.currentScan(id)?.value
        let picked = try #require(model.add(urls: [try fakeApp(in: apps, named: "Picked")], bookmark: { _ in Data([1]) }).first)
        model.remove(picked)
        #expect(model.folder(id)?.excludedAppKeys.isEmpty == true)
        #expect(model.ledgers.count == 1)
    }

    @Test func folderScanSkipsExcludedKeysOnARealFolder() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try fakeApp(in: root, named: "Keep")
        _ = try fakeApp(in: root, named: "Drop")
        let folderID = UUID()
        let dropKey = AutoRecorder.appKey(folderID: folderID, relativePath: "Drop.app", bundleID: "com.example.drop")
        var read: [String] = []
        let result = try #require(FolderScan.run(root: root, folderID: folderID, previous: [], now: appT0, excluded: [dropKey],
                                                 inspector: { url in read.append(url.lastPathComponent)
                                                     return .complete(observation("com.example.keep", at: appT0)) }))
        #expect(read == ["Keep.app"])
        #expect(result.ledgers.count == 1 && result.ledgers[0].appKey != dropKey)
    }

    @Test func oldFoldersJSONWithoutExclusionsDecodes() throws {
        let dir = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        // Write a build 4 file, then drop the new key to get the shape of a file written before exclusions.
        let store = FolderStore(directory: dir)
        try store.save([WatchedFolder(id: id, name: "Applications", bookmark: Data([1, 2]), addedAt: appT0, excludedAppKeys: ["k1-x"])])
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        var list = try #require(object["folders"] as? [[String: Any]])
        list[0].removeValue(forKey: "excludedAppKeys")
        object["folders"] = list
        try JSONSerialization.data(withJSONObject: object).write(to: store.fileURL)
        guard case .loaded(let folders) = FolderStore(directory: dir).load() else { Issue.record("old file did not decode"); return }
        #expect(folders.map(\.id) == [id] && folders[0].excludedAppKeys.isEmpty)
    }
}

@Suite struct FolderStoreReviewTwoTests {
    @Test func anUnreadableFoldersFileThatCannotBeCopiedIsNeverOverwritten() throws {
        let dir = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FolderStore(directory: dir)
        let original = Data("not json".utf8)
        try original.write(to: store.fileURL)
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: store.fileURL.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.fileURL.path) }
        #expect(store.load() == .corrupt(keptCopy: false))
        #expect(store.writesPaused)
        #expect(throws: FolderStore.WritesPaused.self) { try store.save([]) }
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.fileURL.path)
        #expect(try Data(contentsOf: store.fileURL) == original)
    }
}
