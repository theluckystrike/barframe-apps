import AppKit
import SwiftUI
import NameWeaveCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sample = false
    @Published var policy = Policy() { didSet { rebuildPlan(); if !editingPolicyFields { syncPolicyFields() } } }
    @Published var scan: Scan? { didSet { rebuildPlan() } }
    @Published var edits: [String: String] = [:] { didSet { rebuildPlan() } }
    @Published var busy = false
    @Published var stale = false
    @Published var error: String?
    @Published var rootLabel = ""
    @Published var checkedAt: Date?
    @Published var copied = false
    @Published var spanish = UserDefaults.standard.bool(forKey: "spanish") { didSet { UserDefaults.standard.set(spanish, forKey: "spanish") } }
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system" { didSet { UserDefaults.standard.set(appearance, forKey: "appearance") } }
    static let defaultShortcutKey = ""
    @Published var shortcutKey = UserDefaults.standard.string(forKey: "shortcut") ?? AppModel.defaultShortcutKey { didSet { UserDefaults.standard.set(shortcutKey, forKey: "shortcut") } }
    @Published var shortcutModifier = UserDefaults.standard.string(forKey: "modifier") ?? "commandShift" { didSet { UserDefaults.standard.set(shortcutModifier, forKey: "modifier") } }
    @Published var shortcutError: String?
    private var bookmark: Data?
    private var rootURL: URL?
    private var live = SavedState()
    private let monitor = InputMonitor()
    private var cancellation: ScanCancellation?
    private var generation = UUID()
    private let stateURL: URL
    var onChange: (() -> Void)?
    @Published private(set) var plan = Weave.plan(Scan(entries: []), policy: Policy(), edits: [:])
    @Published var observationNotice: String?
    private var appliedExclusions: [String] = []
    private var pendingSave: Task<Void, Never>?
    private(set) var planBuildCount = 0
    private(set) var saveCount = 0
    private func rebuildPlan() {
        plan = Weave.plan(scan ?? Scan(entries: []), policy: policy, edits: edits)
        planBuildCount += 1
    }
    @Published private var budgetDraft = ""
    @Published private var exclusionsDraft = ""
    private var editingPolicyFields = false
    private func syncPolicyFields() {
        budgetDraft = policy.legacyBudget.map(String.init) ?? ""
        exclusionsDraft = policy.exclusions.joined(separator: ",")
    }
    var budgetText: String {
        get { budgetDraft }
        set {
            budgetDraft = newValue; editingPolicyFields = true
            policy.legacyBudget = Int(newValue).flatMap { $0 > 0 ? $0 : nil }
            editingPolicyFields = false; updatePolicy()
        }
    }
    var exclusionsText: String {
        get { exclusionsDraft }
        set {
            exclusionsDraft = newValue; editingPolicyFields = true
            policy.exclusions = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            editingPolicyFields = false; updatePolicy()
        }
    }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    var status: String {
        if busy { return l("Checking", "Comprobando") }
        if stale { return l("Incomplete", "Incompleto") }
        guard let scan else { return l("Choose folder", "Elegir carpeta") }
        if !scan.coverage.complete { return l("Incomplete", "Incompleto") }
        return (plan.issueCount > 0 || plan.unresolvedCount > 0) ? l("Issues", "Problemas") : l("Clear", "Sin problemas")
    }
    var ready: Bool { scan != nil && !busy && !stale && plan.ready }
    var badge: String { busy ? "◌" : stale || scan?.coverage.complete == false ? "?" : scan == nil ? "○" : (plan.issueCount > 0 || plan.unresolvedCount > 0) ? "!" : "✓" }
    var stateAccessibility: String { (sample ? "Sample " : "") + status + " " + (checkedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? l("Not checked", "Sin comprobar")) }
    func l(_ english: String, _ es: String) -> String { spanish ? es : english }
    init(stateURL: URL? = nil, restoreBookmark: (Data) throws -> (URL, Data) = BookmarkAccess.restore) {
        self.stateURL = stateURL ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("nameweave-state.json")
        if FileManager.default.fileExists(atPath: self.stateURL.path) {
            do {
                live = try StateStore.load(self.stateURL)
                policy = live.policy; bookmark = live.bookmark; rootLabel = live.rootLabel; scan = live.scan; edits = live.edits; checkedAt = live.checkedAt
                stale = scan != nil
                appliedExclusions = policy.exclusions
                if let bookmark {
                    do {
                        let restored = try restoreBookmark(bookmark)
                        rootURL = restored.0; self.bookmark = restored.1
                        if restored.1 != bookmark { persist() }
                    } catch {
                        rootURL = nil; stale = scan != nil
                        self.error = l("Saved folder is unavailable or access could not be restored. Choose again. ", "La carpeta guardada no está disponible o no se pudo recuperar el acceso. Vuelve a elegir. ") + error.localizedDescription
                    }
                }
            } catch { self.error = l("Saved state could not be restored. Choose the folder again.", "No se pudo recuperar el estado. Vuelve a elegir la carpeta.") }
        }
        rebuildPlan(); syncPolicyFields()
    }
    func persist() {
        pendingSave?.cancel(); pendingSave = nil
        if sample { return }
        live.bookmark = bookmark; live.rootLabel = rootLabel; live.policy = policy; live.scan = scan; live.edits = edits; live.checkedAt = checkedAt
        do { try StateStore.save(live, to: stateURL); saveCount += 1 }
        catch { self.error = l("Could not save local state. ", "No se pudo guardar el estado. ") + error.localizedDescription }
        onChange?()
    }
    private func schedulePersist() {
        pendingSave?.cancel()
        if !sample {
            pendingSave = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.persist()
            }
        }
    }
    func toggleSample(_ enabled: Bool) {
        cancelScan(); monitor.stop()
        if enabled && !sample { persist(); sample = true; resetSample() }
        else if !enabled && sample {
            sample = false; policy = live.policy; appliedExclusions = policy.exclusions; scan = live.scan; edits = live.edits; rootLabel = live.rootLabel; checkedAt = live.checkedAt; stale = scan != nil; error = nil
        }
        observationNotice = nil; copied = false; onChange?()
    }
    func resetSample() { policy = Policy(); appliedExclusions = []; scan = Weave.sample; edits = Weave.suggestions(Weave.sample); stale = false; error = nil; rootLabel = "Sample handoff folder"; checkedAt = Date(); onChange?() }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = l("Read filenames only to review a handoff plan. Source files are never changed.", "Leer solo nombres para revisar un plan. Los archivos no se modifican.")
        // Begin the system sheet after the triggering control has finished its event.
        DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.keyWindow, window.canBecomeKey {
            panel.beginSheetModal(for: window) { response in self.acceptSelection(panel, response: response) }
        } else {
            panel.begin { response in self.acceptSelection(panel, response: response) }
        }
        }
    }
    private func acceptSelection(_ panel: NSOpenPanel, response: NSApplication.ModalResponse) {
        guard response == .OK, let url = panel.url else {
            error = l("Selection cancelled. No new result was produced.", "Selección cancelada. No hay un resultado nuevo."); stale = scan != nil; onChange?(); return
        }
        if sample { toggleSample(false) }
        do {
            bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            rootURL = url; rootLabel = url.lastPathComponent; scan = nil; edits = [:]; checkedAt = nil; persist(); rescan()
        } catch { stale = true; self.error = l("Folder access denied. Choose again. ", "Acceso denegado. Vuelve a elegir. ") + error.localizedDescription; onChange?() }
    }
    func rescan() {
        if sample { acceptScan(Weave.applyingExclusions(policy, to: Weave.sample)); onChange?(); return }
        guard let url = rootURL else { error = l("Choose the folder again to restore access.", "Vuelve a elegir la carpeta para recuperar el acceso."); stale = scan != nil; onChange?(); return }
        cancellation?.cancel()
        let token = UUID(); generation = token
        let cancel = ScanCancellation(); cancellation = cancel
        let selectedPolicy = policy
        busy = true; copied = false; error = nil; onChange?()
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                if !granted {
                    var coverage = Coverage(); coverage.omissions = ["Security scoped permission denied. Choose again."]
                    return Scan(entries: [], coverage: coverage)
                }
                return Scanner.scan(url, policy: selectedPolicy, cancellation: cancel)
            }.value
            guard token == generation else { return }
            busy = false; cancellation = nil
            acceptScan(result)
            let observation = monitor.watch(url, relativeDirectories: result.entries.filter(\.directory).map(\.path)) { [weak self] in
                Task { @MainActor in self?.markStaleOnReturn() }
            }
            observationNotice = observation.complete ? l("Visible name changes are observed. Returning to NameWeave requires a rescan.", "Se observan cambios de nombres visibles. Vuelve a comprobar al regresar a NameWeave.") : l("Folder observation is limited. Returning to NameWeave requires a rescan.", "La observación de carpetas es limitada. Vuelve a comprobar al regresar a NameWeave.")
            persist(); onChange?()
        }
    }
    func acceptScan(_ result: Scan) {
        let saved = edits
        scan = result; edits = Weave.mergingEdits(saved, into: result)
        appliedExclusions = policy.exclusions; stale = false; checkedAt = Date(); copied = false
    }
    func cancelScan() {
        if busy { cancellation?.cancel(); generation = UUID(); busy = false; stale = true; error = l("Check cancelled. Rescan to obtain a complete result.", "Comprobación cancelada. Vuelve a comprobar.") }
        onChange?()
    }
    func updatePolicy() {
        if busy { cancelScan() }
        if scan != nil && policy.exclusions != appliedExclusions { stale = true }
        copied = false; schedulePersist(); onChange?()
    }
    func edit(_ entry: Entry, value: String) { edits[entry.id] = value; copied = false; schedulePersist(); onChange?() }
    func resolve() { guard let scan else { return }; edits = Weave.resolve(scan, policy: policy, edits: edits); copied = false; persist(); onChange?() }
    func copyPlan() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(plan.report(sample: sample, stale: stale || busy, policy: policy), forType: .string); copied = true }
    func forget() {
        cancelScan(); monitor.stop(); bookmark = nil; rootURL = nil; live = SavedState()
        observationNotice = nil; sample = false; rootLabel = ""; scan = nil; edits = [:]; checkedAt = nil; stale = false; error = nil
        persist(); onChange?()
    }
    func clearLocalData() {
        forget(); policy = Policy(); live = SavedState()
        do { if FileManager.default.fileExists(atPath: stateURL.path) { try FileManager.default.removeItem(at: stateURL) } }
        catch { self.error = error.localizedDescription }
        for key in ["spanish", "appearance", "shortcut", "modifier"] { UserDefaults.standard.removeObject(forKey: key) }
        spanish = false; appearance = "system"; shortcutKey = ""; shortcutModifier = "commandShift"; onChange?()
    }
    func markStaleOnReturn() { if !sample && scan != nil { stale = true; onChange?() } }
}

/// Bookmark failures are kept separate from JSON restoration failures.
enum BookmarkAccess {
    static func restore(_ data: Data) throws -> (URL, Data) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        let refreshed = try refreshIfStale(data, stale: stale) {
            try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return (url, refreshed)
    }
    static func refreshIfStale(_ data: Data, stale: Bool, create: () throws -> Data) rethrows -> Data {
        try stale ? create() : data
    }
}
