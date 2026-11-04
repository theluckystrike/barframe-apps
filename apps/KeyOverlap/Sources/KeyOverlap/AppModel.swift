import SwiftUI
import AppKit
import Carbon
import KeyOverlapCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var live = ShortcutPlan()
    @Published private(set) var sample = ShortcutPlan.sample()
    @Published private(set) var sampleMode = false
    @Published var message: String?
    @Published var storageError: String?
    @Published var shortcutError: String?
    @Published var tab = 0
    @Published var language: String { didSet { UserDefaults.standard.set(language, forKey: "language") } }
    @Published var showPossible: Bool { didSet { UserDefaults.standard.set(showPossible, forKey: "showPossible") } }
    @Published var defaultScope: String { didSet { UserDefaults.standard.set(defaultScope, forKey: "defaultScope") } }
    @Published var opener: String { didSet { UserDefaults.standard.set(opener, forKey: "opener") } }
    @Published var candidateChord = "command+shift+5"
    @Published var candidateScope = "Orbit Editor"
    @Published var candidateContext = ""
    let hotkey = PlannerHotkey()
    let file: URL
    init(screenshot: Bool = false) {
        let defaults = UserDefaults.standard
        language = screenshot ? "en" : (defaults.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("es") == true ? "es" : "en"))
        showPossible = screenshot || defaults.object(forKey: "showPossible") == nil ? true : defaults.bool(forKey: "showPossible")
        defaultScope = defaults.string(forKey: "defaultScope") ?? ""
        opener = defaults.string(forKey: "opener") ?? "command+option+k"
        file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/KeyOverlap/plan.json")
        reload()
    }
    func l(_ english: String, _ spanish: String) -> String { language == "es" ? spanish : english }
    func errorText(_ error: Error) -> String { PlanText.error(error, language: language) }
    var plan: ShortcutPlan { sampleMode ? sample : live }
    var pairs: [Overlap] { OverlapEngine.overlaps(plan.records, contexts: plan.contexts) }
    var afterPairs: [Overlap] { OverlapEngine.overlaps(plan.proposedRecords, contexts: plan.contexts) }
    var definiteCount: Int { pairs.filter { $0.kind == .definite }.count }
    var possibleCount: Int { pairs.filter { $0.kind == .possible }.count }
    var statusSymbol: String {
        if plan.records.isEmpty { return "keyboard" }
        if definiteCount > 0 { return "exclamationmark.triangle" }
        if possibleCount > 0 { return "questionmark.circle" }
        return "checkmark.circle"
    }
    var menuLabel: String {
        let prefix = sampleMode ? l("Sample · ", "Ejemplo · ") : ""
        if plan.records.isEmpty { return prefix + l("Empty plan", "Plan vacío") }
        if definiteCount > 0 { return prefix + l("Plan overlaps", "Cruces en el plan") + " \(definiteCount)" }
        if possibleCount > 0 { return prefix + l("Possible plan overlaps", "Posibles cruces en el plan") + " \(possibleCount)" }
        return prefix + l("No overlaps in this plan", "Sin cruces en este plan")
    }
    func toggleSample(_ enabled: Bool) { sampleMode = enabled; message = nil }
    func resetSample() { sample = .sample(); message = l("Sample fixtures restored.", "Ejemplos restaurados.") }
    func update(_ newPlan: ShortcutPlan) {
        if sampleMode { sample = newPlan; return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(newPlan).write(to: file, options: .atomic)
            live = newPlan; storageError = nil
        } catch { storageError = l("Could not save the plan. ", "No se pudo guardar el plan. ") + errorText(error) }
    }
    func reload() {
        guard FileManager.default.fileExists(atPath: file.path) else { live = .init(); storageError = nil; return }
        do { live = try JSONDecoder().decode(ShortcutPlan.self, from: Data(contentsOf: file)).validated(); storageError = nil }
        catch { storageError = l("Could not read the saved plan. Retry or clear local plans in Settings. ", "No se pudo leer el plan guardado. Reintenta o borra los planes en Ajustes. ") + errorText(error) }
    }
    func clear() {
        if sampleMode { sample = .init(); message = l("Sample plan cleared. Restore Sample in Settings.", "Plan de ejemplo borrado. Restaura el ejemplo en Ajustes."); return }
        do { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }; live = .init(); storageError = nil; message = l("Local plan cleared.", "Plan local borrado.") }
        catch { storageError = errorText(error) }
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); message = l("Copied to clipboard.", "Copiado al portapapeles.") }
    func save(_ row: ShortcutRecord) {
        var next = plan
        if let index = next.records.firstIndex(where: { $0.id == row.id }) { next.records[index] = row; next.replacements.removeAll { $0.recordID == row.id } }
        else { next.records.append(row) }
        update(next)
    }
    func remove(_ id: UUID) { var next = plan; next.remove(id: id); update(next) }
    func stage(_ id: UUID, _ chord: Chord) throws { var next = plan; try next.stage(id: id, chord: chord); update(next); tab = 2 }
    func apply() { var next = plan; next.apply(); update(next); message = l("Applied to local records. Set the changes manually in your target apps.", "Aplicado a registros locales. Configura los cambios manualmente en tus apps.") }
    func unstage(_ id: UUID) { var next = plan; next.replacements.removeAll { $0.recordID == id }; update(next) }
    func addContext(_ value: ExclusiveContexts) { var next = plan; if !next.contexts.contains(where: { $0.app.lowercased() == value.app.lowercased() && Set([$0.first.lowercased(),$0.second.lowercased()]) == Set([value.first.lowercased(),value.second.lowercased()]) }) { next.contexts.append(value) }; update(next) }
    func removeContext(_ id: UUID) { var next = plan; next.contexts.removeAll { $0.id == id }; update(next) }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = l("Only this selected JSON file is read. No ongoing file access is kept.", "Solo se lee este archivo JSON. No se conserva acceso al archivo.")
        guard panel.runModal() == .OK, let url = panel.url else { message = l("Import canceled. Your plan is unchanged.", "Importación cancelada. El plan no ha cambiado."); return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let next = try PlanImport.importing(Data(contentsOf: url), into: plan)
            update(next)
            if sampleMode || storageError == nil { message = l("Imported \(next.records.count) records. Previous staged changes cleared.", "Se importaron \(next.records.count) registros. Se borraron los cambios propuestos anteriores.") }
        } catch { message = l("Import failed. Your plan is unchanged. ", "La importación falló. El plan no ha cambiado. ") + errorText(error) }
    }
    var candidate: Result<[Overlap], Error> {
        Result {
            let chord = try Chord.parse(candidateChord)
            let row = try ShortcutRecord(command: PlanText.translate("Candidate", language: language), key: chord.key, modifiers: chord.modifiers, scope: candidateScope, context: candidateContext)
            return OverlapEngine.candidate(row, in: plan.records, contexts: plan.contexts)
        }
    }
    func registerShortcut() {
        hotkey.unregister()
        do { try hotkey.register(Chord.parse(opener)); shortcutError = nil }
        catch { shortcutError = l("Planner shortcut unavailable. Use the menu bar button. ", "Atajo del plan no disponible. Usa el botón de la barra de menús. ") + errorText(error) }
    }
}

@MainActor
final class PlannerHotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    static let keycodes: [String: UInt32] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"return":36,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"tab":48,"space":49,"`":50,"delete":51,"escape":53,"f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,"f9":101,"f10":109,"f11":103,"f12":111,"f13":105,"f14":107,"f15":113,"f16":106,"f17":64,"f18":79,"f19":80,"f20":90,"home":115,"end":119,"pageup":116,"pagedown":121,"forwarddelete":117,"left":123,"right":124,"down":125,"up":126]
    func unregister() { if let ref { UnregisterEventHotKey(ref); self.ref = nil } }
    func register(_ chord: Chord) throws {
        guard let code = Self.keycodes[chord.key], !chord.modifiers.isEmpty else { throw PlanError.invalid("Use a supported key with at least one modifier for the planner shortcut.") }
        let flags = chord.modifiers.reduce(UInt32(0)) { result, modifier in result | ["command":UInt32(cmdKey),"option":UInt32(optionKey),"shift":UInt32(shiftKey),"control":UInt32(controlKey)][modifier, default:0] }
        // Validate first, then replace the old registration. Only this app opening shortcut is observed.
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { AppDelegate.openPlanner() }; return noErr
            }, 1, &event, nil, &handler)
            guard status == noErr else { throw PlanError.invalid("Shortcut event handler failed with code \(status).") }
        }
        let result = RegisterEventHotKey(code, flags, EventHotKeyID(signature: 0x4B4F564C, id: 1), GetApplicationEventTarget(), 0, &ref)
        guard result == noErr else { throw PlanError.invalid("Shortcut registration failed with code \(result).") }
    }
}
