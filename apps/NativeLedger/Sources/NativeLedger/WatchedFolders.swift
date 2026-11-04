import Foundation
import CoreServices
import LedgerCore

/// A folder the user chose with Watch a Folder. Only its display name and a read-only bookmark are kept.
struct WatchedFolder: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var bookmark: Data
    var addedAt: Date
    /// Path-free app keys whose ledger the user removed. Scans skip them until the folder is chosen again.
    var excludedAppKeys: [String]

    init(id: UUID, name: String, bookmark: Data, addedAt: Date, excludedAppKeys: [String] = []) {
        self.id = id; self.name = name; self.bookmark = bookmark; self.addedAt = addedAt
        self.excludedAppKeys = excludedAppKeys
    }
    enum CodingKeys: String, CodingKey { case id, name, bookmark, addedAt, excludedAppKeys }
    /// folders.json files written before exclusions existed still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        bookmark = try c.decode(Data.self, forKey: .bookmark)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        excludedAppKeys = try c.decodeIfPresent([String].self, forKey: .excludedAppKeys) ?? []
    }
}

/// folders.json next to ledgers.json in Application Support. Writes are atomic.
/// An unreadable file is copied aside before the list starts empty, so a bookmark is never silently overwritten.
final class FolderStore: @unchecked Sendable {
    static let fileName = "folders.json"
    static let schema = 1
    private struct Envelope: Codable { var schema: Int; var folders: [WatchedFolder] }
    enum Load: Equatable { case loaded([WatchedFolder]), corrupt(keptCopy: Bool) }

    let fileURL: URL
    /// True after an unreadable file could not be copied aside. Saving would overwrite the only copy, so the
    /// list is kept in memory until the next launch.
    private(set) var writesPaused = false
    struct WritesPaused: Error {}
    init(directory: URL) { fileURL = directory.appendingPathComponent(Self.fileName) }

    func load() -> Load {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return .loaded([]) }
        if let data = try? Data(contentsOf: fileURL),
           let envelope = try? LedgerCoding.decoder().decode(Envelope.self, from: data),
           envelope.schema == Self.schema, Set(envelope.folders.map(\.id)).count == envelope.folders.count {
            return .loaded(envelope.folders)
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copy = fileURL.deletingLastPathComponent().appendingPathComponent("folders.corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        let kept = (try? fm.copyItem(at: fileURL, to: copy)) != nil
        if kept { try? fm.removeItem(at: fileURL) } else { writesPaused = true }
        return .corrupt(keptCopy: kept)
    }

    func save(_ folders: [WatchedFolder]) throws {
        guard !writesPaused else { throw WritesPaused() }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LedgerCoding.encoder().encode(Envelope(schema: Self.schema, folders: folders)).write(to: fileURL, options: .atomic)
    }
}

/// One automatic pass over a watched folder, handed to the folder access off the main actor.
struct ScanRequest: Sendable {
    let folderID: UUID
    let bookmark: Data
    /// The ledgers of this folder when the scan started.
    let previous: [AppLedger]
    let now: Date
    /// App keys the user removed from this folder. Discovery skips them.
    var excluded: Set<String> = []
}

enum ScanOutcome: Equatable, Sendable {
    /// The bookmark did not resolve or the folder could not be listed. Nothing is marked removed.
    case unavailable
    case recorded(AutoRecordResult, refreshedBookmark: Data?)
}

/// A running folder watcher. stop() ends it and its security scope.
protocol FolderWatching: AnyObject {
    func stop()
}

/// The seam between the model and the file system for watched folders. Tests use a fake.
protocol FolderAccessing: Sendable {
    /// A read-only security-scoped bookmark for a folder the user chose.
    func bookmark(for folder: URL) throws -> Data
    /// True when the bookmark resolves to the given folder.
    func resolvesToSameFolder(_ bookmark: Data, _ folder: URL) -> Bool
    /// Discovers the folder inside its scope and runs AutoRecorder.step only when discovery returned a list.
    /// Blocking. The model calls it off the main actor. progress receives (done, total) full inspections.
    func scan(_ request: ScanRequest, progress: @escaping @Sendable (Int, Int) -> Void) -> ScanOutcome
    /// A full reading of one app of the folder, for Inspect now and Acknowledge. Blocking.
    func inspectApp(folderID: UUID, folderBookmark: Data, appKey: String?, ledgerID: UUID) -> InspectionResult
    /// Starts an FSEvents watcher for the folder. nil when the bookmark does not resolve.
    @MainActor func watch(_ bookmark: Data, onChange: @escaping @Sendable () -> Void) -> FolderWatching?
}

/// The pure part of a scan: discovery, the count of full inspections it will need, and the AutoRecorder step.
enum FolderScan {
    /// nil when the folder cannot be listed. Then no app is marked removed.
    static func run(root: URL, folderID: UUID, previous: [AppLedger], now: Date, excluded: Set<String> = [],
                    inspector: (URL) -> InspectionResult, progress: (Int, Int) -> Void = { _, _ in }) -> AutoRecordResult? {
        let recorder = AutoRecorder(folderID: folderID)
        guard let found = recorder.discover(root: root) else { return nil }
        let discovered = found.filter { !excluded.contains($0.key) }
        let total = pendingInspections(discovered, previous: previous, folderID: folderID)
        var done = 0
        progress(0, total)
        return recorder.step(previous: previous, discovered: discovered, inspector: { url in
            let result = inspector(url)
            done += 1
            progress(done, max(total, done))
            return result
        }, now: now)
    }

    /// Apps that the step will read in full: new apps, apps whose cheap fingerprint changed and apps that came back.
    static func pendingInspections(_ discovered: [DiscoveredApp], previous: [AppLedger], folderID: UUID) -> Int {
        var known: [String: AppLedger] = [:]
        for ledger in previous where ledger.source == .folder(folderID) {
            if let key = ledger.appKey, known[key] == nil { known[key] = ledger }
        }
        var seen: Set<String> = []
        return discovered.filter { app in
            guard seen.insert(app.key).inserted else { return false }
            guard let ledger = known[app.key] else { return true }
            return app.fingerprint == nil || app.fingerprint != ledger.lastFingerprint || ledger.isRemoved
        }.count
    }
}

/// Real folder access: security-scoped bookmarks, FolderCatalog discovery, the full LedgerInspector and FSEvents.
struct SystemFolderAccess: FolderAccessing {
    var inspector = LedgerInspector()

    func bookmark(for folder: URL) throws -> Data { try BookmarkInspector.bookmark(for: folder) }

    static func resolve(_ bookmark: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }

    func resolvesToSameFolder(_ bookmark: Data, _ folder: URL) -> Bool {
        guard let resolved = Self.resolve(bookmark)?.url else { return false }
        return resolved.standardizedFileURL.resolvingSymlinksInPath().path == folder.standardizedFileURL.resolvingSymlinksInPath().path
    }

    func scan(_ request: ScanRequest, progress: @escaping @Sendable (Int, Int) -> Void) -> ScanOutcome {
        guard let (root, stale) = Self.resolve(request.bookmark) else { return .unavailable }
        let active = root.startAccessingSecurityScopedResource()
        defer { if active { root.stopAccessingSecurityScopedResource() } }
        let inspector = inspector
        guard let result = FolderScan.run(root: root, folderID: request.folderID, previous: request.previous, now: request.now,
                                          excluded: request.excluded, inspector: { inspector.inspect($0) }, progress: progress) else { return .unavailable }
        let renewed = stale && active ? try? bookmark(for: root) : nil
        return .recorded(result, refreshedBookmark: renewed)
    }

    func inspectApp(folderID: UUID, folderBookmark: Data, appKey: String?, ledgerID: UUID) -> InspectionResult {
        guard let appKey, let (root, _) = Self.resolve(folderBookmark) else { return .failed(.accessUnavailable) }
        let active = root.startAccessingSecurityScopedResource()
        defer { if active { root.stopAccessingSecurityScopedResource() } }
        guard let app = AutoRecorder(folderID: folderID).discover(root: root)?.first(where: { $0.key == appKey }) else {
            return .failed(.accessUnavailable)
        }
        return inspector.inspect(app.url)
    }

    @MainActor func watch(_ bookmark: Data, onChange: @escaping @Sendable () -> Void) -> FolderWatching? {
        guard let (url, _) = Self.resolve(bookmark) else { return nil }
        let active = url.startAccessingSecurityScopedResource()
        guard let watcher = FSEventsWatcher(url: url, scoped: active, onChange: onChange) else {
            if active { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        return watcher
    }
}

/// An FSEvents stream on one folder. It holds the folder's security scope until stop().
final class FSEventsWatcher: FolderWatching, @unchecked Sendable {
    private let url: URL
    private let scoped: Bool
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.michaellip.nativeledger.fsevents")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    init?(url: URL, scoped: Bool, onChange: @escaping @Sendable () -> Void) {
        self.url = url; self.scoped = scoped; self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        // The stream is published under the lock before it starts, so the first callback sees it.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue().fired()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        guard let created = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else { return nil }
        FSEventStreamSetDispatchQueue(created, queue)
        lock.lock(); stream = created; lock.unlock()
        guard FSEventStreamStart(created) else {
            lock.lock(); stream = nil; lock.unlock()
            FSEventStreamInvalidate(created); FSEventStreamRelease(created)
            return nil
        }
    }
    private func fired() {
        lock.lock(); let running = stream != nil; lock.unlock()
        if running { onChange() }
    }
    func stop() {
        lock.lock(); let current = stream; stream = nil; lock.unlock()
        guard let current else { return }
        FSEventStreamStop(current)
        FSEventStreamInvalidate(current)
        // Waits for a callback that was already running, so it never outlives this object. stop() is never
        // called on this queue.
        queue.sync {}
        FSEventStreamRelease(current)
        if scoped { url.stopAccessingSecurityScopedResource() }
    }
    deinit { stop() }
}
