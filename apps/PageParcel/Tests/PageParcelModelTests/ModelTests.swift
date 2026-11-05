import Testing
import Foundation
import PDFKit
import PageParcelCore
@testable import PageParcel
@Suite(.serialized) @MainActor struct ModelRegressionTests {
 @Test func labelEditsReuseCachedPlan() { let m = Model(loadFromDisk:false); m.documents = Fixtures.documents; let builds = m.planBuildCount; m.documents[0].label = "Updated"; #expect(m.planBuildCount == builds); #expect(m.plan.pages.count == 6) }
 @Test func expectationReplacementValidatesCount() { let m = Model(loadFromDisk:false); m.documents = Fixtures.documents; let id = m.documents[0].id; m.acceptExpected(id,0); #expect(m.documents[0].expected == 3); m.acceptExpected(id,5); #expect(m.documents[0].expected == 5); m.saveTask?.cancel() }
 @Test func removalReleasesCachedInput() { let m = Model(loadFromDisk:false); m.documents = Fixtures.documents; let id = m.documents[0].id; m.urls[id] = URL(fileURLWithPath:"/not/a/grant.pdf"); m.pdfs[id] = PDFDocument(); m.remove(id); #expect(m.urls[id] == nil); #expect(m.pdfs[id] == nil); #expect(!m.documents.contains { $0.id == id }); m.saveTask?.cancel() }
 @Test func deletionMarksIncomplete() { let m = Model(loadFromDisk:false); m.documents = Fixtures.documents; m.urls[m.documents[0].id] = URL(fileURLWithPath:"/file/does/not/exist.pdf"); m.checkStale(); #expect(m.state == "Incomplete"); #expect(m.mostImportant.contains("File unavailable")) }
 @Test func cancellationNeverShowsReady() { let m = Model(loadFromDisk:false); m.documents = Fixtures.documents; m.cancelScan(); #expect(!m.busy); #expect(m.state == "Incomplete"); m.saveTask?.cancel() }
 @Test func savesCoalesceAndPersistPendingReview() throws {
 let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:root) }
 let m = Model(loadFromDisk:false,rootOverride:root); m.documents = Fixtures.documents; m.review.observe(m.plan); m.documents[0].count = 5; m.review.observe(m.plan); m.save(); m.save(); m.flushSave()
 let restored = try SavedPacket.decode(Data(contentsOf:root.appendingPathComponent("live.json"))); #expect(restored.review.pending == m.review.pending)
 }
 @Test func summaryUsesFindingAndLanguage() { let m = Model(loadFromDisk:false); m.documents = Fixtures.documents; m.documents[0].issue = "Password locked PDF"; m.spanish = true; #expect(m.mostImportant.contains("contraseña")); #expect(m.displayState == "Incompleto"); UserDefaults.standard.removeObject(forKey:"spanish") }
 @Test func scanPublishesBusyAndProgressWithoutBlockingUI() async {
 let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:root) }
 let m = Model(loadFromDisk:false,rootOverride:root); m.documents = Fixtures.documents; m.rescan(); #expect(m.busy); #expect(m.state == "Checking")
 await m.scanTask?.value
 #expect(!m.busy); #expect(m.progress == 2); #expect(m.state == "Incomplete"); m.saveTask?.cancel()
 }
 @Test func sampleNeedsNoExternalGrant() throws {
 let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:root) }
 let m = Model(loadFromDisk:false,rootOverride:root); m.sample = true; m.resetSample(); #expect(m.urls.isEmpty); #expect(m.plan.complete); #expect(m.pdfs.count == 2)
 }

 @Test func freshnessDiscardsURLMetadataCache() throws {
 let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
 let url = root.appendingPathComponent("source.pdf"); try Data("fixture".utf8).write(to:url)
 let date = try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate!
 let m = Model(loadFromDisk:false,rootOverride:root); m.documents = Fixtures.documents; m.documents[0].modified = date; m.urls[m.documents[0].id] = url
 try FileManager.default.setAttributes([.modificationDate:date.addingTimeInterval(2)],ofItemAtPath:url.path)
 m.checkStale(); #expect(m.documents[0].issue == "File changed · Rescan required"); #expect(m.state == "Incomplete")
 }

}
