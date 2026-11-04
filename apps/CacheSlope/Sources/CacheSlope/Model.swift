import AppKit
import SwiftUI
import CacheSlopeCore
import Carbon

struct Root: Codable, Identifiable {
    var id = UUID(); var name: String; var bookmark: Data
    var history: [Snapshot] = []; var baseline: Snapshot?; var threshold: Int64 = 500_000_000
}
final class Cancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}
@MainActor final class Model: ObservableObject {
    @Published var roots: [Root] = []
    @Published var selected: UUID?
    @Published var sample = false
    @Published var scanning = false
    @Published var message = ""
    @Published var denied = false
    @Published var interval = 0
    @Published var retention = 20
    @Published var shortcutChoice = 0
    @Published var shortcutError = ""
    @Published var spanish = Locale.current.language.languageCode?.identifier == "es"
    private var live: [Root] = []
    private var cancellation: Cancellation?
    private var undoBaseline: (UUID, Snapshot?)?
    private var timer: Timer?
    private var hotKey: EventHotKeyRef?
    private let saveURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/CacheSlope/roots.json")
    var index: Int? { roots.firstIndex { $0.id == selected } }
    var root: Root? { index.map { roots[$0] } }
    var pair: (Snapshot?, Snapshot?) { Analysis.pair(root?.history ?? [], pinned: root?.baseline) }
    var changes: [Change] { pair.0.map { Analysis.compare($0, to: pair.1) } ?? [] }
    var state: String {
        if scanning { return tr("Scanning", "Analizando") }
        if denied { return tr("Choose folder again", "Selecciona la carpeta de nuevo") }
        if root?.history.last?.complete == false { return tr("Partial scan", "Análisis parcial") }
        if pair.0 == nil { return tr("No baseline", "Sin referencia") }
        if pair.1 == nil { return tr("Baseline recorded", "Referencia guardada") }
        return Analysis.attention(changes, threshold: root?.threshold ?? 0) ? tr("Growth needs attention", "Revisa el crecimiento") : tr("Below growth threshold", "Por debajo del umbral")
    }
    var symbol: String {
        if scanning { return "arrow.triangle.2.circlepath" }
        if denied { return "lock" }
        if pair.0 == nil { return "folder" }
        let growth = Analysis.attention(changes, threshold: root?.threshold ?? 0)
        let preferred = growth ? "folder.badge.exclamationmark" : "folder.badge.checkmark"
        return NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil ? preferred : growth ? "exclamationmark.triangle" : "checkmark.circle"
    }
    init(preview: Bool = false) {
        if preview { return }
        do { if FileManager.default.fileExists(atPath: saveURL.path) { roots = try JSONDecoder().decode([Root].self, from: Data(contentsOf: saveURL)) } } catch { message = "Saved data could not be read. " + error.localizedDescription }
        selected = roots.first?.id
        interval = UserDefaults.standard.integer(forKey: "interval")
        retention = max(2, UserDefaults.standard.object(forKey: "retention") as? Int ?? 20)
        shortcutChoice = UserDefaults.standard.integer(forKey: "shortcut")
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.title == "CacheSlope" && $0.canBecomeKey }?.makeKeyAndOrderFront(nil) }; return noErr
        }, 1, [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))], nil, nil)
        registerShortcut(); schedule()
    }
    func tr(_ en: String, _ es: String) -> String { spanish ? es : en }
    func persist() {
        guard !sample else { return }
        do { try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(roots).write(to: saveURL, options: .atomic) } catch { message = error.localizedDescription }
    }
    func toggleSample(_ enabled: Bool) {
        guard !scanning else { return }
        if enabled && !sample { live = roots }
        sample = enabled
        if enabled { roots = [Root(name: "BuildCache", bookmark: Data(), history: Fixtures.history), Root(name: "ProjectAssets", bookmark: Data(), history: [Fixtures.partial])] } else { roots = live }
        selected = roots.first?.id; message = ""; denied = false; undoBaseline = nil
    }
    func choose(replace: Bool = false) {
        guard !sample && !scanning else { return }
        // Leave the SwiftUI accessibility action before creating the remote system panel.
        DispatchQueue.main.async { self.presentChooser(replace: replace) }
    }
    private func presentChooser(replace: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = tr("Allow read only access to measure logical file sizes. File contents are never read.", "Permite acceso de lectura para medir tamaños. No se lee el contenido.")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.acceptFolder(url, replace: replace)
        }
    }
    private func acceptFolder(_ url: URL, replace: Bool) {
        guard !sample && !scanning else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            if replace, let i = index {
                // A replacement may point to a different directory. Start a new history.
                roots[i] = Root(name: url.lastPathComponent, bookmark: bookmark); selected = roots[i].id
            } else { let root = Root(name: url.lastPathComponent, bookmark: bookmark); roots.append(root); selected = root.id }
            denied = false; message = ""; persist()
        } catch { message = error.localizedDescription; denied = true }
    }
    func scan() {
        guard !scanning, let i = index else { return }
        if sample { roots[i].history.append(i == 0 ? Fixtures.history.last! : Fixtures.partial); trim(); return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: roots[i].bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else { denied = true; message = tr("Choose folder again to renew access", "Selecciona la carpeta para renovar el acceso"); return }
            guard url.startAccessingSecurityScopedResource() else { denied = true; message = tr("Permission unavailable", "Permiso no disponible"); return }
            denied = false; scanning = true; message = ""
            let token = Cancellation(); cancellation = token; let id = roots[i].id
            Task {
                let snapshot = await Task.detached(priority: .utility) { Scanner.scan(url, cancelled: { token.get() }) }.value
                url.stopAccessingSecurityScopedResource()
                if let index = roots.firstIndex(where: { $0.id == id }) { roots[index].history.append(snapshot) }
                scanning = false; cancellation = nil; trim(); persist()
                if snapshot.cancelled { message = tr("Cancelled scan retained as partial", "Análisis cancelado guardado como parcial") }
            }
        } catch { denied = true; message = error.localizedDescription }
    }
    func cancel() { cancellation?.cancel() }
    func trim() { for i in roots.indices { roots[i].history = Analysis.retain(roots[i].history, limit: retention) }; persist() }
    func pin() { guard let i = index, let current = pair.0 else { return }; undoBaseline = (roots[i].id, roots[i].baseline); roots[i].baseline = current; persist() }
    func undoPin() { guard let previous = undoBaseline, let i = roots.firstIndex(where: { $0.id == previous.0 }) else { return }; roots[i].baseline = previous.1; undoBaseline = nil; persist() }
    var canUndo: Bool { undoBaseline != nil }
    func unpin() { guard let i = index else { return }; undoBaseline = (roots[i].id, roots[i].baseline); roots[i].baseline = nil; persist() }
    func remove() { guard !scanning, let i = index else { return }; roots.remove(at: i); selected = roots.first?.id; undoBaseline = nil; persist() }
    func clear() { guard !scanning else { return }; roots = []; selected = nil; undoBaseline = nil; persist() }
    func copyReport() {
        let header = (sample ? "Sample\n" : "") + (root?.name ?? "") + "\n" + state + "\n" + (pair.0?.date.formatted() ?? "") + "\n"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(header + Analysis.report(changes), forType: .string)
    }
    func reveal(_ name: String) {
        guard !sample, let root else { message = tr("Sample folders are fictional", "Las carpetas de muestra son ficticias"); return }
        do { var stale = false; let url = try URL(resolvingBookmarkData: root.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, url.startAccessingSecurityScopedResource() else { denied = true; return }
            defer { url.stopAccessingSecurityScopedResource() }
            NSWorkspace.shared.activateFileViewerSelecting([name == "Files in root" ? url : url.appendingPathComponent(name)])
        } catch { denied = true; message = error.localizedDescription }
    }
    func schedule() {
        timer?.invalidate(); UserDefaults.standard.set(interval, forKey: "interval")
        guard interval > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Double(interval * 60), repeats: true) { [weak self] _ in Task { @MainActor in guard let self, !self.sample, !self.scanning else { return }; self.scan() } }
    }
    func registerShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        let code: UInt32 = shortcutChoice == 0 ? 8 : 5
        let result = RegisterEventHotKey(code, UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x43534C50, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        shortcutError = result == noErr ? "" : tr("Shortcut unavailable. Open the report from the menu bar.", "Atajo no disponible. Abre el informe desde la barra de menús.")
        UserDefaults.standard.set(shortcutChoice, forKey: "shortcut")
    }
}
