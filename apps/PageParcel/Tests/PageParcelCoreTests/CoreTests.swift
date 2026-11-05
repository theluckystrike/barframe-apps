import Testing
import Foundation
@testable import PageParcelCore
@Test func empty() { #expect(Plan([]).complete == false) }
@Test func samplePages() { #expect(Plan(Fixtures.documents).pages.count == 6) }
@Test func sampleBlank() { #expect(Plan(Fixtures.documents).blanks == 1) }
@Test func appendixStart() { #expect(Plan(Fixtures.documents).pages[4].local == 1) }
@Test func oddFront() { #expect(Plan([Document(label:"A",count:1),Document(label:"B",count:1)]).blanks == 1) }
@Test func evenFront() { #expect(Plan([Document(label:"A",count:2),Document(label:"B",count:1)]).blanks == 0) }
@Test func firstFront() { #expect(Plan([Document(label:"A",count:1)]).pages[0].position == 1) }
@Test func noFront() { #expect(Plan([Document(label:"A",count:1),Document(label:"B",count:1,front:false)]).pages.count == 2) }
@Test func threeSingles() { #expect(Plan([Document(label:"A",count:1),Document(label:"B",count:1),Document(label:"C",count:1)]).pages.count == 5) }
@Test func locked() { #expect(!Plan([Document(label:"Locked",count:2,issue:"Locked")]).complete) }
@Test func unreadable() { #expect(!Plan([Document(label:"Bad",count:nil)]).complete) }
@Test func zero() { #expect(!Plan([Document(label:"Empty",count:0)]).complete) }
@Test func negative() { #expect(!Plan([Document(label:"Bad",count: -1)]).complete) }
@Test func mismatch() { #expect(Document(label:"A",count:3,expected:2).changed) }
@Test func match() { #expect(!Document(label:"A",count:3,expected:3).changed) }
@Test func unset() { #expect(!Document(label:"A",count:3).changed) }
@Test func sheet() { #expect(Plan(Fixtures.documents).pages[4].sheet == 3) }
@Test func back() { #expect(Plan(Fixtures.documents).pages[3].side == "Back") }
@Test func front() { #expect(Plan(Fixtures.documents).pages[4].side == "Front") }
@Test func blankSource() { #expect(Plan(Fixtures.documents).pages[3].document == nil) }
@Test func provenance() { #expect(Plan(Fixtures.documents).pages[5].local == 2) }
@Test func sampleReport() { #expect(Plan(Fixtures.documents).report(Fixtures.documents,sample:true).contains("Sample")) }
@Test func liveReport() { #expect(!Plan([]).report([],sample:false).contains("Sample")) }
@Test func downstreamBlocked() { #expect(Plan([Document(label:"A",count:nil),Document(label:"B",count:3)]).pages.isEmpty) }
@Test func reorder() { #expect(Plan(Array(Fixtures.documents.reversed())).blanks == 0) }
@Test func persistence() throws { let docs = Fixtures.documents; #expect(try PacketStore.decode(PacketStore.encode(docs)) == docs) }
@Test func corruptState() { #expect(throws: (any Error).self) { try PacketStore.decode(Data("broken".utf8)) } }
@Test func stableIDs() throws { let docs = Fixtures.documents; let restored = try PacketStore.decode(PacketStore.encode(docs)); #expect(Plan(restored).ranges == Plan(docs).ranges) }

@Test func stalePlanKeepsCompletedBaseline() {
 var docs = Fixtures.documents; var review = ReviewState(); review.observe(Plan(docs))
 docs[0].issue = "File changed · Rescan required"; review.observe(Plan(docs))
 docs[0].issue = nil; docs[0].count = 5; review.observe(Plan(docs))
 #expect(review.pending.contains { $0.id == docs[1].id && $0.before == 5...6 && $0.after == 7...8 })
}
@Test func pendingChangesSurviveRescanRestartAndMismatch() throws {
 var docs = Fixtures.documents; var review = ReviewState(); review.observe(Plan(docs))
 docs[0].count = 5; review.observe(Plan(docs)); review.observe(Plan(docs))
 #expect(docs[0].changed)
 let restored = try SavedPacket.decode(JSONEncoder().encode(SavedPacket(documents:docs,review:review,checked:Date())))
 #expect(restored.review == review); #expect(restored.review.pending.count == 2)
 var next = restored.review; next.observe(Plan(docs)); #expect(next.pending == review.pending)
 next.acknowledge(Plan(docs)); #expect(next.pending.isEmpty); #expect(next.baseline == Plan(docs).ranges)
}
@Test func partialPlanCannotAcknowledgeMovement() {
 var docs = Fixtures.documents; var review = ReviewState(); review.observe(Plan(docs)); docs[0].count = 5; review.observe(Plan(docs)); let pending = review.pending
 docs[0].issue = "Unavailable"; review.acknowledge(Plan(docs)); #expect(review.pending == pending)
}
@Test func legacyPacketMigrationRetainsBaseline() throws { let docs = Fixtures.documents; let packet = try SavedPacket.decode(PacketStore.encode(docs)); #expect(packet.review.baseline == Plan(docs).ranges) }
@Test func invalidExpectedCountsRejected() { #expect(!ExpectedCount.valid(0)); #expect(!ExpectedCount.valid(-1)); #expect(!ExpectedCount.valid(100001)); #expect(ExpectedCount.valid(12)) }
@Test func missingInputRequiresRecovery() { #expect(InputFreshness.issue(saved:nil,current:nil,available:false) == "File unavailable · Choose again") }
@Test func changedInputNeedsRescan() { #expect(InputFreshness.issue(saved:Date(timeIntervalSince1970:1),current:Date(timeIntervalSince1970:2),available:true) != nil) }
@Test func clearRemovesBothModes() throws {
 let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
 for name in ["live.json","sample.json","source.pdf"] { try Data("fixture".utf8).write(to:root.appendingPathComponent(name)) }
 try PacketFiles.clear(root); #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("live.json").path)); #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("sample.json").path)); #expect(FileManager.default.fileExists(atPath:root.appendingPathComponent("source.pdf").path))
}
@Test func damagedPacketSurvivesSubsequentSave() throws {
 let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
 let file = root.appendingPathComponent("live.json"); let raw = Data("broken".utf8); try raw.write(to:file); let backup = try PacketFiles.preserveCorrupt(file); try PacketStore.encode([]).write(to:file); #expect(try Data(contentsOf:backup) == raw)
}
@Test func staleBookmarkRefreshContinues() throws { let old = Data([1]), refreshed = Data([2]); #expect(BookmarkRefresh.data(original:old,stale:true) { refreshed } == refreshed); #expect(BookmarkRefresh.data(original:old,stale:false) { refreshed } == old) }
@Test func spanishReportTranslatesFunctionalStates() { let text = Plan(Fixtures.documents).report(Fixtures.documents,sample:true,spanish:true); #expect(text.contains("Anverso")); #expect(text.contains("Reverso")); #expect(text.contains("páginas originales")); #expect(!text.contains("Assumption")); #expect(text.contains("Sample")) }
@Test func spanishUnavailableAndCancelledStates() { #expect(IssueText.spanish("File unavailable · Choose again").contains("Archivo no disponible")); #expect(IssueText.spanish("Scan cancelled · Rescan required").contains("cancelado")) }
@Test func shortcutPolicyProtectsSystemKeys() { #expect(ShortcutPolicy.reserved(key:49,modifiers:256)); #expect(!ShortcutPolicy.reserved(key:35,modifiers:256|2048)); #expect(!ShortcutPolicy.reserved(key:17,modifiers:4096)) }
@Test func unfinishedDomainUsesLocalPolicy() { #expect(ProductLink.resolved("https://{DOMAIN}/apps/pageparcel/privacy/") == nil); #expect(ProductLink.resolved("https://barframe.com/apps/pageparcel/privacy/") != nil) }

@Test func separatelyChosenDownstreamDocumentGetsBaseline() {
 var docs = Fixtures.documents; var review = ReviewState(); review.observe(Plan([docs[0]])); review.observe(Plan(docs)); docs[0].count = 5; review.observe(Plan(docs))
 #expect(review.pending.contains { $0.id == docs[1].id && $0.before == 5...6 && $0.after == 7...8 })
}

@Test func spanishReportPreservesUserProvenanceVerbatim() {
 var doc = Document(label:"Packet Front page yes",count:1,expected:1); doc.filename = "packet-Front-page-yes.pdf"
 let report = Plan([doc]).report([doc],sample:false,spanish:true)
 #expect(report.contains(doc.label)); #expect(report.contains(doc.filename)); #expect(report.contains("páginas originales")); #expect(report.contains("Anverso"))
}

@Test func productLinkRequiresApprovedRoute() {
 #expect(ProductLink.resolved("https://barframe.com/apps/pageparcel/privacy/",path:"/apps/pageparcel/privacy/") != nil)
 #expect(ProductLink.resolved("https://barframe.com/apps/pageparcel/support/",path:"/apps/pageparcel/privacy/") == nil)
 #expect(ProductLink.resolved("https://{DOMAIN}/apps/pageparcel/privacy/",path:"/apps/pageparcel/privacy/") == nil)
}

@Test func missingPreviewCannotChangeSourcePageToBlank() {
 let plan = Plan(Fixtures.documents)
 #expect(!plan.pages[0].isBlank); #expect(plan.pages[3].isBlank); #expect(!plan.pages[4].isBlank)
}
