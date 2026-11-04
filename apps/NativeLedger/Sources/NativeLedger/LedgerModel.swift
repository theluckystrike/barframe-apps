import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LedgerCore

/// Main-actor state for the ledger window. Inspections run on a detached task. Each one holds a ticket with a
/// serial number that never repeats, so a late result never lands on a removed, re-added or reloaded ledger.
@MainActor
final class LedgerModel: ObservableObject {
    struct Ticket: Equatable, Sendable {
        let id: UUID
        let serial: Int
    }
    enum Badge: Equatable, CaseIterable {
        case intact, anomaly, broken, notInspected, unavailable, removed
        var label: String {
            switch self {
            case .intact: return "Intact"
            case .anomaly: return "Anomaly"
            case .broken: return "Chain broken"
            case .notInspected: return "Not inspected"
            case .unavailable: return "Unavailable"
            case .removed: return "Removed"
            }
        }
    }
    enum FolderStatus: Equatable {
        case idle
        /// Discovery is running and no full inspection has been counted yet.
        case checking
        case recording(done: Int, total: Int)
        /// The bookmark did not resolve or the folder could not be listed.
        case unavailable
        var progressText: String? {
            switch self {
            case .checking: return "Checking for changes"
            case .recording(let done, let total): return "Recording \(done) of \(total)"
            case .idle, .unavailable: return nil
            }
        }
    }
    /// One row of Recent changes.
    struct FeedItem: Identifiable, Equatable {
        let ledgerID: UUID
        let displayName: String
        let entry: LedgerEntry
        var id: String { "\(ledgerID.uuidString)-\(entry.seq)-\(entry.entryHash)" }
        var date: Date { entry.observation.observedAt }
    }
    struct Comparison: Identifiable {
        let id = UUID()
        let source: String
        let exportedAt: Date
        let rows: [CrossMacRow]
        /// Ledgers in the opened file whose own chain does not verify.
        let brokenInFile: Int
        /// Ledgers on this Mac whose own chain does not verify.
        var brokenHere = 0
        /// Bundle identifiers whose newest entry on either side comes from a chain that does not verify.
        var unverified: Set<String> = []
        let sample: Bool
    }

    static let staleKey = "NativeLedger.staleAfterDays"
    static let defaultStaleDays = 14
    static let maximumFileBytes = 64 << 20
    static var ledgerType: UTType { UTType(filenameExtension: LedgerFile.fileExtension, conformingTo: .json) ?? .json }
    static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/NativeLedger", isDirectory: true)
    }

    static let recentWindow: TimeInterval = 7 * 86400

    @Published private(set) var ledgers: [AppLedger] = []
    /// The selected ledger. Choosing one leaves Recent changes.
    @Published var selection: UUID? { didSet { if selection != nil && showingRecent { showingRecent = false } } }
    /// True while the sidebar's Recent changes item is selected.
    @Published var showingRecent = false
    @Published private(set) var folders: [WatchedFolder] = []
    @Published private(set) var folderStatus: [UUID: FolderStatus] = [:]
    /// Window-level message for storage, export and compare.
    @Published private(set) var notice = ""
    /// Per-ledger messages, so a result for one app never shows on another.
    @Published private(set) var notices: [UUID: String] = [:]
    @Published private(set) var storageCorrupt = false
    @Published private(set) var verdicts: [UUID: ChainVerdict] = [:]
    @Published private(set) var verifiedAt: [UUID: Date] = [:]
    @Published private(set) var failures: [UUID: InspectionFailure] = [:]
    @Published private(set) var checkedAt: [UUID: Date] = [:]
    @Published private var active: [UUID: Ticket] = [:]
    @Published var comparison: Comparison?

    let isSample: Bool
    private let store: LedgerStore?
    private let folderStore: FolderStore?
    private let inspector: AppInspecting
    private let folderAccess: FolderAccessing
    private let now: @Sendable () -> Date
    private var serial = 0

    // Watched folders. Every scan holds a token from the same serial; a result applies only while its token is the
    // folder's current one, so a late result never lands on a removed or re-added folder.
    private var watchers: [UUID: FolderWatching] = [:]
    private var scanTokens: [UUID: Int] = [:]
    private var scanTasks: [UUID: (token: Int, task: Task<Void, Never>)] = [:]
    private var rescanPending: Set<UUID> = []
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    private var watching = false
    /// Seconds between the last FSEvents change and the scan it triggers.
    var debounceInterval: TimeInterval = 5
    /// Receives the entries an automatic scan appended. AppState passes them to the alerts.
    var onAutomaticEntries: (([RecordedEntry]) -> Void)?

    /// `store == nil` keeps everything in memory. A stored model loads at creation and pauses writes on corrupt data.
    /// Watched folders are kept in folders.json next to ledgers.json.
    init(store: LedgerStore?, inspector: AppInspecting = BookmarkInspector(), isSample: Bool = false,
         seed: [AppLedger] = [], folderSeed: [WatchedFolder] = [], folderAccess: FolderAccessing = SystemFolderAccess(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store; self.inspector = inspector; self.isSample = isSample; self.now = now
        self.folderAccess = folderAccess
        folderStore = store.map { FolderStore(directory: $0.fileURL.deletingLastPathComponent()) }
        ledgers = seed
        folders = folderSeed
        if let store { applyLoad(store.load()) } else { verifyAll() }
        if let folderStore { loadFolders(folderStore) }
        for folder in folders { folderStatus[folder.id] = .idle }
        selection = ledgers.first?.id
    }

    /// The memory-only Sample with a watched folder. It never has a store, a watcher or a scan.
    static func sample(now: Date = Date()) -> LedgerModel {
        let ledgers = AppSample.ledgers(now: now)
        let inspector = AppSample.Inspector(ledgers: ledgers)
        let model = LedgerModel(store: nil, inspector: inspector, isSample: true, seed: ledgers,
                                folderSeed: [AppSample.folder(now: now)], folderAccess: AppSample.FolderAccess(inspector: inspector),
                                now: { Date() })
        model.showingRecent = true
        return model
    }

    // MARK: state

    var canWrite: Bool { !(store?.writesPaused ?? false) && !storageCorrupt }
    var canAddApps: Bool { !isSample && canWrite }
    var canWatchFolders: Bool { !isSample && canWrite }
    var canExport: Bool { !isSample && !ledgers.isEmpty }
    var hasStore: Bool { store != nil }
    func ledger(_ id: UUID) -> AppLedger? { ledgers.first { $0.id == id } }
    var selectedLedger: AppLedger? { showingRecent ? nil : selection.flatMap(ledger) }
    func isBusy(_ id: UUID) -> Bool { active[id] != nil }
    func canInspect(_ ledger: AppLedger) -> Bool { canWrite && !isBusy(ledger.id) && !ledger.isRemoved }
    func folder(_ id: UUID) -> WatchedFolder? { folders.first { $0.id == id } }
    /// The watched folder a ledger belongs to, if any.
    func folder(of ledger: AppLedger) -> WatchedFolder? { ledger.source.folderID.flatMap(folder) }
    func folderLedgers(_ id: UUID) -> [AppLedger] { ledgers.filter { $0.source == .folder(id) } }
    /// Apps of the folder that are still in it.
    func appCount(_ id: UUID) -> Int { folderLedgers(id).filter { !$0.isRemoved }.count }
    func removedCount(_ id: UUID) -> Int { folderLedgers(id).filter(\.isRemoved).count }
    func isScanning(_ id: UUID) -> Bool { scanTasks[id] != nil }
    /// The scan that is running for the folder, if any.
    func currentScan(_ id: UUID) -> Task<Void, Never>? { scanTasks[id]?.task }
    /// The first folder progress line, for the bar above the detail view.
    var scanProgress: (folder: WatchedFolder, text: String, fraction: Double?)? {
        for folder in folders {
            switch folderStatus[folder.id] {
            case .checking?: return (folder, "Checking for changes in \(folder.name)", nil)
            case .recording(let done, let total)?:
                return (folder, "Recording \(done) of \(total) in \(folder.name)", total > 0 ? Double(done) / Double(total) : nil)
            default: continue
            }
        }
        return nil
    }

    func badge(_ ledger: AppLedger) -> Badge {
        if case .broken = verdicts[ledger.id] { return .broken }
        if ledger.isRemoved { return .removed }
        if !ledger.openAnomalies.isEmpty { return .anomaly }
        if failures[ledger.id] != nil { return .unavailable }
        if ledger.entries.isEmpty { return .notInspected }
        return .intact
    }
    /// The newest moment the copy was read completely, including readings that matched the latest entry.
    func lastRead(_ ledger: AppLedger) -> Date? {
        [ledger.latest?.observation.observedAt, ledger.lastCheckedAt, checkedAt[ledger.id]].compactMap { $0 }.max()
    }
    func isStale(_ ledger: AppLedger, days: Int) -> Bool {
        guard let last = lastRead(ledger), days > 0 else { return false }
        return now().timeIntervalSince(last) > Double(days) * 86400
    }
    func canAcknowledge(_ ledger: AppLedger) -> Bool {
        guard let latest = ledger.latest else { return false }
        let intact = (verdicts[ledger.id] ?? LedgerChain.verify(ledger)).isIntact
        return latest.kind == .observed && intact && canWrite && !isBusy(ledger.id)
    }

    // MARK: recent changes

    /// Entries of every ledger from the last 7 days, newest first.
    func recentChanges(now date: Date? = nil) -> [FeedItem] {
        let start = (date ?? now()).addingTimeInterval(-Self.recentWindow)
        let items = ledgers.flatMap { ledger in
            ledger.entries.filter { $0.observation.observedAt >= start }
                .map { FeedItem(ledgerID: ledger.id, displayName: ledger.displayName, entry: $0) }
        }
        return items.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            if a.displayName != b.displayName { return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending }
            return a.entry.seq > b.entry.seq
        }
    }
    func showRecentChanges() { showingRecent = true }
    /// A click on a Recent changes row opens that ledger.
    func open(_ item: FeedItem) {
        guard ledger(item.ledgerID) != nil else { return }
        selection = item.ledgerID
        showingRecent = false
    }

    // MARK: storage

    private func applyLoad(_ load: LedgerLoad) {
        active.removeAll()
        failures.removeAll(); notices.removeAll(); checkedAt.removeAll(); verifiedAt.removeAll()
        switch load {
        case .loaded(let saved):
            ledgers = saved; storageCorrupt = false; notice = ""
        case .corrupt:
            ledgers = []
            storageCorrupt = true
            notice = "Saved ledgers could not be read. The file was left untouched and changes are paused. Retry, or start fresh. Start fresh keeps a copy of the unreadable file."
        }
        verifyAll()
    }
    private func verifyAll() {
        verdicts = Dictionary(ledgers.map { ($0.id, LedgerChain.verify($0)) }, uniquingKeysWith: { first, _ in first })
    }
    private func commit() {
        guard let store else { return }
        do { try store.save(ledgers) } catch { notice = "Ledgers could not be saved. Your last change is kept in this window only." }
    }
    func retrySavedData() {
        guard let store else { return }
        cancelScans()
        applyLoad(store.retry())
        if selection.flatMap(ledger) == nil { selection = ledgers.first?.id }
        if watching && canWrite { startWatching() }
    }
    /// Starts with no ledgers and no watched folders. The support text asks the user to watch the folders again.
    func recoverStartingFresh() {
        guard let store else { return }
        do {
            let copy = try store.recoverByStartingFresh()
            cancelScans()
            for watcher in watchers.values { watcher.stop() }
            watchers.removeAll()
            folders = []; folderStatus = [:]
            saveFolders()
            applyLoad(store.load()); selection = nil
            notice = copy == nil ? "Started fresh. Watch your folders again." : "Started fresh. The unreadable file was kept as \(copy!.lastPathComponent) in the app's storage folder. Watch your folders again."
        } catch { notice = "Recovery failed. The unreadable file was not changed." }
    }

    private func loadFolders(_ folderStore: FolderStore) {
        switch folderStore.load() {
        case .loaded(let saved):
            folders = saved
        case .corrupt(let kept):
            folders = []
            notice = kept
                ? "The list of watched folders could not be read. A copy was kept. Choose Watch a Folder to watch them again."
                : "The list of watched folders could not be read. Choose Watch a Folder to watch them again."
        }
    }
    private func saveFolders() {
        guard let folderStore else { return }
        do { try folderStore.save(folders) } catch { notice = "Watched folders could not be saved. They are kept in this window only." }
    }

    // MARK: adding and removing

    func chooseApps() {
        guard canAddApps else { return }
        let panel = NSOpenPanel()
        panel.title = "Add apps to NativeLedger"
        panel.message = "Choose one or more apps. NativeLedger keeps read-only access to each app you choose."
        panel.prompt = "Add App"
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for id in add(urls: panel.urls) { inspect(id) }
    }

    /// Adds each .app with a read-only app-scope bookmark. Choosing a copy that is already tracked renews its access.
    @discardableResult
    func add(urls: [URL], bookmark: (URL) throws -> Data = BookmarkInspector.bookmark(for:)) -> [UUID] {
        guard canAddApps else { return [] }
        var added: [UUID] = []
        var refused: [String] = []
        for url in urls {
            let name = MachOArchitecture.displayName(at: url)
            guard url.pathExtension.lowercased() == "app", let data = try? bookmark(url) else { refused.append(name); continue }
            if let index = ledgers.firstIndex(where: { Self.sameCopy($0, url) }) {
                let id = ledgers[index].id
                ledgers[index].bookmark = data
                active[id] = nil; failures[id] = nil
                notices[id] = "Access renewed."
                added.append(id)
            } else {
                let ledger = AppLedger(displayName: name, bookmark: data)
                ledgers.append(ledger)
                verdicts[ledger.id] = LedgerChain.verify(ledger)
                added.append(ledger.id)
            }
        }
        if let first = added.first { selection = first; commit() }
        if !refused.isEmpty { notice = "Could not add \(refused.joined(separator: ", ")). Choose an app bundle you can read." }
        return added
    }
    private static func sameCopy(_ ledger: AppLedger, _ url: URL) -> Bool {
        guard let data = ledger.bookmark else { return false }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                                      bookmarkDataIsStale: &stale) else { return false }
        return resolved.standardizedFileURL.path == url.standardizedFileURL.path
    }

    /// Deletes the ledger. A watched-folder app is also excluded from its folder, so the next scan does not
    /// recreate it. Choosing the folder again in Watch a Folder clears the exclusions.
    func remove(_ id: UUID) {
        guard canWrite, let removed = ledger(id) else { return }
        ledgers.removeAll { $0.id == id }
        if let folderID = removed.source.folderID, let key = removed.appKey,
           let index = folders.firstIndex(where: { $0.id == folderID }), !folders[index].excludedAppKeys.contains(key) {
            folders[index].excludedAppKeys.append(key)
            saveFolders()
        }
        active[id] = nil; failures[id] = nil; notices[id] = nil; verdicts[id] = nil; verifiedAt[id] = nil; checkedAt[id] = nil
        if selection == id { selection = ledgers.first?.id }
        commit()
    }

    // MARK: watched folders

    static let folderAccessMessage = "NativeLedger cannot read this app in its watched folder. It may have moved, or access to the folder is unavailable. Choose Watch a Folder and select the folder again."

    func chooseFolders() {
        guard canWatchFolders else { return }
        let panel = NSOpenPanel()
        panel.title = "Watch a Folder"
        panel.message = "Choose a folder that holds apps, for example Applications. Access is read only. For the apps that come with macOS, press Command Shift G and type /System/Applications."
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true; panel.treatsFilePackagesAsDirectories = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        watch(urls: panel.urls)
    }

    /// Adds each folder with a read-only bookmark, starts its watcher and scans it. Choosing a folder that is already
    /// watched renews its access and adds no duplicate.
    @discardableResult
    func watch(urls: [URL]) -> [UUID] {
        guard canWatchFolders else { return [] }
        var chosen: [UUID] = []
        var refused: [String] = []
        for url in urls {
            let name = FileManager.default.displayName(atPath: url.path)
            guard url.pathExtension.lowercased() != "app", let data = try? folderAccess.bookmark(for: url) else {
                refused.append(name); continue
            }
            if let index = folders.firstIndex(where: { folderAccess.resolvesToSameFolder($0.bookmark, url) }) {
                folders[index].bookmark = data
                folders[index].excludedAppKeys = []
                chosen.append(folders[index].id)
            } else {
                let folder = WatchedFolder(id: UUID(), name: uniqueName(for: url, base: name), bookmark: data,
                                           addedAt: LedgerCoding.normalized(now()))
                folders.append(folder)
                folderStatus[folder.id] = .idle
                chosen.append(folder.id)
            }
        }
        guard !chosen.isEmpty || !refused.isEmpty else { return [] }
        if !chosen.isEmpty { saveFolders() }
        notice = refused.isEmpty ? "" : "Could not watch \(refused.joined(separator: ", ")). Choose a folder you can read. To track one app, use Add App."
        for id in chosen {
            for ledger in folderLedgers(id) where failures[ledger.id] == .accessUnavailable { failures[ledger.id] = nil }
            startWatcher(id)
            scanFolder(id)
        }
        if !chosen.isEmpty { showingRecent = true }
        return chosen
    }
    /// Two folders with the same name, such as Applications and the system Applications folder, get the parent's name.
    private func uniqueName(for url: URL, base: String) -> String {
        guard folders.contains(where: { $0.name == base }) else { return base }
        let parent = FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
        let candidate = parent.isEmpty || parent == "/" ? base : "\(base) (\(parent))"
        return folders.contains(where: { $0.name == candidate }) ? "\(candidate) \(folders.count + 1)" : candidate
    }

    /// Starts the watchers and scans every folder once. Called at launch, so changes made while NativeLedger was
    /// closed are recorded. The Sample never watches.
    func startWatching() {
        guard !isSample else { return }
        watching = true
        guard canWrite else { return }
        for folder in folders {
            startWatcher(folder.id)
            scanFolder(folder.id)
        }
    }
    private func startWatcher(_ id: UUID) {
        guard !isSample, let folder = folder(id) else { return }
        watchers[id]?.stop()
        watchers[id] = folderAccess.watch(folder.bookmark) { [weak self] in
            Task { @MainActor in self?.folderDidChange(id) }
        }
    }
    var watcherCount: Int { watchers.count }

    /// An FSEvents change. Changes within the debounce interval are combined into one scan.
    @discardableResult
    func folderDidChange(_ id: UUID) -> Task<Void, Never>? {
        guard !isSample, folder(id) != nil, canWrite else { return nil }
        debounceTasks[id]?.cancel()
        let delay = max(0, debounceInterval)
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.debounceTasks[id] = nil
            await self.scanFolder(id)?.value
        }
        debounceTasks[id] = task
        return task
    }

    /// Scans a folder off the main actor. A request while a scan runs is queued as one more pass.
    /// The returned task finishes after the queued passes.
    @discardableResult
    func scanFolder(_ id: UUID) -> Task<Void, Never>? {
        guard !isSample, canWrite, folder(id) != nil else { return nil }
        if let running = scanTasks[id] {
            rescanPending.insert(id)
            return running.task
        }
        serial += 1
        let token = serial
        let task = Task { [weak self] in
            var again = true
            while again {
                guard let self, self.scanTasks[id]?.token == token else { return }
                self.rescanPending.remove(id)
                await self.scanOnce(id)
                again = self.rescanPending.contains(id) && self.folder(id) != nil
            }
            if self?.scanTasks[id]?.token == token { self?.scanTasks[id] = nil }
        }
        scanTasks[id] = (token, task)
        return task
    }

    private func scanOnce(_ id: UUID) async {
        guard canWrite, let folder = folder(id) else { return }
        serial += 1
        let token = serial
        scanTokens[id] = token
        let snapshot = folderLedgers(id)
        if folderStatus[id] == .idle || folderStatus[id] == nil || folderStatus[id] == .unavailable { folderStatus[id] = .checking }
        let request = ScanRequest(folderID: id, bookmark: folder.bookmark, previous: snapshot, now: LedgerCoding.normalized(now()),
                                  excluded: Set(folder.excludedAppKeys))
        let access = folderAccess
        let outcome = await Task.detached(priority: .utility) {
            access.scan(request) { done, total in
                Task { @MainActor [weak self] in self?.reportProgress(id, token: token, done: done, total: total) }
            }
        }.value
        applyScan(outcome, folderID: id, token: token, snapshot: snapshot)
    }

    private func reportProgress(_ id: UUID, token: Int, done: Int, total: Int) {
        guard scanTokens[id] == token, total > 0 else { return }
        folderStatus[id] = .recording(done: min(done, total), total: total)
    }

    /// Applies one scan result to its own folder. Results with an old token, for a removed folder or for other
    /// folders' ledgers are dropped. A ledger that changed on the main actor during the scan keeps its new state,
    /// and its fingerprint is not updated, so the next scan reads it again.
    private func applyScan(_ outcome: ScanOutcome, folderID id: UUID, token: Int, snapshot: [AppLedger]) {
        guard scanTokens[id] == token, let folderIndex = folders.firstIndex(where: { $0.id == id }) else { return }
        scanTokens[id] = nil
        guard canWrite else { folderStatus[id] = .idle; return }
        switch outcome {
        case .unavailable:
            folderStatus[id] = .unavailable
            for ledger in folderLedgers(id) where !ledger.isRemoved { failures[ledger.id] = .accessUnavailable }
        case .recorded(let result, let renewed):
            if let renewed { folders[folderIndex].bookmark = renewed; saveFolders() }
            let before = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Exclusions as they are now, so an app removed while the scan ran is not recreated.
            let excluded = Set(folders[folderIndex].excludedAppKeys)
            var applied: Set<UUID> = []
            var changed = false
            for updated in result.ledgers where updated.source == .folder(id) && !(updated.appKey.map(excluded.contains) ?? false) {
                if let original = before[updated.id] {
                    guard let index = ledgers.firstIndex(where: { $0.id == updated.id }), ledgers[index] == original else { continue }
                    if ledgers[index] != updated { ledgers[index] = updated; changed = true }
                    applied.insert(updated.id)
                } else if !ledgers.contains(where: { $0.id == updated.id || ($0.source == .folder(id) && $0.appKey == updated.appKey) }) {
                    ledgers.append(updated)
                    applied.insert(updated.id)
                    changed = true
                }
            }
            // AutoRecorder drops a folder ledger with no entries when its app is gone.
            let kept = Set(result.ledgers.map(\.id))
            for original in snapshot where !kept.contains(original.id) {
                if let index = ledgers.firstIndex(where: { $0.id == original.id }), ledgers[index] == original {
                    ledgers.remove(at: index); verdicts[original.id] = nil; failures[original.id] = nil
                    changed = true
                }
            }
            for ledgerID in applied {
                failures[ledgerID] = result.failures[ledgerID]
                if let ledger = ledger(ledgerID) { verdicts[ledgerID] = LedgerChain.verify(ledger) }
            }
            folderStatus[id] = .idle
            if changed { commit() }
            let entries = result.newEntries.filter { applied.contains($0.ledgerID) }
            if snapshot.isEmpty && !entries.isEmpty {
                notice = "Recorded \(entries.count) \(entries.count == 1 ? "app" : "apps") in \(folders[folderIndex].name)."
            }
            if !showingRecent && selection.flatMap(ledger) == nil { selection = ledgers.first?.id }
            if !entries.isEmpty { onAutomaticEntries?(entries) }
        }
    }

    private func cancelScans() {
        for task in debounceTasks.values { task.cancel() }
        debounceTasks.removeAll()
        scanTokens.removeAll()
        scanTasks.removeAll()
        rescanPending.removeAll()
        for folder in folders where folderStatus[folder.id] != .unavailable { folderStatus[folder.id] = .idle }
    }

    /// Stops watching the folder and deletes its folder ledgers. The window asks for confirmation first.
    func removeFolder(_ id: UUID) {
        guard canWrite, folder(id) != nil else { return }
        watchers[id]?.stop(); watchers[id] = nil
        debounceTasks[id]?.cancel(); debounceTasks[id] = nil
        scanTokens[id] = nil; scanTasks[id] = nil; rescanPending.remove(id)
        folderStatus[id] = nil
        let gone = Set(folderLedgers(id).map(\.id))
        ledgers.removeAll { gone.contains($0.id) }
        for ledgerID in gone {
            active[ledgerID] = nil; failures[ledgerID] = nil; notices[ledgerID] = nil
            verdicts[ledgerID] = nil; verifiedAt[ledgerID] = nil; checkedAt[ledgerID] = nil
        }
        folders.removeAll { $0.id == id }
        if let selected = selection, gone.contains(selected) { selection = ledgers.first?.id }
        saveFolders()
        commit()
    }

    // MARK: inspection

    private func begin(_ id: UUID) -> Ticket {
        serial += 1
        let ticket = Ticket(id: id, serial: serial)
        active[id] = ticket
        return ticket
    }
    /// The index of the ledger when the ticket is still the current one for it.
    private func claim(_ ticket: Ticket) -> Int? {
        guard active[ticket.id] == ticket, let index = ledgers.firstIndex(where: { $0.id == ticket.id }) else { return nil }
        active[ticket.id] = nil
        return index
    }
    /// The blocking reading for a ledger. A watched-folder app is read through its folder's scope.
    private func reading(for ledger: AppLedger) -> @Sendable () -> InspectionResult {
        let id = ledger.id
        if let folderID = ledger.source.folderID {
            guard let folder = folder(folderID) else { return { .failed(.accessUnavailable) } }
            let access = folderAccess, bookmark = folder.bookmark, key = ledger.appKey
            return { access.inspectApp(folderID: folderID, folderBookmark: bookmark, appKey: key, ledgerID: id) }
        }
        let bookmark = ledger.bookmark, inspector = inspector
        return { inspector.inspect(bookmark: bookmark, id: id) }
    }
    private func run(_ id: UUID, then finish: @escaping @MainActor (LedgerModel, InspectionResult, Ticket) -> Void) -> Task<Void, Never>? {
        guard let ledger = ledger(id), canInspect(ledger) else { return nil }
        let ticket = begin(id)
        let read = reading(for: ledger)
        return Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { read() }.value
            guard let self else { return }
            finish(self, result, ticket)
        }
    }
    /// A complete reading of the same app, or nil after recording why it cannot be used.
    private func usable(_ result: InspectionResult, at index: Int) -> LedgerObservation? {
        let id = ledgers[index].id
        guard result.isComplete, let observation = result.observation else {
            let failure = result.failure ?? .bundleUnreadable
            failures[id] = failure
            notices[id] = failure == .accessUnavailable && ledgers[index].source.folderID != nil
                ? Self.folderAccessMessage : failure.safeMessage
            return nil
        }
        if let pinned = ledgers[index].pinnedBundleID, pinned != observation.bundleID {
            failures[id] = .identityDiffers
            notices[id] = InspectionFailure.identityDiffers.safeMessage
            return nil
        }
        failures[id] = nil
        let read = LedgerCoding.normalized(now())
        checkedAt[id] = read
        ledgers[index].lastCheckedAt = read
        return observation
    }

    @discardableResult
    func inspect(_ id: UUID) -> Task<Void, Never>? {
        run(id) { model, result, ticket in model.finishInspect(result, ticket: ticket) }
    }
    /// Keeps a renewed bookmark from a stale one. Saved by the caller.
    private func adoptBookmark(_ result: InspectionResult, at index: Int) {
        if let renewed = result.refreshedBookmark { ledgers[index].bookmark = renewed }
    }
    func finishInspect(_ result: InspectionResult, ticket: Ticket) {
        guard let index = claim(ticket) else { return }
        adoptBookmark(result, at: index)
        guard let observation = usable(result, at: index) else {
            if result.refreshedBookmark != nil { commit() }
            return
        }
        var ledger = ledgers[index]
        guard let entry = LedgerChain.append(observation, kind: .observed, to: &ledger) else {
            commit()
            notices[ticket.id] = "No change since entry \(ledger.latest?.seq ?? 0). Nothing was added."
            return
        }
        ledgers[index] = ledger
        verdicts[ticket.id] = LedgerChain.verify(ledger)
        commit()
        notices[ticket.id] = entry.anomalies.isEmpty
            ? "Entry \(entry.seq) recorded."
            : "Entry \(entry.seq) recorded. Review \(entry.anomalies.map(\.label).joined(separator: ", ").lowercased())."
    }

    /// Reads the copy again and accepts the latest entry only when the fresh reading matches it.
    @discardableResult
    func acknowledge(_ id: UUID) -> Task<Void, Never>? {
        guard let ledger = ledger(id), canAcknowledge(ledger) else { return nil }
        return run(id) { model, result, ticket in model.finishAcknowledge(result, ticket: ticket) }
    }
    func finishAcknowledge(_ result: InspectionResult, ticket: Ticket) {
        guard let index = claim(ticket) else { return }
        adoptBookmark(result, at: index)
        guard let observation = usable(result, at: index) else {
            if result.refreshedBookmark != nil { commit() }
            notices[ticket.id] = (notices[ticket.id] ?? "") + " Nothing was acknowledged."
            return
        }
        var ledger = ledgers[index]
        let outcome = LedgerChain.acknowledge(observation, in: &ledger)
        switch outcome {
        case .acknowledged(let entry):
            notices[ticket.id] = "Entry \(entry.seq) is now the reviewed baseline."
        case .changedSinceLatest(let entry):
            notices[ticket.id] = "The app changed since the latest entry. Entry \(entry.seq) was recorded instead. Review it, then acknowledge."
        case .nothingToAcknowledge:
            notices[ticket.id] = "There is no entry to acknowledge."
        case .alreadyAcknowledged:
            notices[ticket.id] = "The latest entry is already acknowledged."
        case .chainBroken:
            notices[ticket.id] = "The chain does not verify, so nothing was acknowledged. Export a copy and review the broken entry."
        }
        ledgers[index] = ledger
        verdicts[ticket.id] = LedgerChain.verify(ledger)
        commit()
    }

    /// Runs an acknowledgement on the calling thread. Used with the instant Sample inspector, for example by the
    /// screenshot renderer, where no run loop drains the main queue.
    func acknowledgeImmediately(_ id: UUID) {
        guard let ledger = ledger(id), canAcknowledge(ledger) else { return }
        let ticket = begin(id)
        finishAcknowledge(reading(for: ledger)(), ticket: ticket)
    }

    @discardableResult
    func verify(_ id: UUID) -> ChainVerdict? {
        guard let ledger = ledger(id) else { return nil }
        let verdict = LedgerChain.verify(ledger)
        verdicts[id] = verdict
        verifiedAt[id] = now()
        switch verdict {
        case .intact(let count): notices[id] = count == 0 ? "The ledger has no entries yet." : "Chain intact. \(count) \(count == 1 ? "entry" : "entries") verified."
        case .broken(let seq, let reason): notices[id] = "Chain broken at entry \(seq). \(reason)"
        }
        return verdict
    }

    // MARK: report

    func reportText(_ id: UUID) -> String? {
        guard let ledger = ledger(id) else { return nil }
        return LedgerReport.make(ledger, verdict: LedgerChain.verify(ledger), now: now(), sample: isSample)
    }
    @discardableResult
    func copyReport(_ id: UUID, write: (String) -> Bool = { text in
        NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(text, forType: .string) }) -> Bool {
        guard let text = reportText(id) else { return false }
        let ok = write(text)
        notices[id] = ok ? "Report copied." : "The report could not be copied."
        return ok
    }

    // MARK: export

    /// The exported document. LedgerFile strips bookmarks and path-like names.
    func exportData() throws -> Data {
        try LedgerFile(ledgers: ledgers, exportedAt: now()).encoded()
    }
    @discardableResult
    func export(to url: URL) -> Bool {
        do {
            try exportData().write(to: url, options: .atomic)
            notice = "Exported \(ledgers.count) \(ledgers.count == 1 ? "ledger" : "ledgers") to \(url.lastPathComponent)."
            return true
        } catch {
            notice = "The ledger file could not be saved there."
            return false
        }
    }
    static func suggestedFileName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return "NativeLedger \(f.string(from: date)).\(LedgerFile.fileExtension)"
    }
    func chooseExport() {
        guard canExport else {
            if isSample { notice = "Sample ledgers are not exported. Leave Sample to export your own ledgers." }
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Ledger"
        panel.message = "The file contains entries and hashes. It contains no file paths and no saved access."
        panel.prompt = "Export"
        panel.allowedContentTypes = [Self.ledgerType]
        panel.nameFieldStringValue = Self.suggestedFileName(now())
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        export(to: url)
    }

    // MARK: compare

    @discardableResult
    func compare(data: Data, source: String) -> Bool {
        guard data.count <= Self.maximumFileBytes else { notice = "That file is too large to be a ledger file."; return false }
        do {
            let file = try LedgerFile.decode(data)
            let brokenThere = file.ledgers.filter { !LedgerChain.verify($0).isIntact }
            let brokenHere = ledgers.filter { !LedgerChain.verify($0).isIntact }
            var comparison = Comparison(source: source, exportedAt: file.exportedAt,
                                        rows: CrossMacComparison.compare(here: ledgers, there: file),
                                        brokenInFile: brokenThere.count, sample: isSample)
            comparison.brokenHere = brokenHere.count
            comparison.unverified = Set((brokenThere + brokenHere).compactMap { $0.latest?.observation.bundleID })
            self.comparison = comparison
            notice = ""
            return true
        } catch LedgerFileError.unsupportedFormat(let format) {
            notice = "This file uses the format \(format), which this version cannot read."
        } catch {
            notice = "That file is not a NativeLedger ledger file."
        }
        return false
    }
    @discardableResult
    func compare(fileAt url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maximumFileBytes else { notice = "That file is too large to be a ledger file."; return false }
        guard let data = try? Data(contentsOf: url) else { notice = "That file could not be read."; return false }
        return compare(data: data, source: url.lastPathComponent)
    }
    /// The synthetic file from a second Mac that Sample compares with.
    func compareWithSampleFile() {
        if let data = try? SampleLedger.otherMac(now: now()).encoded() { compare(data: data, source: "Sample ledger from another Mac") }
    }
    func chooseCompare() {
        if isSample { compareWithSampleFile(); return }
        let panel = NSOpenPanel()
        panel.title = "Compare with Ledger File"
        panel.message = "Choose a .nativeledger file exported on another Mac. NativeLedger only reads it."
        panel.prompt = "Compare"
        panel.allowedContentTypes = [Self.ledgerType, .json]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        compare(fileAt: url)
    }
}
