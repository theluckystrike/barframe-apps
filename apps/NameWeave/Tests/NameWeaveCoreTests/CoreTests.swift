import Foundation
import Testing
@testable import NameWeaveCore

@Test func reservedExtension() { #expect(Weave.reasons("AUX.txt").contains("Reserved device stem")) }
@Test func reservedMultipleExtensions() { #expect(Weave.reasons("nul.tar.gz").contains("Reserved device stem")) }
@Test func deviceDigits() { #expect(Weave.reasons("COM9.dat").contains("Reserved device stem")); #expect(Weave.reasons("COM0.dat").isEmpty) }
@Test func superscriptDigits() { #expect(Weave.reasons("LPT².txt").contains("Reserved device stem")) }
@Test func trailingPeriod() { #expect(Weave.reasons("Design.").contains("Trailing dot or space")) }
@Test func trailingSpace() { #expect(Weave.reasons("Design ").contains("Trailing dot or space")) }
@Test func forbiddenCharacters() { for name in ["a?b", "a*b", "a:b", "a\\b", "a/b", "a|b", "a\"b", "a<b", "a>b"] { #expect(Weave.reasons(name).contains("Restricted character")) } }
@Test func controlCharacters() { #expect(Weave.reasons("a\u{01}b").contains("Restricted character")) }
@Test func leadingDotAllowed() { #expect(Weave.reasons(".gitignore").isEmpty) }
@Test func emptyNames() { #expect(!Weave.reasons("").isEmpty); #expect(!Weave.reasons("..").isEmpty) }
@Test func componentBudgetUsesUTF16() { #expect(!Weave.reasons(String(repeating: "😀", count: 128)).isEmpty) }
@Test func sanitizeReserved() { #expect(Weave.sanitize("AUX.txt") == "_AUX.txt") }
@Test func sanitizeRestricted() { #expect(Weave.sanitize("report?.txt") == "report_.txt") }
@Test func sanitizeEmpty() { #expect(Weave.sanitize("... ") == "untitled") }
@Test func sanitizeLong() { #expect(Weave.sanitize(String(repeating: "😀", count: 150)).utf16.count <= 245) }
@Test func caseCollision() {
    let scan = Scan(entries: [Entry("Readme.md"), Entry("README.md")])
    #expect(Weave.plan(scan, policy: Policy(), edits: [:]).unresolvedCount == 2)
}
@Test func normalizationCollision() {
    let scan = Scan(entries: [Entry("é.txt"), Entry("e\u{301}.txt")])
    #expect(Weave.plan(scan, policy: Policy(), edits: [:]).unresolvedCount == 2)
}
@Test func normalizationPolicyCanDisable() {
    let scan = Scan(entries: [Entry("é.txt"), Entry("e\u{301}.txt")]); var policy = Policy(); policy.normalize = false
    #expect(Weave.plan(scan, policy: policy, edits: [:]).unresolvedCount == 0)
}
@Test func siblingScope() {
    let scan = Scan(entries: [Entry("a", directory: true), Entry("b", directory: true), Entry("a/Readme"), Entry("b/README")])
    #expect(Weave.plan(scan, policy: Policy(), edits: [:]).ready)
}
@Test func repairCreatedCollision() {
    let scan = Scan(entries: [Entry("report?.txt"), Entry("report*.txt")])
    let plan = Weave.plan(scan, policy: Policy(), edits: Weave.suggestions(scan))
    #expect(plan.unresolvedCount == 2); #expect(!plan.ready)
}
@Test func collisionsResolve() {
    #expect(Weave.plan(Weave.sample, policy: Policy(), edits: Weave.resolve(Weave.sample, policy: Policy(), edits: Weave.suggestions(Weave.sample))).ready)
}
@Test func existingCandidateProtected() {
    let scan = Scan(entries: [Entry("a*.txt"), Entry("a?.txt"), Entry("a_.txt"), Entry("a__2.txt")])
    let plan = Weave.plan(scan, policy: Policy(), edits: Weave.resolve(scan, policy: Policy(), edits: [:]))
    #expect(plan.ready); #expect(Set(plan.rows.map { Weave.key($0.proposed) }).count == 4)
}
@Test func parentPropagation() {
    #expect(Weave.virtual(Entry("bad./child.txt"), edits: ["bad.": "good"]) == "good/child.txt")
}
@Test func renamedParentsCollide() {
    let scan = Scan(entries: [Entry("a", directory: true), Entry("b", directory: true), Entry("a/first"), Entry("b/second")])
    #expect(!Weave.plan(scan, policy: Policy(), edits: ["b": "a"]).ready)
}
@Test func invalidParent() {
    let scan = Scan(entries: [Entry("a", directory: true), Entry("a/child")])
    #expect(Weave.plan(scan, policy: Policy(), edits: ["a": "bad?"]).rows.last?.unresolved.contains("Invalid parent replacement") == true)
}
@Test func proposalSeparatorIsInvalid() {
    #expect(!Weave.plan(Scan(entries: [Entry("a")]), policy: Policy(), edits: ["a": "x/y"]).ready)
}
@Test func emptyProposalIsInvalid() { #expect(!Weave.plan(Scan(entries: [Entry("a")]), policy: Policy(), edits: ["a": ""]).ready) }
@Test func fullDestinationLength() {
    var p = Policy(); p.prefix = "D:\\Drop\\"; #expect(Weave.targetLength("a/b.txt", policy: p) == "D:\\Drop\\a\\b.txt".utf16.count)
}
@Test func optionalLegacyBudget() {
    var p = Policy(); p.legacyBudget = 5
    #expect(!Weave.plan(Scan(entries: [Entry("long.txt")]), policy: p, edits: [:]).ready)
    p.legacyBudget = nil; #expect(Weave.plan(Scan(entries: [Entry("long.txt")]), policy: p, edits: [:]).ready)
}
@Test func renamedParentChangesLength() {
    var p = Policy(); p.legacyBudget = 5
    let scan = Scan(entries: [Entry("long", directory: true), Entry("long/a")])
    #expect(!Weave.plan(scan, policy: p, edits: [:]).ready)
    #expect(Weave.plan(scan, policy: p, edits: ["long": "x"]).ready)
}
@Test func incompleteNeverReady() {
    var c = Coverage(); c.omissions = ["permission denied"]
    #expect(!Weave.plan(Scan(entries: [], coverage: c), policy: Policy(), edits: [:]).ready)
}
@Test func cancelledNeverReady() {
    var c = Coverage(); c.cancelled = true
    #expect(!Weave.plan(Scan(entries: [], coverage: c), policy: Policy(), edits: [:]).ready)
}
func temporaryDirectory() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
@Test func enumerateRealTree() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("sub/AUX.txt"))
    let result = Scanner.scan(root, policy: Policy()); #expect(result.coverage.complete); #expect(result.entries.count == 2)
}
@Test func skippedSymlink() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root)
    let result = Scanner.scan(root, policy: Policy()); #expect(result.entries.isEmpty); #expect(!result.coverage.complete)
}
@Test func scanLimitHonest() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent("a")); try Data().write(to: root.appendingPathComponent("b"))
    let result = Scanner.scan(root, policy: Policy(), limit: 1); #expect(result.entries.count == 1); #expect(!result.coverage.complete)
}
@Test func missingRootHonest() { #expect(!Scanner.scan(URL(fileURLWithPath: "/missing/" + UUID().uuidString), policy: Policy()).coverage.complete) }
@Test func excludeSubtreeHonest() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("skip"), withIntermediateDirectories: true)
    var p = Policy(); p.exclusions = ["skip"]
    let result = Scanner.scan(root, policy: p); #expect(result.entries.isEmpty); #expect(!result.coverage.complete)
}
@Test func cancellationStopsScan() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let cancel = ScanCancellation(); cancel.cancel()
    #expect(Scanner.scan(root, policy: Policy(), cancellation: cancel).coverage.cancelled)
}
@Test func stateRoundtrip() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }; let url = root.appendingPathComponent("state.json")
    var state = SavedState(); state.bookmark = Data([1, 2]); state.scan = Weave.sample; state.edits = Weave.suggestions(Weave.sample); state.policy.prefix = "example"; state.checkedAt = Date()
    try StateStore.save(state, to: url); let loaded = try StateStore.load(url)
    #expect(loaded.bookmark == state.bookmark); #expect(loaded.scan?.entries == state.scan?.entries); #expect(loaded.edits == state.edits); #expect(loaded.policy == state.policy)
}
@Test func corruptStateThrows() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }; let url = root.appendingPathComponent("state.json"); try Data("corrupt".utf8).write(to: url)
    #expect(throws: (any Error).self) { try StateStore.load(url) }
}
@Test func copiedSampleIncludesContext() {
    let plan = Weave.plan(Weave.sample, policy: Policy(), edits: Weave.suggestions(Weave.sample))
    let text = plan.report(sample: true)
    #expect(text.hasPrefix("Sample")); #expect(text.contains("Unresolved")); #expect(text.contains("Source files remain unchanged")); #expect(text.contains("report?.txt → report_.txt"))
}
@Test func copiedStaleCannotClaimReady() {
    let plan = Weave.plan(Scan(entries: [Entry("clear.txt")]), policy: Policy(), edits: [:]); #expect(plan.ready)
    #expect(!plan.report(sample: false, stale: true).contains("\nReady\n"))
}

@Test func validLongNamesStayUnchanged() { let name = String(repeating: "a", count: 250); #expect(Weave.sanitize(name) == name) }
@Test func resolvedLongCollisionFitsBudget() {
    let stem = String(repeating: "a", count: 247)
    let scan = Scan(entries: [Entry(stem + "?.txt"), Entry(stem + "*.txt")])
    #expect(Weave.plan(scan, policy: Policy(), edits: Weave.resolve(scan, policy: Policy(), edits: [:])).ready)
}

@Test func unicodeSourceIDsRemainDistinct() {
    #expect(Entry("é?.txt").id != Entry("e\u{301}?.txt").id)
    let scan = Scan(entries: [Entry("é?.txt"), Entry("e\u{301}?.txt")])
    #expect(Weave.suggestions(scan).count == 2)
    #expect(Weave.plan(scan, policy: Policy(), edits: Weave.resolve(scan, policy: Policy(), edits: Weave.suggestions(scan))).ready)
}
@Test func symlinkRootIsNotFollowed() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let link = root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    #expect(!Scanner.scan(link, policy: Policy()).coverage.complete)
}

@Test func unchangedNamesAreReservedBeforeRepairs() {
    let scan = Scan(entries: [Entry("report?.txt"), Entry("report_.txt"), Entry("report__2.txt")])
    let edits = Weave.resolve(scan, policy: Policy(), edits: Weave.suggestions(scan))
    #expect(edits[Entry("report_.txt").id] == nil); #expect(edits[Entry("report__2.txt").id] == nil)
    #expect(edits[Entry("report?.txt").id] == "report__3.txt")
    #expect(Weave.plan(scan, policy: Policy(), edits: edits).ready)
}
@Test func scannerSkipsHiddenTreesAndTreatsPackagesAsItems() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    for directory in [".git/objects", "Tool.app/Contents", "visible"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(directory + "/AUX.txt"))
    }
    try Data().write(to: root.appendingPathComponent(".DS_Store"))
    let scan = Scanner.scan(root, policy: Policy())
    #expect(scan.coverage.complete)
    #expect(scan.entries.map(\.path) == ["Tool.app", "visible", "visible/AUX.txt"])
}
@Test func sampleAndLiveApplyTheSameExclusionCoverage() {
    var policy = Policy(); policy.exclusions = ["archive"]
    let result = Weave.applyingExclusions(policy, to: Weave.sample)
    #expect(!result.coverage.complete); #expect(!result.entries.contains { $0.path.hasPrefix("archive") })
    #expect(result.coverage.omissions == ["Excluded directory archive"])
}

@Test func dependencyTreesDoNotConsumeScanLimit() throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules/vendor"), withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("node_modules/vendor/AUX.txt"))
    let scan = Scanner.scan(root, policy: Policy(), limit: 1)
    #expect(scan.entries.map(\.path) == ["node_modules"])
    #expect(scan.coverage.omissions == ["Dependency directory contents skipped node_modules"])
    #expect(!Weave.plan(scan, policy: Policy(), edits: [:]).ready)
}
