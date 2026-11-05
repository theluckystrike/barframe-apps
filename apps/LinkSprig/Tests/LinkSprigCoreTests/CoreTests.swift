import Foundation
import Testing
@testable import LinkSprigCore

func fixture(_ links: [DocumentLink]) -> Tree { Tree(nodes: ["guide.md", "archive", "images", "images/diagram.png", "nested", "nested/readme.md"], directories: ["", "archive", "images", "nested"], links: links) }
func link(_ target: String, source: String = "guide.md", line: Int = 1) -> DocumentLink { DocumentLink(source: source, line: line, target: target) }
@Test func inlineLink() { #expect(Markdown.parse("[Guide](guide.md)", source: "a.md").first?.target == "guide.md") }
@Test func imageLink() { #expect(Markdown.parse("![Image](a.png)", source: "a.md").first?.image == true) }
@Test func omitImages() { #expect(Markdown.parse("![Image](a.png)", source: "a.md", includeImages: false).isEmpty) }
@Test func referenceDefinition() { #expect(Markdown.parse("[g]: guide.md \"title\"", source: "a.md").first?.target == "guide.md") }
@Test func angleTarget() { #expect(Markdown.parse("[g](<a b.md>)", source: "a.md").first?.target == "a b.md") }
@Test func sourceLine() { #expect(Markdown.parse("hello\n[g](g.md)", source: "a.md").first?.line == 2) }
@Test func backtickFence() { #expect(Markdown.parse("```md\n[g](g.md)\n```", source: "a.md").isEmpty) }
@Test func tildeFence() { #expect(Markdown.parse("~~~\n[g](g.md)\n~~~\n[g](a.md)", source: "a.md").count == 1) }
@Test func shorterFenceDoesNotClose() { #expect(Markdown.parse("````\n```\n[g](g.md)\n````", source: "a.md").isEmpty) }
@Test func inlineCode() { #expect(Markdown.parse("`[g](g.md)`", source: "a.md").isEmpty) }
@Test func wikiUnchecked() { #expect(Markdown.parse("[[Guide]]", source: "a.md").first?.unchecked == true) }
@Test func htmlUnchecked() { #expect(Markdown.parse("<a href='g.md'>Guide</a>", source: "a.md").first?.unchecked == true) }
@Test func nestedUnchecked() { #expect(Markdown.parse("[g](a(b).md)", source: "a.md").first?.unchecked == true) }
@Test func normalizeDots() { #expect(PathRules.normalize("../guide.md", relativeTo: "nested") == "guide.md") }
@Test func refuseEscape() { #expect(PathRules.normalize("../../g", relativeTo: "nested") == nil) }
@Test func refuseAbsolute() { #expect(PathRules.normalize("/tmp/g") == nil) }
@Test func percentSpace() { #expect(Target.resolve(link("some%20guide.md")) == .local("some guide.md", "")) }
@Test func encodedHash() { #expect(Target.resolve(link("a%23b.md#heading")) == .local("a#b.md", "#heading")) }
@Test func fragmentOnly() { #expect(Target.resolve(link("#heading")) == .fragment) }
@Test func externalScheme() { #expect(Target.resolve(link("mailto:a@example.invalid")) == .external) }
@Test func queryUnchecked() { #expect(Target.resolve(link("g.md?x=1")) == .unchecked) }
@Test func invalidEncodingUnchecked() { #expect(Target.resolve(link("g%ZZ.md")) == .unchecked) }
@Test func movedSource() throws { let p = try Planner.plan(tree: fixture([link("images/diagram.png")]), proposal: Sample.proposal); #expect(p.affected.first?.replacement == "../images/diagram.png"); #expect(p.broken.count == 1) }
@Test func movedTarget() throws { let p = try Planner.plan(tree: fixture([link("../guide.md", source: "nested/readme.md")]), proposal: Sample.proposal); #expect(p.affected.first?.replacement == "../archive/guide.md") }
@Test func preserveFragment() throws { let p = try Planner.plan(tree: fixture([link("images/diagram.png#demo")]), proposal: Sample.proposal); #expect(p.affected.first?.replacement == "../images/diagram.png#demo"); #expect(p.incomplete) }
@Test func preexistingSeparate() throws { let p = try Planner.plan(tree: fixture([link("missing.png")]), proposal: Sample.proposal); #expect(p.preexisting.count == 1); #expect(p.broken.isEmpty) }
@Test func destinationCollision() { #expect(throws: ProposalError.conflict) { try Proposal(source: "guide.md", destination: "nested/readme.md").validated(in: fixture([])) } }
@Test func selfDirectoryMove() { #expect(throws: ProposalError.selfMove) { try Proposal(source: "nested", destination: "nested/sub").validated(in: fixture([])) } }
@Test func newParentsAllowed() throws { #expect(try Proposal(source: "guide.md", destination: "new/deep/guide.md").validated(in: fixture([])).destination == "new/deep/guide.md") }
@Test func missingSource() { #expect(throws: ProposalError.missing) { try Proposal(source: "missing", destination: "archive/missing").validated(in: fixture([])) } }
@Test func movedDirectoryInternalLinks() throws { let t = Tree(nodes: ["docs", "docs/a.md", "docs/b.md", "archive"], directories: ["", "docs", "archive"], links: [link("b.md", source: "docs/a.md")]); #expect(try Planner.plan(tree: t, proposal: Proposal(source: "docs", destination: "archive/docs")).affected.isEmpty) }
@Test func existingWrongTargetStillAffected() throws { var t = fixture([link("images/diagram.png")]); t.nodes.insert("archive/images/diagram.png"); let p = try Planner.plan(tree: t, proposal: Sample.proposal); #expect(p.affected.first?.kind == .changed) }
@Test func prefixBoundary() { #expect(Proposal(source: "doc", destination: "archive/doc").map("docs/a.md") == "docs/a.md") }
@Test func relativeSibling() { #expect(PathRules.relative(from: "docs/a.md", to: "docs/b.md") == "b.md") }
@Test func relativeEncode() { #expect(PathRules.encode("a b#c.md") == "a%20b%23c.md") }
@Test func persistenceRoundTrip() throws { let state = SavedState(bookmark: Data([1,2]), rootName: "Docs", proposal: Sample.proposal); #expect(SavedState.load(try JSONEncoder().encode(state)).0 == state) }
@Test func corruptRecovery() { let loaded = SavedState.load(Data("broken".utf8)); #expect(loaded.1); #expect(loaded.0.bookmark == nil) }
@Test func sampleReportLabeled() throws { let p = try Planner.plan(tree: fixture([link("images/diagram.png")]), proposal: Sample.proposal); #expect(p.report(sample: true).contains("Sample")); #expect(p.report(sample: true).contains("line 1")) }
@Test func warningPreventsClear() throws { var t = fixture([]); t.warnings = ["Unreadable descendant"]; #expect(try Planner.plan(tree: t, proposal: Sample.proposal).state == "0 affected · Incomplete") }
@Test func scanSymlinkAndDryRun() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try Sample.create(at: root)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
    let before = try Data(contentsOf: root.appendingPathComponent("guide.md"))
    let t = try Scanner.scan(root: root); #expect(!t.nodes.contains("escape")); #expect(!t.warnings.isEmpty)
    let p = try Planner.plan(tree: t, proposal: Sample.proposal); #expect(p.affected.count == 3)
    #expect(try Data(contentsOf: root.appendingPathComponent("guide.md")) == before)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("archive/guide.md").path))
}
@Test func excludedCoverage() throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }; try Sample.create(at: root); try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true); let t = try Scanner.scan(root: root); #expect(!t.nodes.contains(".git")); #expect(t.warnings.contains { $0.contains("Excluded") }) }
@Test func cancelledScan() throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }; try Sample.create(at: root); #expect(throws: ScanError.cancelled) { try Scanner.scan(root: root, cancelled: { true }) } }

@Test func reverseIndexDecodesTargets() { let t = Tree(nodes: ["some guide.md"], links: [link("some%20guide.md"), link("../some%20guide.md", source: "nested/a.md"), link("https://example.invalid")]); #expect(t.reverseIndex["some guide.md"]?.count == 2); #expect(t.reverseIndex.count == 1) }
@Test func rawHTMLContainerUnchecked() { #expect(Markdown.parse("<div>Text</div>", source: "a.md").first?.unchecked == true) }
@Test func unchangedSourceAndTargetRemainClear() throws { let p = try Planner.plan(tree: fixture([link("images/diagram.png", source: "nested/readme.md")]), proposal: Proposal(source: "guide.md", destination: "archive/guide.md")); #expect(p.affected.isEmpty); #expect(p.preexisting.count == 1) }
@Test func checkedClearPlan() throws { let p = try Planner.plan(tree: fixture([link("../images/diagram.png", source: "nested/readme.md")]), proposal: Sample.proposal); #expect(p.state == "Clear") }
@Test func encodedEscapeRefused() { #expect(Target.resolve(link("%2E%2E/%2E%2E/g.md", source: "nested/readme.md")) == .escape) }
@Test func symlinkRootRefused() throws { let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: base) }; try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true); let target = base.appendingPathComponent("docs"); try Sample.create(at: target); let alias = base.appendingPathComponent("alias"); try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target); #expect(throws: ScanError.symlinkRoot) { try Scanner.scan(root: alias) } }
@Test func rootDirectoryTargetIsResolved() throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }; try Sample.create(at: root); let tree = try Scanner.scan(root: root); #expect(tree.nodes.contains("")); #expect(Target.resolve(link("..", source: "nested/readme.md")) == .local("", "")) }

@Test func excludedTargetIsUnchecked() throws { var t = fixture([link("vendor/doc.md")]); t.warnings = ["Excluded folder · vendor"]; t.unavailablePaths = ["vendor"]; let p = try Planner.plan(tree: t, proposal: Sample.proposal); #expect(p.preexisting.isEmpty); #expect(p.findings.first?.kind == .unchecked); #expect(p.incomplete) }
@Test func skippedSymlinkTargetIsUnchecked() throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }; try Sample.create(at: root); try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("nested")); try Data("[Doc](alias/readme.md)".utf8).write(to: root.appendingPathComponent("guide.md")); let p = try Planner.plan(tree: Scanner.scan(root: root), proposal: Sample.proposal); #expect(p.preexisting.isEmpty); #expect(p.findings.contains { $0.kind == .unchecked }) }
@Test func caseVariantConflictRefused() { #expect(throws: ProposalError.conflict) { try Proposal(source: "guide.md", destination: "nested/README.md").validated(in: fixture([])) } }
@Test func caseVariantTargetIsUnchecked() throws { let p = try Planner.plan(tree: fixture([link("images/DIAGRAM.png")]), proposal: Sample.proposal); #expect(p.preexisting.isEmpty); #expect(p.findings.first?.kind == .unchecked) }

@Test func crlfLineNumbers() { #expect(Markdown.parse("a\r\n[x](b.md)\r\n", source: "a.md").first?.line == 2) }
@Test func angleTargetNotHTML() { let links = Markdown.parse("[g](<my file.md>)", source: "a.md"); #expect(links.count == 1); #expect(links.first?.unchecked == false) }
@Test func angleReferenceNotHTML() { #expect(Markdown.parse("[g]: <my file.md>", source: "a.md").count == 1) }
@Test func actualHTMLWithAngleTargetUnchecked() { #expect(Markdown.parse("[g](<my file.md>) <br>", source: "a.md").contains { $0.unchecked }) }
@Test func rootRelativeTarget() { #expect(Target.resolve(link("/images/diagram.png", source: "nested/readme.md")) == .local("images/diagram.png", "")) }
@Test func rootRelativeMoveReplacement() throws { let p = try Planner.plan(tree: fixture([link("/guide.md", source: "nested/readme.md")]), proposal: Sample.proposal); #expect(p.affected.first?.replacement == "/archive/guide.md") }
@Test func incompleteIncludesCount() throws { let p = try Planner.plan(tree: fixture([link("images/diagram.png#demo")]), proposal: Sample.proposal); #expect(p.state == "1 affected · Incomplete") }
@Test func duplicateLinksHaveDistinctIDs() { let l = Markdown.parse("[A](b.md) [A](b.md)", source: "a.md"); #expect(l.count == 2); #expect(Set(l.map(\.id)).count == 2) }
@Test func emptyRelativeDirectoryUsesDotSlash() throws {
 let t = Tree(nodes: ["a.md", "docs"], directories: ["", "docs"], links: [link("docs", source: "a.md")])
 let p = try Planner.plan(tree: t, proposal: Proposal(source: "a.md", destination: "docs/b.md"))
 #expect(p.affected.first?.replacement == "./")
 for f in p.affected { #expect(Target.resolve(DocumentLink(source: f.sourceAfter, line: f.link.line, target: f.replacement!)) == .local("docs", "")) }
}
@Test func unchangedFragmentsKeepCoverageIncomplete() throws {
 let t = Tree(nodes: ["a.md", "b.md"], links: [link("a.md#missing", source: "b.md")])
 let p = try Planner.plan(tree: t, proposal: Proposal(source: "b.md", destination: "renamed.md"))
 #expect(p.incomplete); #expect(p.affected.isEmpty); #expect(p.findings.contains { $0.kind == .fragment })
}
@Test func untouchedSourceFragmentKeepsCoverageIncomplete() throws {
 let t = Tree(nodes: ["a.md", "b.md", "c.md"], links: [link("a.md#missing", source: "b.md")])
 #expect(try Planner.plan(tree: t, proposal: Proposal(source: "c.md", destination: "renamed.md")).incomplete)
}
@Test func newParentConflictsWithFile() { #expect(throws: ProposalError.conflict) { try Proposal(source: "guide.md", destination: "images/diagram.png/new.md").validated(in: fixture([])) } }
@Test func defaultShortcutDisabled() { #expect(SavedState().shortcutKey == UInt32.max) }
@Test func localizedCoverageAndErrors() {
 for k in CoverageKind.allCases { let text = CoverageKind.localized(k.rawValue + " · docs/a.md", spanish: true); #expect(!text.contains(k.rawValue)); #expect(text.contains("docs/a.md")) }
 for error in [ProposalError.invalid, .missing, .conflict, .parentMissing, .selfMove, .unchanged] { #expect(error.spanish != error.rawValue) }
 for error in [ScanError.permission, .symlinkRoot, .cancelled] { #expect(error.spanish != error.errorDescription) }
}
@Test func provisionalURLFallsBackLocally() { #expect(ProductLink.webURL("https://{DOMAIN}/apps/linksprig/privacy/") == nil); #expect(ProductLink.webURL("https://barframe.com/apps/linksprig/privacy/") != nil) }
@Test func mdxAndFingerprintWithoutParse() throws {
 let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
 try Sample.create(at: root); try Data("[g](guide.md)".utf8).write(to: root.appendingPathComponent("index.mdx"))
 let full = try Scanner.scan(root: root); let cheap = try Scanner.scan(root: root, parseDocuments: false)
 #expect(full.links.contains { $0.source == "index.mdx" }); #expect(cheap.links.isEmpty); #expect(full.fingerprint == cheap.fingerprint)
 #expect(throws: ScanError.cancelled) { try Scanner.scan(root: root, cancelled: { true }, parseDocuments: false) }
}

@Test func legacyDefaultShortcutMigratesToDisabled() throws {
 let legacy = SavedState(shortcutKey: 37)
 var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
 object.removeValue(forKey: "shortcutModifiers")
 let loaded = SavedState.load(try JSONSerialization.data(withJSONObject: object)).0
 #expect(loaded.shortcutKey == UInt32.max)
}
