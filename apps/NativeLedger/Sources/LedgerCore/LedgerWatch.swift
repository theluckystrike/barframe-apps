import Foundation

/// Lists the .app bundles of a watched folder.
public enum FolderCatalog {
    static let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isPackageKey]

    /// .app bundles at depth 1 and depth 2, sorted by their path inside the folder.
    /// Symlinks are skipped. Bundles and other packages are never entered.
    public static func enumerate(root: URL) -> [URL] { (entries(root: root) ?? []).map(\.url) }

    /// True when the folder can be listed. A watched folder that cannot be listed must not be treated as empty.
    public static func isReadable(root: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) != nil
    }

    /// nil when the root itself cannot be listed, so a listing failure is never read as an empty folder.
    static func entries(root: URL) -> [(url: URL, relativePath: String)]? {
        let fm = FileManager.default
        func list(_ dir: URL) -> [URL]? {
            try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        }
        func children(_ dir: URL) -> [URL] { list(dir) ?? [] }
        guard let top = list(root) else { return nil }
        func kind(_ url: URL) -> (app: Bool, folder: Bool) {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true, v.isDirectory == true else {
                return (false, false)
            }
            if url.pathExtension.lowercased() == "app" { return (true, false) }
            return (false, v.isPackage != true)
        }
        var out: [(url: URL, relativePath: String)] = []
        for child in top {
            let k = kind(child)
            if k.app { out.append((child, child.lastPathComponent)); continue }
            guard k.folder else { continue }
            for grandchild in children(child) where kind(grandchild).app {
                out.append((grandchild, child.lastPathComponent + "/" + grandchild.lastPathComponent))
            }
        }
        return out.sorted { $0.relativePath < $1.relativePath }
    }
}

/// One app found in a watched folder, with its cheap fingerprint.
public struct DiscoveredApp: Equatable, Sendable {
    /// Path-free key, stable while the app keeps its place in the folder and its bundle identifier.
    public var key: String
    public var url: URL
    public var displayName: String
    public var fingerprint: Fingerprint?
    public init(key: String, url: URL, displayName: String, fingerprint: Fingerprint?) {
        self.key = key; self.url = url; self.displayName = displayName; self.fingerprint = fingerprint
    }
}

/// An entry appended by an automatic step.
public struct RecordedEntry: Equatable, Sendable {
    public var ledgerID: UUID
    public var displayName: String
    public var entry: LedgerEntry
    public init(ledgerID: UUID, displayName: String, entry: LedgerEntry) {
        self.ledgerID = ledgerID; self.displayName = displayName; self.entry = entry
    }
}

public struct AutoRecordResult: Equatable, Sendable {
    public var ledgers: [AppLedger]
    public var newEntries: [RecordedEntry]
    /// Number of full inspections run in this step.
    public var inspectedCount: Int
    /// Ledgers whose inspection in this step did not give a complete result.
    public var failures: [UUID: InspectionFailure]
    public init(ledgers: [AppLedger], newEntries: [RecordedEntry], inspectedCount: Int, failures: [UUID: InspectionFailure]) {
        self.ledgers = ledgers; self.newEntries = newEntries; self.inspectedCount = inspectedCount; self.failures = failures
    }
}

/// Keeps the ledgers of one watched folder up to date. Pure apart from the inspector it is given.
public struct AutoRecorder: Sendable {
    public let folderID: UUID
    public init(folderID: UUID) { self.folderID = folderID }

    /// A digest of the folder ID, the path inside the folder and the bundle identifier. It holds no path.
    public static func appKey(folderID: UUID, relativePath: String, bundleID: String?) -> String {
        "k1-" + String(Hex.sha256(Data("\(folderID.uuidString)\n\(relativePath)\n\(bundleID ?? "")".utf8)).prefix(32))
    }

    /// Enumerates the folder and reads each cheap fingerprint. nil when the folder cannot be listed.
    public func discover(root: URL) -> [DiscoveredApp]? {
        // One listing decides both readability and content, so a folder that fails between two listings is
        // never treated as empty (which would mark every app removed).
        guard let entries = FolderCatalog.entries(root: root) else { return nil }
        return entries.map { url, relative in
            let bundleID = MachOArchitecture.infoPlist(url)["CFBundleIdentifier"] as? String
            return DiscoveredApp(key: Self.appKey(folderID: folderID, relativePath: relative, bundleID: bundleID), url: url,
                                 displayName: MachOArchitecture.displayName(at: url), fingerprint: CheapFingerprint.of(bundle: url))
        }
    }

    /// One automatic pass.
    /// - New apps get a ledger with source folder and a first observed entry.
    /// - Known apps are inspected only when the cheap fingerprint differs from the last inspection, or when they return after removal.
    /// - Apps of this folder that are no longer discovered get one removed entry. Ledgers with no entries are dropped instead.
    /// - Ledgers of other folders and picked apps are returned unchanged.
    /// Pass the result of discover only when it is not nil.
    public func step(previous: [AppLedger], discovered: [DiscoveredApp], inspector: (URL) -> InspectionResult,
                     now: Date) -> AutoRecordResult {
        var ledgers = previous
        var newEntries: [RecordedEntry] = []
        var failures: [UUID: InspectionFailure] = [:]
        var inspected = 0
        var index: [String: Int] = [:]
        for (i, l) in ledgers.enumerated() where l.source == .folder(folderID) {
            if let key = l.appKey, index[key] == nil { index[key] = i }
        }

        func record(_ app: DiscoveredApp, into ledger: inout AppLedger) {
            inspected += 1
            let result = inspector(app.url)
            if let obs = result.observation, result.isComplete {
                if let pinned = ledger.pinnedBundleID, pinned != obs.bundleID {
                    failures[ledger.id] = .identityDiffers
                    return
                }
                if let entry = LedgerChain.append(obs, kind: .observed, to: &ledger) {
                    newEntries.append(RecordedEntry(ledgerID: ledger.id, displayName: ledger.displayName, entry: entry))
                }
                ledger.lastFingerprint = app.fingerprint
                ledger.lastCheckedAt = LedgerCoding.normalized(obs.observedAt)
                return
            }
            let failure = result.failure ?? .bundleUnreadable
            failures[ledger.id] = failure
            // A changed bundle is read again next time. Other failures wait for the next fingerprint change.
            if failure != .changedDuringInspection { ledger.lastFingerprint = app.fingerprint }
        }

        var seen: Set<String> = []
        for app in discovered where !seen.contains(app.key) {
            seen.insert(app.key)
            if let i = index[app.key] {
                let unchanged = app.fingerprint != nil && app.fingerprint == ledgers[i].lastFingerprint && !ledgers[i].isRemoved
                if unchanged { continue }
                record(app, into: &ledgers[i])
            } else {
                var ledger = AppLedger(displayName: app.displayName, source: .folder(folderID), appKey: app.key)
                record(app, into: &ledger)
                ledgers.append(ledger)
            }
        }

        var drop: Set<UUID> = []
        for i in ledgers.indices where ledgers[i].source == .folder(folderID) {
            guard let key = ledgers[i].appKey, !seen.contains(key) else { continue }
            if ledgers[i].entries.isEmpty { drop.insert(ledgers[i].id); continue }
            if let entry = LedgerChain.markRemoved(&ledgers[i], at: now) {
                ledgers[i].lastFingerprint = nil
                newEntries.append(RecordedEntry(ledgerID: ledgers[i].id, displayName: ledgers[i].displayName, entry: entry))
            }
        }
        if !drop.isEmpty { ledgers.removeAll { drop.contains($0.id) } }
        return AutoRecordResult(ledgers: ledgers, newEntries: newEntries, inspectedCount: inspected, failures: failures)
    }
}
