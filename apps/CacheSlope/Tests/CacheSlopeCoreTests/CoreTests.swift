import Foundation
import Testing
@testable import CacheSlopeCore

@Test func aggregation() { #expect(Snapshot(sizes: ["a": 12, "b": 8]).total == 20) }
@Test func emptyTotal() { #expect(Snapshot(sizes: [:]).total == 0) }
@Test func growth() { #expect(Analysis.compare(Snapshot(sizes: ["a": 15]), to: Snapshot(sizes: ["a": 10])).first?.delta == 5) }
@Test func shrink() { #expect(Analysis.compare(Snapshot(sizes: ["a": 4]), to: Snapshot(sizes: ["a": 10])).first?.delta == -6) }
@Test func missingBaseline() { #expect(Analysis.compare(Snapshot(sizes: ["a": 2]), to: nil).isEmpty) }
@Test func partialCurrent() { #expect(Analysis.compare(Fixtures.partial, to: Fixtures.history.first).isEmpty) }
@Test func partialBaseline() { #expect(Analysis.compare(Fixtures.history[0], to: Fixtures.partial).isEmpty) }
@Test func removedFolder() { let result = Analysis.compare(Snapshot(sizes: [:]), to: Snapshot(sizes: ["a": 10])); #expect(result.first?.bytes == 0); #expect(result.first?.delta == -10) }
@Test func newFolder() { #expect(Analysis.compare(Snapshot(sizes: ["a": 10]), to: Snapshot(sizes: [:])).first?.delta == 10) }
@Test func largestFirst() { #expect(Analysis.compare(Fixtures.history[1], to: Fixtures.history[0]).first?.name == "Dependencies") }
@Test func tieOrder() { #expect(Analysis.compare(Snapshot(sizes: ["b": 1, "a": 1]), to: Snapshot(sizes: [:])).map(\.name) == ["a", "b"]) }
@Test func latestComplete() { #expect(Analysis.pair(Fixtures.history + [Fixtures.partial], pinned: nil).0?.sizes == Fixtures.history.last?.sizes) }
@Test func firstScan() { #expect(Analysis.pair([Fixtures.history[0]], pinned: nil).1 == nil) }
@Test func pinnedBaseline() { let pinned = Snapshot(sizes: ["a": 1]); #expect(Analysis.pair(Fixtures.history, pinned: pinned).1 == pinned) }
@Test func partialPinRejected() { #expect(Analysis.pair(Fixtures.history, pinned: Fixtures.partial).1?.sizes == Fixtures.history.first?.sizes) }
@Test func retention() { let h = Fixtures.history + [Fixtures.partial]; #expect(Analysis.retain(h, limit: 2) == Array(h.suffix(2))) }
@Test func retentionMinimum() { #expect(Analysis.retain(Fixtures.history, limit: 0).count == 2) }
@Test func thresholdOff() { #expect(!Analysis.attention(Analysis.compare(Fixtures.history[1], to: Fixtures.history[0]), threshold: 0)) }
@Test func thresholdExceeded() { #expect(Analysis.attention(Analysis.compare(Fixtures.history[1], to: Fixtures.history[0]), threshold: 500_000_000)) }
@Test func thresholdEquality() { #expect(!Analysis.attention(Analysis.compare(Snapshot(sizes: ["a": 5]), to: Snapshot(sizes: [:])), threshold: 5)) }
@Test func staleBookmark() { #expect(Analysis.bookmarkNeedsRecovery(stale: true, access: true)) }
@Test func deniedBookmark() { #expect(Analysis.bookmarkNeedsRecovery(stale: false, access: false)) }
@Test func validBookmark() { #expect(!Analysis.bookmarkNeedsRecovery(stale: false, access: true)) }
@Test func reportUnits() { #expect(Analysis.report([]).contains("Logical file bytes")) }
@Test func sampleIsolation() { var sample = Fixtures.history; sample.removeAll(); #expect(Fixtures.history.count == 2) }
@Test func serialization() throws { let s = Fixtures.partial; #expect(try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s)) == s) }
func temporaryRoot() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
@Test func scanFilesGrouped() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("child/deep"), withIntermediateDirectories: true)
    try Data(repeating: 0, count: 17).write(to: root.appendingPathComponent("child/deep/file"))
    try Data(repeating: 0, count: 4).write(to: root.appendingPathComponent("top"))
    let s = Scanner.scan(root); #expect(s.complete); #expect(s.sizes["child"] == 17); #expect(s.sizes["Files in root"] == 4)
}
@Test func symlinkSkipped() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 0, count: 9).write(to: root.appendingPathComponent("file"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("file"))
    let s = Scanner.scan(root); #expect(s.total == 9); #expect(!s.complete); #expect(s.issues.count == 1)
}
@Test func cancellation() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("file"))
    let s = Scanner.scan(root, cancelled: { true }); #expect(s.cancelled); #expect(!s.complete)
}
@Test func emptyFolderComplete() throws { let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }; let s = Scanner.scan(root); #expect(s.complete); #expect(s.total == 0) }

@Test func missingRootIsPartial() { #expect(!Scanner.scan(URL(fileURLWithPath: "/nonexistent-CacheSlope-test-folder")).complete) }
@Test func cancellationEmptyFolder() throws { let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }; #expect(Scanner.scan(root, cancelled: { true }).cancelled) }

@Test func pinCurrentKeepsPreviousComparison() {
    let previous = Snapshot(sizes: ["cache": 10])
    let current = Snapshot(sizes: ["cache": 25])
    let pair = Analysis.pair([previous, current], pinned: current)
    #expect(Analysis.compare(pair.0!, to: pair.1).first?.delta == 15)
    let next = Snapshot(sizes: ["cache": 30])
    let later = Analysis.pair([previous, current, next], pinned: current)
    #expect(Analysis.compare(later.0!, to: later.1).first?.delta == 5)
}
