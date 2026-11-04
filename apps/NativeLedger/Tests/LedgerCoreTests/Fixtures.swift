import Foundation
@testable import LedgerCore

// Synthetic fixtures. No fixture represents a real app.
let t0 = Date(timeIntervalSince1970: 1_790_000_000.123_4)

func obs(_ id: String = "com.example.editor", version: String = "1.0", build: String = "100", arch: Arch = .universal,
         team: String? = "TEAMAAAAAA", ent: [String: String] = ["com.apple.security.app-sandbox": "true"],
         cdhash: String? = String(repeating: "a", count: 40), sha: String? = String(repeating: "b", count: 64),
         at: Date = t0) -> LedgerObservation {
    LedgerObservation(bundleID: id, version: version, build: build, architecture: arch,
                      signing: .read(identifier: id, team: team, entitlements: ent),
                      binary: BinaryIdentity(cdhash: cdhash, executableSHA256: sha), observedAt: at)
}

/// Three entries: 1.0, 1.1, 1.2, each a day apart.
func threeEntryLedger() -> AppLedger {
    var ledger = AppLedger(displayName: "Fixture Editor", bookmark: Data([1, 2, 3]))
    for (i, v) in ["1.0", "1.1", "1.2"].enumerated() {
        LedgerChain.append(obs(version: v, build: "\(i + 1)00", cdhash: String(repeating: "\(i + 1)", count: 40),
                               sha: String(repeating: "\(i + 4)", count: 64), at: t0.addingTimeInterval(Double(i) * 86400)),
                           kind: .observed, to: &ledger)
    }
    return ledger
}

func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("LedgerCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func brokenSeq(_ verdict: ChainVerdict) -> Int? {
    if case .broken(let seq, _) = verdict { return seq }
    return nil
}
