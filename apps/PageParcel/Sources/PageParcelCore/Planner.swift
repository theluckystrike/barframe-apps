import Foundation
public struct Document: Codable, Identifiable, Equatable {
 public var id: UUID
 public var label: String
 public var filename: String
 public var count: Int?
 public var expected: Int?
 public var front: Bool
 public var issue: String?
 public var bookmark: Data?
 public var modified: Date?
 public init(label: String, count: Int?, front: Bool = true, expected: Int? = nil, issue: String? = nil) {
 id = UUID(); self.label = label; filename = label + ".pdf"; self.count = count; self.front = front; self.expected = expected; self.issue = issue
 }
 public var changed: Bool { expected != nil && expected != count }
}
public struct Page: Identifiable, Equatable {
 public var id: Int { position }
 public let position: Int
 public let document: UUID?
 public let local: Int?
 public var isBlank: Bool { document == nil }
 public var sheet: Int { (position + 1) / 2 }
 public var side: String { position % 2 == 1 ? "Front" : "Back" }
}
public struct Plan {
 public var pages: [Page] = []
 public var unresolved: [String] = []
 public var ranges: [UUID: ClosedRange<Int>] = [:]
 public var complete: Bool { unresolved.isEmpty && !pages.isEmpty }
 public var blanks: Int { pages.filter { $0.document == nil }.count }
 public init(_ documents: [Document]) {
 var blocked = false
 for doc in documents {
 guard !blocked, let count = doc.count, count > 0, count <= 100000, doc.issue == nil else {
 unresolved.append(doc.label + " · " + (doc.issue ?? (blocked ? "Position unavailable after unresolved file" : "No readable pages"))); blocked = true; continue
 }
 if doc.front && pages.count % 2 == 1 { pages.append(Page(position: pages.count + 1, document: nil, local: nil)) }
 let start = pages.count + 1
 for local in 1...count { pages.append(Page(position: pages.count + 1, document: doc.id, local: local)) }
 ranges[doc.id] = start...pages.count
 }
 }
 public func report(_ docs:[Document],sample:Bool,spanish:Bool = false)->String {
 func t(_ en:String,_ es:String)->String { spanish ? es : en }
 var lines = [sample ? t("PageParcel Sample assembly sheet","PageParcel Sample hoja de montaje") : t("PageParcel assembly sheet","PageParcel hoja de montaje"), t("Assumption · duplex with odd pages on the front","Supuesto · dúplex con páginas impares en el anverso"), t("Virtual blanks only · source PDFs unchanged · nothing printed","Blancos virtuales · PDF originales sin cambios · nada impreso"), complete ? t("Complete plan","Plan completo") : t("Incomplete plan","Plan incompleto")]
 for (i,d) in docs.enumerated() {
 let count = d.count.map(String.init) ?? t("unknown","desconocido")
 let expected = d.expected.map(String.init) ?? t("unset","sin definir")
 let range = ranges[d.id].map { "\($0.lowerBound) \(t("to","a")) \($0.upperBound)" } ?? t("unresolved","sin resolver")
 lines.append("\(i+1). \(d.label) · \(d.filename) · \(t("source pages","páginas originales")) \(count) · \(t("expected","esperadas")) \(expected) · \(t("front start","inicio en anverso")) \(d.front ? t("yes","sí") : "no") · \(t("packet","paquete")) \(range)")
 }
 for p in pages {
 let name = docs.first { $0.id == p.document }?.label
 let source = name.map { "\($0) \(t("page","página")) \(p.local ?? 0)" } ?? t("Planned blank","Blanco previsto")
 lines.append("\(t("Packet","Paquete")) \(p.position) · \(t("sheet","hoja")) \(p.sheet) \(t(p.side,p.side == "Front" ? "Anverso" : "Reverso")) · \(source)")
 }
 var blocked = false
 for d in docs where ranges[d.id] == nil {
 let reason = d.issue ?? (blocked ? "Position unavailable after unresolved file" : "No readable pages")
 lines.append(d.label + " · " + (spanish ? IssueText.spanish(reason) : reason)); blocked = true
 }
 return lines.joined(separator:"\n")
 }

}
public enum Fixtures {
 public static var documents: [Document] { [Document(label: "Introduction", count: 3, expected: 3), Document(label: "Appendix", count: 2, expected: 2)] }
}
public enum PacketStore {
 public static func encode(_ docs: [Document]) throws -> Data { try JSONEncoder().encode(docs) }
 public static func decode(_ data: Data) throws -> [Document] { try JSONDecoder().decode([Document].self, from: data) }
}

public struct Movement: Codable, Equatable, Identifiable {
 public var id: UUID
 public var before: ClosedRange<Int>
 public var after: ClosedRange<Int>
}
public struct ReviewState: Codable, Equatable {
 public var baseline: [UUID: ClosedRange<Int>] = [:]
 public var pending: [Movement] = []
 public init() {}
 public mutating func observe(_ plan: Plan) {
 // Partial plans never replace the last complete comparison baseline.
 guard plan.complete else { return }
 if baseline.isEmpty { baseline = plan.ranges; return }
 for (id, after) in plan.ranges {
 guard let before = baseline[id] else { baseline[id] = after; continue }
 guard before != after else { continue }
 let finding = Movement(id:id,before:before,after:after)
 if let i = pending.firstIndex(where: {$0.id == id}) { pending[i] = finding } else { pending.append(finding) }
 }
 }
 public mutating func acknowledge(_ plan: Plan) { guard plan.complete else { return }; baseline = plan.ranges; pending = [] }
 public mutating func remove(_ id: UUID) { baseline.removeValue(forKey:id); pending.removeAll { $0.id == id } }
}
public struct SavedPacket: Codable {
 public var documents: [Document]
 public var review: ReviewState
 public var checked: Date?
 public init(documents: [Document], review: ReviewState, checked: Date?) { self.documents = documents; self.review = review; self.checked = checked }
 public static func decode(_ data: Data) throws -> SavedPacket {
 if let modern = try? JSONDecoder().decode(SavedPacket.self,from:data) { return modern }
 let docs = try PacketStore.decode(data)
 var review = ReviewState(); review.observe(Plan(docs))
 return SavedPacket(documents:docs,review:review,checked:nil)
 }
}
public enum ExpectedCount {
 public static func valid(_ value: Int) -> Bool { (1...100000).contains(value) }
}
public enum PacketFiles {
 public static func clear(_ root: URL) throws {
 let backups = (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
 for url in backups where (url.lastPathComponent.hasPrefix("live.corrupt.") || url.lastPathComponent.hasPrefix("sample.corrupt.")) && url.pathExtension == "json" { try FileManager.default.removeItem(at:url) }
 for name in ["live.json", "sample.json"] {
 let file = root.appendingPathComponent(name)
 if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
 }
 }
 public static func preserveCorrupt(_ file: URL) throws -> URL {
 let backup = file.deletingPathExtension().appendingPathExtension("corrupt." + UUID().uuidString + ".json")
 try FileManager.default.moveItem(at:file,to:backup); return backup
 }
}
public enum InputFreshness {
 public static func issue(saved: Date?, current: Date?, available: Bool) -> String? {
 if !available { return "File unavailable · Choose again" }
 return saved != current ? "File changed · Rescan required" : nil
 }
}
public enum ShortcutPolicy {
 public static func reserved(key: UInt32, modifiers: UInt32) -> Bool {
 // Command-space, Command-tab, Command-Q and Command-comma belong to macOS or this app.
 modifiers & 256 != 0 && [49,48,12,43].contains(key)
 }
}
public enum ProductLink {
 public static func resolved(_ value: String?, path: String? = nil) -> URL? {
 guard let value, value.hasPrefix("https://"), !value.contains("{"), !value.contains("}") else { return nil }
 guard let url = URL(string:value), path == nil || URLComponents(url:url,resolvingAgainstBaseURL:false)?.path == path else { return nil }
 return url
 }
}

public enum IssueText {
 public static func spanish(_ text:String) -> String {
 let translations = ["Local packets and settings cleared. Source PDFs kept.":"Paquetes y ajustes locales borrados. Se conservan los PDF.", "Assembly sheet copied":"Hoja de montaje copiada", "Shortcut registration failed. Choose another combination.":"No se pudo registrar el atajo. Elige otra combinación.", "Reserved system shortcut. Choose another combination.":"Atajo reservado del sistema. Elige otra combinación.", "Could not save packet":"No se pudo guardar el paquete", "Permission unavailable":"Permiso no disponible", "Could not clear local packets":"No se pudieron borrar los paquetes locales", "Selection cancelled. Existing packet kept.":"Selección cancelada. Se conserva el paquete.", "Check cancelled. Rescan before using the plan.":"Análisis cancelado. Analiza antes de usar el plan.", "Damaged packet preserved in a separate recovery file. Choose inputs again.":"Paquete dañado conservado en un archivo de recuperación. Elige de nuevo.", "Could not preserve damaged packet":"No se pudo conservar el paquete dañado", "Choose again to grant access":"Elige de nuevo para permitir acceso", "Permission denied · Choose again":"Permiso denegado · Elige de nuevo", "Unreadable PDF · Choose again":"PDF ilegible · Elige de nuevo", "Password locked PDF":"PDF protegido por contraseña", "Empty PDF":"PDF vacío", "Access unavailable · Choose again":"Acceso no disponible · Elige de nuevo", "File changed · Rescan required":"Archivo modificado · Es necesario analizar", "File unavailable · Choose again":"Archivo no disponible · Elige de nuevo", "Scan cancelled · Rescan required":"Análisis cancelado · Es necesario analizar", "Position unavailable after unresolved file":"Posición no disponible tras archivo sin resolver", "No readable pages":"Sin páginas legibles"]
 return translations.reduce(text) { $0.replacingOccurrences(of:$1.key,with:$1.value) }
 }
}

public enum BookmarkRefresh {
 public static func data(original:Data,stale:Bool,refresh:() throws -> Data) rethrows -> Data { stale ? try refresh() : original }
}
