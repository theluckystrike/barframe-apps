import Foundation
import CryptoKit
import LedgerCore

/// The Sample as the window shows it: the core SampleLedger apps, three of them in a synthetic watched folder, and a
/// Sample Viewer update that adds a background item and fails the signature check. Memory only. It never reads real
/// apps, resolves bookmarks, starts watchers or opens the saved ledgers.
enum AppSample {
    static let folderID = UUID(uuidString: "5A3F00F0-0000-4000-8000-0000000000F0")!
    static let folderName = "Applications"
    /// errSecCSSignatureFailed. The Viewer update does not pass the signature check.
    static let failedSignatureCode: Int32 = -67061
    static let inFolder: Set<UUID> = [SampleLedger.editorID, SampleLedger.notesID, SampleLedger.viewerID]

    static func folder(now: Date) -> WatchedFolder {
        WatchedFolder(id: folderID, name: folderName, bookmark: Data(), addedAt: LedgerCoding.normalized(now.addingTimeInterval(-31 * 86400)))
    }

    static func digest(_ seed: String) -> String { SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// The Sample Viewer 3.1 reading: universal again, a new updater helper and an invalid signature.
    static func viewerUpdate(after previous: LedgerObservation, at date: Date) -> LedgerObservation {
        var o = previous
        o.version = "3.1"; o.build = "310"
        o.architecture = .universal
        o.architectureSlices = ["arm64", "x86_64"]
        o.backgroundItems = ["com.example.viewer.updater"]
        o.updateFeedURL = nil
        o.signatureValidity = .invalid(code: failedSignatureCode)
        o.binary = BinaryIdentity(cdhash: String(digest("cd-viewer-3.1").prefix(40)), executableSHA256: digest("viewer-3.1"))
        o.observedAt = date
        return o
    }

    static func ledgers(now: Date) -> [AppLedger] {
        var all = SampleLedger.ledgers(now: now)
        for i in all.indices where inFolder.contains(all[i].id) {
            all[i].source = .folder(folderID)
            all[i].appKey = AutoRecorder.appKey(folderID: folderID, relativePath: all[i].displayName + ".app", bundleID: all[i].pinnedBundleID)
            all[i].lastCheckedAt = LedgerCoding.normalized(now.addingTimeInterval(-1800))
        }
        if let v = all.firstIndex(where: { $0.id == SampleLedger.viewerID }), let latest = all[v].latest?.observation {
            LedgerChain.append(viewerUpdate(after: latest, at: now.addingTimeInterval(-5 * 3600)), kind: .observed, to: &all[v])
        }
        return all
    }

    /// Returns the latest content of each Sample app, so Inspect now and Acknowledge add no surprise entries.
    /// Sample Clock is unavailable, as a picked app whose access was lost.
    struct Inspector: AppInspecting {
        let base: [UUID: LedgerObservation]
        init(ledgers: [AppLedger]) {
            base = Dictionary(ledgers.compactMap { l in l.latest.map { (l.id, $0.observation) } }, uniquingKeysWith: { a, _ in a })
        }
        func inspect(bookmark: Data?, id: UUID) -> InspectionResult {
            guard id != SampleLedger.clockID, var o = base[id] else { return .failed(.accessUnavailable) }
            o.observedAt = Date()
            return InspectionResult(observation: o, failure: nil)
        }
    }

    /// Folder access for the Sample. It never touches the file system.
    struct FolderAccess: FolderAccessing {
        let inspector: Inspector
        func bookmark(for folder: URL) throws -> Data { throw CocoaError(.featureUnsupported) }
        func resolvesToSameFolder(_ bookmark: Data, _ folder: URL) -> Bool { false }
        func scan(_ request: ScanRequest, progress: @escaping @Sendable (Int, Int) -> Void) -> ScanOutcome {
            .recorded(AutoRecordResult(ledgers: request.previous, newEntries: [], inspectedCount: 0, failures: [:]), refreshedBookmark: nil)
        }
        func inspectApp(folderID: UUID, folderBookmark: Data, appKey: String?, ledgerID: UUID) -> InspectionResult {
            inspector.inspect(bookmark: nil, id: ledgerID)
        }
        @MainActor func watch(_ bookmark: Data, onChange: @escaping @Sendable () -> Void) -> FolderWatching? { nil }
    }
}
