import AppKit
import SwiftUI
import LinkSprigCore

final class Cancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
@MainActor
final class AppModel: ObservableObject {
    @Published var sampleMode = false
    @Published var plan: Plan?
    @Published var busy = false
    @Published var stale = false
    @Published var message = ""
    @Published var rootName = ""
    @Published var source = "" { didSet { edited() } }
    @Published var destination = "" { didSet { edited() } }
    @Published var includeImages = true { didSet { edited(); save() } }
    @Published var excludedNames = "" { didSet { edited(); save() } }
    @Published var appearance = "system" { didSet { applyAppearance(); save() } }
    @Published var language = "en" { didSet { message = ""; shortcutError = ""; shortcutChanged?(); save() } }
    @Published var shortcutKey: UInt32 = UInt32.max { didSet { save(); shortcutChanged?() } }
    @Published var shortcutError = ""
    @Published var shortcutModifiers: UInt32 = 2304 { didSet { save(); shortcutChanged?() } }
    var shortcutChanged: (() -> Void)?
    private var state = SavedState()
    private var root: URL?
    private var livePlan: Plan?
    private var tree: Tree?
    private var loading = true
    private var cancellation: Cancellation?
    private var scanID = UUID()
    private var activationTask: Task<Void, Never>?
    private var activationCancellation: Cancellation?
    private var lastActivationCheck = Date.distantPast
    private let persistent: Bool
    private let directory: URL
    var sampleRoot: URL { directory.appendingPathComponent("SampleDocs") }
    var stateURL: URL { directory.appendingPathComponent("state.json") }
    var planURL: URL { directory.appendingPathComponent("last-plan.json") }
    var proposal: Proposal { Proposal(source: source.trimmingCharacters(in: .whitespacesAndNewlines), destination: destination.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var exclusions: Set<String> { Set(excludedNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }) }
    var status: String {
        if busy { return tr("Scanning", "Escaneando") }
        if stale { return tr("Stale result", "Resultado anterior") }
        if let plan { return plan.incomplete ? "\(plan.affected.count) " + tr("affected · Incomplete", "afectados · Incompleto") : plan.affected.isEmpty ? tr("Clear", "Sin cambios") : "\(plan.affected.count) " + tr("affected", "afectados") }
        return root == nil && !sampleMode ? tr("Choose inputs", "Elegir datos") : tr("Enter a move", "Proponer cambio")
    }
    var menuTitle: String { (sampleMode ? "S · " : "") + status }
    var badge: String { busy ? "clock" : stale ? "questionmark.circle" : plan == nil ? "circle" : plan!.incomplete ? "questionmark.circle" : plan!.affected.isEmpty ? "checkmark.circle" : "exclamationmark.circle" }
    func tr(_ en: String, _ es: String) -> String { language == "es" ? es : en }
    init(persistent: Bool = true) {
        self.persistent = persistent
        directory = persistent ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("LinkSprig") : FileManager.default.temporaryDirectory.appendingPathComponent("LinkSprigPreview-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let loaded = SavedState.load(persistent ? try? Data(contentsOf: stateURL) : nil)
        state = loaded.0
        rootName = state.rootName; source = state.proposal.source; destination = state.proposal.destination
        includeImages = state.includeImages; excludedNames = state.exclusions.joined(separator: ", ")
        appearance = state.appearance; language = state.language; shortcutKey = state.shortcutKey; shortcutModifiers = state.shortcutModifiers ?? 2304
        if loaded.1 { message = tr("Saved settings could not be read. Choose your folder again.", "No se pudieron leer los ajustes guardados. Vuelve a elegir la carpeta.") }
        if persistent, let data = try? Data(contentsOf: planURL), let saved = try? JSONDecoder().decode(Plan.self, from: data) { livePlan = saved; plan = saved; stale = true }
        if let bookmark = state.bookmark {
            do {
                var bookmarkStale = false
                root = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &bookmarkStale)
                if bookmarkStale { root = nil; stale = true; message = tr("Folder permission expired. Choose again. The saved result is stale.", "El permiso de la carpeta caducó. Vuelve a elegirla. El resultado no está actualizado.") }
            } catch { stale = true; message = tr("Folder access unavailable. Choose again. The saved result is stale.", "Acceso a la carpeta no disponible. Vuelve a elegirla. El resultado no está actualizado.") }
        }
        loading = false; applyAppearance()
    }
    func edited() {
        guard !loading else { return }
        activationTask?.cancel(); activationCancellation?.cancel()
        if plan != nil { stale = true }
        save()
    }
    func save() {
        guard !loading, persistent else { return }
        if !sampleMode { state.proposal = proposal }
        state.includeImages = includeImages; state.exclusions = exclusions.sorted(); state.shortcutKey = shortcutKey; state.shortcutModifiers = shortcutModifiers; state.appearance = appearance; state.language = language
        do { try JSONEncoder().encode(state).write(to: stateURL, options: .atomic) }
        catch { message = tr("Local settings could not be saved.", "No se pudieron guardar los ajustes locales.") }
    }
    func applyAppearance() { NSApp?.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil }
    func chooseRoot() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = tr("Choose a documentation folder. LinkSprig reads it and never modifies your files.", "Elige una carpeta de documentación. LinkSprig la lee sin modificar tus archivos.")
        guard panel.runModal() == .OK, let selected = panel.url else { message = tr("Selection cancelled. Choose a folder when ready.", "Selección cancelada. Elige una carpeta cuando quieras."); if plan != nil { stale = true }; return }
        do {
            let bookmark = try selected.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            cancel(); loading = true; sampleMode = false; root = selected; rootName = selected.lastPathComponent
            state.bookmark = bookmark; state.rootName = rootName; state.proposal = Proposal()
            source = ""; destination = ""; plan = nil; tree = nil; livePlan = nil; stale = false; message = ""
            loading = false; try? FileManager.default.removeItem(at: planURL); save()
        } catch { message = tr("Folder permission could not be saved. Choose again.", "No se pudo guardar el permiso de la carpeta. Vuelve a elegirla."); stale = plan != nil }
    }
    func setSample(_ enabled: Bool) {
        cancel(); loading = true
        if !sampleMode { state.proposal = proposal; livePlan = plan }
        sampleMode = enabled
        tree = nil; message = ""
        if enabled {
            source = Sample.proposal.source; destination = Sample.proposal.destination
            plan = nil; stale = false; rootName = tr("Sample docs", "Documentos Sample")
            loading = false; resetSample()
        } else {
            rootName = state.rootName; source = state.proposal.source; destination = state.proposal.destination
            plan = livePlan; stale = livePlan != nil; loading = false
        }
    }
    func resetSample() {
        guard sampleMode else { return }
        do {
            try Sample.create(at: sampleRoot)
            loading = true; source = Sample.proposal.source; destination = Sample.proposal.destination; loading = false
            let scanned = try Scanner.scan(root: sampleRoot, includeImages: includeImages, excluded: exclusions)
            tree = scanned; plan = try Planner.plan(tree: scanned, proposal: proposal); stale = false; message = ""
        } catch { message = localized(error); stale = true }
    }
    func rescan() {
        guard !busy else { return }
        guard let selected = sampleMode ? sampleRoot : root else {
            message = tr("Folder access unavailable. Choose the folder again.", "Acceso no disponible. Vuelve a elegir la carpeta."); stale = plan != nil; return
        }
        let scoped = !sampleMode
        if scoped && !selected.startAccessingSecurityScopedResource() { message = tr("Permission denied. Choose the folder again to restore read access.", "Permiso denegado. Vuelve a elegir la carpeta para restaurar el acceso."); stale = plan != nil; return }
        let id = UUID(); scanID = id; let token = Cancellation(); cancellation = token
        let proposal = self.proposal; let images = includeImages; let excluded = exclusions
        busy = true; message = ""
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(Tree, Plan), Error> in
                Result { let tree = try Scanner.scan(root: selected, includeImages: images, excluded: excluded, cancelled: { token.cancelled }); return (tree, try Planner.plan(tree: tree, proposal: proposal)) }
            }.value
            if scoped { selected.stopAccessingSecurityScopedResource() }
            guard scanID == id else { return }
            busy = false; cancellation = nil
            switch result {
            case let .success((tree, plan)):
                self.tree = tree; self.plan = plan; stale = self.proposal != proposal || self.includeImages != images || self.exclusions != excluded
                if !sampleMode { livePlan = plan; if persistent { try? JSONEncoder().encode(plan).write(to: planURL, options: .atomic) } }; save()
            case let .failure(error): message = localized(error); stale = plan != nil
            }
        }
    }
    func cancel() {
        activationTask?.cancel(); activationCancellation?.cancel(); activationTask = nil; activationCancellation = nil
        cancellation?.cancel(); cancellation = nil; scanID = UUID()
        if busy { busy = false; stale = plan != nil; message = tr("Scan cancelled. Rescan before using the previous result.", "Escaneo cancelado. Vuelve a escanear antes de usar el resultado anterior.") }
    }
    func resetProposal() {
        cancel(); loading = true; source = ""; destination = ""; loading = false
        plan = nil; tree = nil; stale = false; message = ""
        if !sampleMode { livePlan = nil; try? FileManager.default.removeItem(at: planURL) }; save()
    }
    func becameActive() {
        guard !sampleMode, !busy, let root, let tree, plan != nil, !stale else { return }
        activationTask?.cancel(); activationCancellation?.cancel()
        let token = Cancellation(); activationCancellation = token
        let excluded = exclusions; let id = scanID
        activationTask = Task {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled, Date().timeIntervalSince(lastActivationCheck) >= 5 else { return }
            lastActivationCheck = Date()
            guard root.startAccessingSecurityScopedResource() else {
                stale = true; message = tr("Permission denied. Choose again.", "Permiso denegado. Vuelve a elegir la carpeta."); return
            }
            let result = await Task.detached(priority: .utility) {
                try? Scanner.scan(root: root, excluded: excluded, cancelled: { token.cancelled }, parseDocuments: false)
            }.value
            root.stopAccessingSecurityScopedResource()
            guard !Task.isCancelled, !token.cancelled, !sampleMode, id == scanID else { return }
            if result?.fingerprint != tree.fingerprint {
                stale = true; message = tr("Folder contents changed. Rescan the proposal.", "La carpeta cambió. Vuelve a escanear la propuesta.")
            }
        }
    }
    func localized(_ error: Error) -> String {
        if let error = error as? ProposalError { return tr(error.rawValue, error.spanish) }
        if let error = error as? ScanError { return tr(error.localizedDescription, error.spanish) }
        return tr("The operation could not finish. Check folder access and try again.", "No se pudo completar la operación. Revisa el acceso a la carpeta e inténtalo de nuevo.")
    }
    func copyPlan() {
        guard let plan, !stale, !busy else { message = tr("Rescan before copying a current plan.", "Vuelve a escanear antes de copiar el plan."); return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(plan.report(sample: sampleMode), forType: .string)
        message = tr("Change plan copied. Files were not modified.", "Plan copiado. Los archivos no se modificaron.")
    }
    func clearLocalData() {
        cancel(); loading = true
        try? FileManager.default.removeItem(at: stateURL); try? FileManager.default.removeItem(at: planURL); try? FileManager.default.removeItem(at: sampleRoot)
        state = SavedState(); root = nil; rootName = ""; source = ""; destination = ""; tree = nil; plan = nil; livePlan = nil; sampleMode = false; stale = false
        includeImages = true; excludedNames = Scanner.exclusions.sorted().joined(separator: ", "); shortcutKey = UInt32.max; shortcutModifiers = 2304; appearance = "system"; language = "en"
        loading = false; applyAppearance(); shortcutChanged?(); message = tr("Local data cleared. Your source files were not changed.", "Datos locales borrados. Tus archivos permanecen intactos.")
    }
}
