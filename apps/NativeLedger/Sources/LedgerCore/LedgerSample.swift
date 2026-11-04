import Foundation

/// Synthetic ledgers for Sample mode and screenshots. Never reads real apps, bookmarks or the saved ledgers.
public enum SampleLedger {
    public static let editorID = UUID(uuidString: "5A3F0001-0000-4000-8000-000000000001")!
    public static let notesID = UUID(uuidString: "5A3F0002-0000-4000-8000-000000000002")!
    public static let viewerID = UUID(uuidString: "5A3F0003-0000-4000-8000-000000000003")!
    public static let clockID = UUID(uuidString: "5A3F0004-0000-4000-8000-000000000004")!
    static let sandbox = ["com.apple.security.app-sandbox": "true", "com.apple.security.files.user-selected.read-only": "true"]

    static func binary(_ seed: String) -> BinaryIdentity {
        let digest = Hex.sha256(Data(seed.utf8))
        return BinaryIdentity(cdhash: String(Hex.sha256(Data(("cd" + seed).utf8)).prefix(40)), executableSHA256: digest)
    }
    static func slices(_ arch: Arch) -> [String] {
        switch arch {
        case .universal: return ["arm64", "x86_64"]
        case .appleSilicon: return ["arm64"]
        case .intelOnly: return ["x86_64"]
        case .script, .unknown: return []
        }
    }
    static func usage(_ id: String) -> [String: String] {
        switch id {
        case "com.example.editor": return ["NSCameraUsageDescription": "Sample Editor uses the camera to scan pages."]
        case "com.example.notes": return ["NSMicrophoneUsageDescription": "Sample Notes records voice notes."]
        default: return [:]
        }
    }
    static func obs(_ id: String, _ version: String, _ build: String, _ arch: Arch = .universal, team: String = "TEAMAAAAAA",
                    ent: [String: String] = sandbox, seed: String, at date: Date) -> LedgerObservation {
        LedgerObservation(bundleID: id, version: version, build: build, architecture: arch,
                          signing: .read(identifier: id, team: team, entitlements: ent), binary: binary(seed), observedAt: date,
                          usageDescriptions: usage(id),
                          backgroundItems: id == "com.example.notes" ? ["com.example.notes.sync-helper"] : [],
                          updateFeedURL: id == "com.example.editor" ? "https://updates.example.com/editor/appcast.xml" : nil,
                          minimumSystemVersion: "14.0", architectureSlices: slices(arch), signatureValidity: .valid)
    }
    static func ledger(_ id: UUID, _ name: String, _ steps: [(LedgerObservation, EntryKind)]) -> AppLedger {
        var l = AppLedger(id: id, displayName: name)
        for (o, k) in steps { LedgerChain.append(o, kind: k, to: &l) }
        return l
    }
    static func days(_ now: Date, _ n: Double) -> Date { now.addingTimeInterval(-n * 86400) }

    /// The latest Sample Editor entry is a silent rebuild of version 2.4 build 240.
    public static func editorRebuild(at date: Date) -> LedgerObservation {
        obs("com.example.editor", "2.4", "240", seed: "editor-2.4-rebuilt", at: date)
    }

    public static func ledgers(now: Date) -> [AppLedger] {
        let e = "com.example.editor", n = "com.example.notes", v = "com.example.viewer", c = "com.example.clock"
        return [
            ledger(editorID, "Sample Editor", [
                (obs(e, "2.3", "230", seed: "editor-2.3", at: days(now, 30)), .observed),
                (obs(e, "2.3", "230", seed: "editor-2.3", at: days(now, 29)), .acknowledged),
                (obs(e, "2.4", "240", seed: "editor-2.4", at: days(now, 9)), .observed),
                (obs(e, "2.4", "240", seed: "editor-2.4", at: days(now, 8)), .acknowledged),
                (editorRebuild(at: now.addingTimeInterval(-3600)), .observed),
            ]),
            ledger(notesID, "Sample Notes", [
                (obs(n, "5.1", "510", .appleSilicon, seed: "notes-5.1", at: days(now, 20)), .observed),
                (obs(n, "5.2", "520", .appleSilicon, seed: "notes-5.2", at: days(now, 6)), .observed),
                (obs(n, "5.2", "520", .appleSilicon, seed: "notes-5.2", at: days(now, 5)), .acknowledged),
            ]),
            ledger(viewerID, "Sample Viewer", [
                (obs(v, "3.0", "300", seed: "viewer-3.0", at: days(now, 14)), .observed),
                (obs(v, "2.9", "290", .intelOnly, team: "TEAMBBBBBB",
                     ent: sandbox.merging(["com.apple.security.network.client": "true"]) { a, _ in a },
                     seed: "viewer-2.9", at: days(now, 2)), .observed),
            ]),
            ledger(clockID, "Sample Clock", [
                (obs(c, "1.0", "100", seed: "clock-1.0", at: days(now, 12)), .observed),
            ]),
        ]
    }

    /// A ledger file from a second Mac. It yields one row for each CrossMacVerdict.
    public static func otherMac(now: Date) -> LedgerFile {
        let e = "com.example.editor", n = "com.example.notes", v = "com.example.viewer", s = "com.example.sketch"
        return LedgerFile(ledgers: [
            ledger(UUID(uuidString: "5B3F0001-0000-4000-8000-000000000001")!, "Sample Editor",
                   [(obs(e, "2.4", "240", seed: "editor-2.4", at: days(now, 7)), .observed)]),
            ledger(UUID(uuidString: "5B3F0002-0000-4000-8000-000000000002")!, "Sample Notes",
                   [(obs(n, "5.2", "520", .appleSilicon, seed: "notes-5.2", at: days(now, 4)), .observed)]),
            ledger(UUID(uuidString: "5B3F0003-0000-4000-8000-000000000003")!, "Sample Viewer",
                   [(obs(v, "3.0", "300", seed: "viewer-3.0", at: days(now, 3)), .observed)]),
            ledger(UUID(uuidString: "5B3F0004-0000-4000-8000-000000000004")!, "Sample Sketch",
                   [(obs(s, "1.2", "120", seed: "sketch-1.2", at: days(now, 3)), .observed)]),
        ], exportedAt: days(now, 1))
    }

    /// Scripted inspector. Editor and Notes return their latest content, Viewer its latest content, Clock is unavailable.
    public struct Inspector: AppInspecting {
        let base: [UUID: LedgerObservation]
        public init(now: Date = Date()) {
            base = Dictionary(uniqueKeysWithValues: SampleLedger.ledgers(now: now).compactMap { l in l.latest.map { (l.id, $0.observation) } })
        }
        public func inspect(bookmark: Data?, id: UUID) -> InspectionResult {
            guard id != SampleLedger.clockID, var o = base[id] else { return .failed(.accessUnavailable) }
            o.observedAt = Date()
            return InspectionResult(observation: o, failure: nil)
        }
    }
}
