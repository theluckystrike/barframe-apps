import SwiftUI
import PDFKit
import PageParcelCore
import Carbon

@MainActor final class Model: ObservableObject {
 @Published var documents: [Document] = [] { didSet {
 let relevant: (Document) -> String = { "\($0.id)|\($0.count ?? -1)|\($0.front)|\($0.issue ?? "")" }
 if !applyingScan && documents.map(relevant) != oldValue.map(relevant) { plan = Plan(documents); planBuildCount += 1 }
 } }
 var planBuildCount = 0
 var applyingScan = false
 @Published private(set) var plan = Plan([])
 @Published var sample = false
 var snapshot = false
 @Published var message = ""
 @Published var review = ReviewState()
 var changes: [String] { review.pending.map { finding in
 let label = documents.first { $0.id == finding.id }?.label ?? t("Document","Documento")
 return "\(label) · \(finding.before.lowerBound) \(t("to","a")) \(finding.before.upperBound) → \(finding.after.lowerBound) \(t("to","a")) \(finding.after.upperBound)"
 } }
 @Published var lastCheck: Date?
 @Published var busy = false
 @Published var progress = 0
 @Published var selected: Int? = 1
 @Published var defaultFront = true { didSet { UserDefaults.standard.set(defaultFront,forKey:"front") } }
 @Published var appearance = "System" { didSet { UserDefaults.standard.set(appearance,forKey:"appearance") } }
 @Published var spanish = false { didSet { UserDefaults.standard.set(spanish,forKey:"spanish") } }
 @Published var shortcutKey: UInt32 = UInt32(kVK_ANSI_P)
 @Published var shortcutModifiers: UInt32 = UInt32(cmdKey | optionKey)
 @Published var shortcutName = "⌘⌥P"
 @Published var shortcutMessage = ""
 var hotKey: EventHotKeyRef?
 var urls: [UUID:URL] = [:]
 var pdfs: [UUID:PDFDocument] = [:]
 var saveTask: Task<Void,Never>?
 var scanTask: Task<Void,Never>?
 var scanGeneration = UUID()
 var state: String { busy ? "Checking" : documents.isEmpty ? "No inputs" : !plan.complete ? "Incomplete" : documents.contains(where: {$0.changed}) || !changes.isEmpty ? "Changed" : "Ready" }
 var displayState: String { t(state,["Checking":"Analizando","No inputs":"Sin archivos","Incomplete":"Incompleto","Changed":"Modificado","Ready":"Listo"][state] ?? state) }
 var mostImportant: String {
 if busy { return t("Checking document \(progress) of \(documents.count)","Analizando documento \(progress) de \(documents.count)") }
 if let d = documents.first(where: {$0.issue != nil}) { return d.label + " · " + translatedIssue(d.issue!) }
 if let first = plan.unresolved.first { return translatedIssue(first) }
 if let d = documents.first(where: {$0.changed}) { return d.label + " · " + t("Count differs from expectation","El recuento difiere del esperado") }
 return changes.first ?? t("All planned positions resolved","Todas las posiciones resueltas")
 }
 func translatedIssue(_ issue:String) -> String { spanish ? IssueText.spanish(issue) : issue }
 var rootOverride:URL?
 var root:URL { if let rootOverride { return rootOverride }; return URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/PageParcel") }
 var file:URL { root.appendingPathComponent(sample ? "sample.json" : "live.json") }
 init(loadFromDisk:Bool = true, rootOverride:URL? = nil) {
 self.rootOverride = rootOverride
 defaultFront = UserDefaults.standard.object(forKey:"front") as? Bool ?? true
 appearance = UserDefaults.standard.string(forKey:"appearance") ?? "System"
 spanish = UserDefaults.standard.bool(forKey:"spanish")
 if let key = UserDefaults.standard.object(forKey:"shortcutKey") as? Int { shortcutKey = UInt32(key) }
 if let mods = UserDefaults.standard.object(forKey:"shortcutModifiers") as? Int { shortcutModifiers = UInt32(mods) }
 shortcutName = UserDefaults.standard.string(forKey:"shortcutName") ?? "⌘⌥P"
 if loadFromDisk { load(); registerShortcut() }
 }
 func t(_ en:String,_ es:String)->String { spanish ? es : en }
 func save() {
 saveTask?.cancel()
 saveTask = Task { try? await Task.sleep(nanoseconds:400_000_000); guard !Task.isCancelled else { return }; flushSave() }
 }
 func flushSave() {
 saveTask?.cancel(); saveTask = nil
 if documents.isEmpty { try? FileManager.default.removeItem(at:file); return }
 do {
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 try JSONEncoder().encode(SavedPacket(documents:documents,review:review,checked:lastCheck)).write(to:file,options:.atomic)
 } catch { message = t("Could not save packet","No se pudo guardar el paquete") + " · " + error.localizedDescription }
 }
 func release() { for url in urls.values { url.stopAccessingSecurityScopedResource() }; urls = [:]; pdfs = [:] }
 func cancelScan() { scanTask?.cancel(); scanTask = nil; scanGeneration = UUID(); busy = false; message = t("Check cancelled. Rescan before using the plan.","Análisis cancelado. Analiza antes de usar el plan."); for i in documents.indices { documents[i].issue = "Scan cancelled · Rescan required" }; save() }
 func load() {
 scanTask?.cancel(); scanGeneration = UUID(); busy = false; release(); review = ReviewState(); lastCheck = nil
 guard FileManager.default.fileExists(atPath:file.path) else { documents = []; return }
 do {
 let saved = try SavedPacket.decode(Data(contentsOf:file)); documents = saved.documents; review = saved.review; lastCheck = saved.checked
 if sample { makeSamplePDFs() } else { rescan() }
 } catch {
 do { _ = try PacketFiles.preserveCorrupt(file); message = t("Damaged packet preserved in a separate recovery file. Choose inputs again.","Paquete dañado conservado en un archivo de recuperación. Elige de nuevo.") }
 catch { message = t("Could not preserve damaged packet","No se pudo conservar el paquete dañado"); return }
 documents = []
 }
 }
 func toggleSample(_ enabled:Bool) { flushSave(); sample = enabled; message = ""; load(); if enabled && documents.isEmpty { resetSample() } }
 func resetSample() { scanTask?.cancel(); scanGeneration = UUID(); busy = false; release(); documents = Fixtures.documents; makeSamplePDFs(); review = ReviewState(); review.observe(plan); lastCheck = Date(); flushSave() }
 func makeSamplePDFs() {
 for d in documents {
 let pdf = PDFDocument()
 for n in 1...(d.count ?? 1) {
 let image = NSImage(size: NSSize(width: 612, height: 792)); image.lockFocus(); NSColor.white.setFill(); NSRect(x: 0,y: 0,width: 612,height: 792).fill()
 ("Sample\n\(d.label)\nPage \(n)" as NSString).draw(in: NSRect(x: 55,y: 530,width: 500,height: 190),withAttributes: [.font: NSFont.systemFont(ofSize: 32),.foregroundColor: NSColor.black]); image.unlockFocus()
 if let page = PDFPage(image: image) { pdf.insert(page, at: pdf.pageCount) }
 }
 pdfs[d.id] = pdf
 }
 }
 func choose(replacing id: UUID? = nil) { DispatchQueue.main.async { self.performChoose(replacing: id) } }
 func performChoose(replacing id: UUID?) {
 NSApp.activate(ignoringOtherApps:true)
 let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = id == nil
 panel.message = t("Choose PDFs to read page counts and preview pages. Source files stay unchanged.","Elige PDF para contar y previsualizar páginas. Los originales no cambian.")
 guard panel.runModal() == .OK else { message = t("Selection cancelled. Existing packet kept.","Selección cancelada. Se conserva el paquete."); return }
 if sample { toggleSample(false) }
 for url in panel.urls {
 let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
 do {
 let bookmark = try url.bookmarkData(options: [.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys: nil,relativeTo: nil)
 if let id, let i = documents.firstIndex(where: { $0.id == id }) { documents[i].bookmark = bookmark; documents[i].filename = url.lastPathComponent }
 else { var d = Document(label: url.deletingPathExtension().lastPathComponent,count: nil,front: defaultFront); d.filename = url.lastPathComponent; d.bookmark = bookmark; documents.append(d) }
 } catch { message = t("Permission unavailable","Permiso no disponible") + " · " + error.localizedDescription }
 }
 rescan()
 }

 func rescan() {
 guard !sample else { lastCheck = Date(); review.observe(plan); save(); return }
 scanTask?.cancel(); let generation = UUID(); scanGeneration = generation
 let input = documents; busy = true; progress = 0; message = ""
 release()
 scanTask = Task {
 let worker = Task.detached(priority:.userInitiated) { await PDFScanner.scan(input) { number in
 await MainActor.run { if self.scanGeneration == generation { self.progress = number } }
 } }
 let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
 guard !Task.isCancelled, self.scanGeneration == generation else { result.release(); return }
 self.applyingScan = true; self.documents = result.documents; self.applyingScan = false; self.plan = result.plan; self.urls = result.urls; self.pdfs = result.pdfs
 self.review.observe(result.plan); self.busy = false; self.lastCheck = Date(); self.flushSave()
 }
 }
 func checkStale() {
 guard !sample, !busy else { return }
 for i in documents.indices {
 guard let url = urls[documents[i].id] else { continue }
 do {
 var freshURL = url; freshURL.removeAllCachedResourceValues()
 let current = try freshURL.resourceValues(forKeys:[.contentModificationDateKey,.isRegularFileKey])
 if let issue = InputFreshness.issue(saved:documents[i].modified,current:current.contentModificationDate,available:current.isRegularFile == true) { documents[i].issue = issue }
 } catch { documents[i].issue = "File unavailable · Choose again" }
 }
 }
 func move(_ id:UUID,_ delta:Int) { guard !busy, let i = documents.firstIndex(where:{$0.id == id}), documents.indices.contains(i+delta) else { return }; documents.swapAt(i,i+delta); review.observe(plan); save() }
 func remove(_ id:UUID) {
 if busy { cancelScan() }
 urls.removeValue(forKey:id)?.stopAccessingSecurityScopedResource(); pdfs.removeValue(forKey:id)
 documents.removeAll { $0.id == id }; review.remove(id); review.observe(plan); save()
 }
 func acceptExpected(_ id:UUID,_ value:Int) {
 guard ExpectedCount.valid(value), let i = documents.firstIndex(where:{$0.id == id}) else { return }
 documents[i].expected = value; save()
 }
 func acknowledgeChanges() { review.acknowledge(plan); save() }
 func clear() {
 scanTask?.cancel(); scanGeneration = UUID(); busy = false; saveTask?.cancel(); saveTask = nil; release()
 documents = []; review = ReviewState(); lastCheck = nil
 defaultFront = true; appearance = "System"; spanish = false; shortcutKey = UInt32(kVK_ANSI_P); shortcutModifiers = UInt32(cmdKey | optionKey); shortcutName = "⌘⌥P"; registerShortcut()
 do { try PacketFiles.clear(root)
 for key in ["front","appearance","spanish","shortcut","shortcutKey","shortcutModifiers","shortcutName"] { UserDefaults.standard.removeObject(forKey:key) }
 message = "Local packets and settings cleared. Source PDFs kept."
 } catch { message = t("Could not clear local packets","No se pudieron borrar los paquetes locales") + " · " + error.localizedDescription }
 }
 func copy() {
 var reportDocs = documents
 if spanish { for i in reportDocs.indices { if let issue = reportDocs[i].issue { reportDocs[i].issue = translatedIssue(issue) } } }
 let text = plan.report(reportDocs,sample:sample,spanish:spanish) + (changes.isEmpty ? "" : "\n" + t("Pending position changes","Cambios de posición pendientes") + "\n" + changes.joined(separator:"\n"))
 NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string); message = t("Assembly sheet copied","Hoja de montaje copiada")
 }
 func setShortcut(key:UInt32,modifiers:UInt32,name:String) {
 guard !ShortcutPolicy.reserved(key:key,modifiers:modifiers), modifiers != 0 else { shortcutMessage = t("Reserved system shortcut. Choose another combination.","Atajo reservado del sistema. Elige otra combinación."); return }
 shortcutKey = key; shortcutModifiers = modifiers; shortcutName = name; registerShortcut()
 UserDefaults.standard.set(Int(key),forKey:"shortcutKey"); UserDefaults.standard.set(Int(modifiers),forKey:"shortcutModifiers"); UserDefaults.standard.set(name,forKey:"shortcutName")
 }
 func registerShortcut() {
 if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil
 let status = RegisterEventHotKey(shortcutKey,shortcutModifiers,EventHotKeyID(signature:0x50414745,id:1),GetApplicationEventTarget(),0,&hotKey)
 shortcutMessage = status == noErr ? "" : t("Shortcut registration failed. Choose another combination.","No se pudo registrar el atajo. Elige otra combinación.")
 }
}
final class ScanResult: @unchecked Sendable {
 var documents:[Document]; var urls:[UUID:URL] = [:]; var pdfs:[UUID:PDFDocument] = [:]; var plan:Plan
 init(_ docs:[Document]) { documents = docs; plan = Plan([]) }
 func release() { for url in urls.values { url.stopAccessingSecurityScopedResource() } }
}
enum PDFScanner {
 static func scan(_ input:[Document], progress:@Sendable (Int) async -> Void) async -> ScanResult {
 let result = ScanResult(input)
 for i in result.documents.indices {
 if Task.isCancelled { break }
 await progress(i+1)
 result.documents[i].issue = nil
 guard let bookmark = result.documents[i].bookmark else { result.documents[i].issue = "Choose again to grant access"; continue }
 do {
 var stale = false
 let url = try URL(resolvingBookmarkData:bookmark,options:[.withSecurityScope],relativeTo:nil,bookmarkDataIsStale:&stale)
 guard url.startAccessingSecurityScopedResource() else { result.documents[i].issue = "Permission denied · Choose again"; continue }
 result.urls[result.documents[i].id] = url
 result.documents[i].bookmark = try BookmarkRefresh.data(original:bookmark,stale:stale) { try url.bookmarkData(options:[.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys:nil,relativeTo:nil) }
 guard let pdf = PDFDocument(url:url) else { result.documents[i].issue = "Unreadable PDF · Choose again"; continue }
 guard !pdf.isLocked else { result.documents[i].issue = "Password locked PDF"; continue }
 guard pdf.pageCount > 0 else { result.documents[i].issue = "Empty PDF"; continue }
 result.documents[i].count = pdf.pageCount
 if result.documents[i].expected == nil { result.documents[i].expected = pdf.pageCount }
 result.documents[i].modified = try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
 result.pdfs[result.documents[i].id] = pdf
 } catch { result.documents[i].issue = "Access unavailable · Choose again" }
 }
 result.plan = Plan(result.documents); return result
 }
}
