import Foundation
import LedgerCore
@testable import NativeLedger

let appT0 = Date(timeIntervalSince1970: 1_790_000_000)

func observation(_ id: String = "com.example.tool", version: String = "1.0", build: String = "100",
                 team: String? = "TEAMAAAAAA", cdhash: String = String(repeating: "a", count: 40),
                 sha: String = String(repeating: "b", count: 64), at: Date = appT0) -> LedgerObservation {
    LedgerObservation(bundleID: id, version: version, build: build, architecture: .universal,
                      signing: .read(identifier: id, team: team, entitlements: ["com.apple.security.app-sandbox": "true"]),
                      binary: BinaryIdentity(cdhash: cdhash, executableSHA256: sha), observedAt: at)
}

/// Returns queued results in order, repeating the last one. An optional gate holds each call until released.
final class ScriptedInspector: AppInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [InspectionResult]
    private(set) var calls = 0
    let gate: DispatchSemaphore?
    init(_ results: [InspectionResult], gated: Bool = false) {
        queue = results
        gate = gated ? DispatchSemaphore(value: 0) : nil
    }
    func inspect(bookmark: Data?, id: UUID) -> InspectionResult {
        gate?.wait()
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return queue.count > 1 ? queue.removeFirst() : (queue.first ?? .failed(.bundleUnreadable))
    }
}

extension InspectionResult {
    static func complete(_ o: LedgerObservation) -> InspectionResult { InspectionResult(observation: o, failure: nil) }
}

func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("NativeLedgerAppTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A minimal app bundle folder. Only its location matters for bookmarks.
func fakeApp(in folder: URL, named name: String = "Tool") throws -> URL {
    let app = folder.appendingPathComponent("\(name).app")
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": "com.example.\(name.lowercased())", "CFBundleExecutable": name,
                                "CFBundleShortVersionString": "1.0", "CFBundleVersion": "100"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    return app
}
