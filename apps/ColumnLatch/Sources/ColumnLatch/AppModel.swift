import AppKit
import SwiftUI
import ColumnLatchCore
import Carbon

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
@MainActor final class AppModel: ObservableObject {
    static var openPanel: (() -> Void)?
    @Published var state = SavedState()
    @Published var sampleMode = false
    @Published var selected: UUID?
    @Published var draft = Contract(name: "New supplier", rules: [])
    @Published var result: Summary?
    @Published var message = "Choose Sample or select a CSV header to create a contract."
    @Published var busy = false
    @Published var stale = false
    @Published var incomplete = false
    @Published var shortcutError = ""
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "System" { didSet { UserDefaults.standard.set(appearance, forKey: "appearance") } }
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? "English" { didSet { UserDefaults.standard.set(language, forKey: "language") } }
    @Published var shortcutKey = UserDefaults.standard.integer(forKey: "shortcutKey")
    private var sampleContract = Contract.sample
    private var sampleBaseline: Summary?
    private var flag: CancellationFlag?
    private var token = UUID()
    private var inputURL: URL?
    private var inputDate: Date?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    let stateURL: URL
    var contract: Contract { draft }
    var localizedMessage: String {
        if language == "Español" && message.hasPrefix("Incomplete.") && L(message) == message { return "Incompleto. No se pudo completar la revisión. Elija de nuevo si no tiene permiso. Se conserva la revisión anterior. " + message }
        return L(message)
    }
    var activeBaseline: Summary? { sampleMode ? sampleBaseline : state.baselines[draft.id.uuidString] }
    var outdated: Bool { stale || (result?.contractSnapshot.map { $0 != draft } ?? false) }
    var status: String { busy ? "Checking" : incomplete ? "Incomplete" : outdated ? "Stale" : result.map { $0.complete ? ($0.failed ? "Findings" : "Accepted") : "Incomplete" } ?? "No input" }
    var statusSymbol: String { busy ? "arrow.triangle.2.circlepath" : (outdated || incomplete) ? "questionmark.circle" : result.map { $0.complete ? ($0.failed ? "exclamationmark.circle" : "checkmark.circle") : "questionmark.circle" } ?? "tablecells" }
    var pinnedContract: Contract? { state.contracts.first { $0.id == state.pinned } }
    var menuResult: Summary? { if sampleMode || state.pinned == nil || state.pinned == draft.id { return result }; return state.baselines[state.pinned!.uuidString] }
    var menuStatus: String { if sampleMode || state.pinned == nil || state.pinned == draft.id { return status }; return menuResult == nil ? "No input" : "Stale" }
    var menuSymbol: String { if sampleMode || state.pinned == nil || state.pinned == draft.id { return statusSymbol }; return menuResult == nil ? "tablecells" : "questionmark.circle" }
    var menuMessage: String { if !sampleMode, let c = pinnedContract, c.id != draft.id { return "Pinned · " + c.name + " · Open to check the last completed result again." }; return localizedMessage }
    var statusTitle: String { (sampleMode ? "S " : (pinnedContract.map { String($0.name.prefix(18)) + " " } ?? "")) + L(menuStatus) }
    func openPinned() { if !sampleMode, let pinned = state.pinned, pinned != draft.id { select(pinned) }; Self.openPanel?(); NSApp.activate(ignoringOtherApps: true) }
    func checkPinned() { if !sampleMode, let pinned = state.pinned, pinned != draft.id { select(pinned) }; checkSaved() }
    func tr(_ english: String, _ spanish: String) -> String { language == "Español" ? spanish : english }
    init(persist: Bool = true) {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/ColumnLatch")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        stateURL = root.appendingPathComponent("state.json")
        if persist && FileManager.default.fileExists(atPath: stateURL.path) {
            do { state = try StateStore.load(at: stateURL); selected = state.pinned ?? state.contracts.first?.id; select(selected) }
            catch { message = "Saved state could not be read. Clear local data to reset, or create a new contract. Source files are safe." }
        }
    }
    func save() {
        do { try StateStore.save(state, at: stateURL) }
        catch { message = "Could not save local state. \(error.localizedDescription)" }
    }
    func select(_ id: UUID?) {
        cancel(); incomplete = false; selected = id; inputURL = nil; inputDate = nil
        if let c = state.contracts.first(where: { $0.id == id }) { draft = c; result = state.baselines[c.id.uuidString]; stale = result != nil; message = "Choose a delivery or check the saved file. Previous result is stale until checked again." }
        else { draft = Contract(name: "New supplier", rules: []); result = nil; stale = false }
    }
    func setSample(_ enabled: Bool) {
        cancel(); sampleMode = enabled; inputURL = nil; result = nil; stale = false
        if enabled { draft = sampleContract; runSample() }
        else { select(selected); message = "Live mode. Choose a delivery to validate your saved contract." }
    }
    func resetSample() { sampleContract = .sample; sampleBaseline = nil; draft = sampleContract; runSample() }
    func runSample() {
        do {
            let current = try Validator.run(Validator.sampleData, contract: draft)
            result = Validator.compare(current, previous: sampleBaseline); sampleBaseline = result; stale = false; incomplete = false
            message = "Sample has a duplicate item key and an invalid quantity. Optional status is absent and passes."
        } catch { message = error.localizedDescription; stale = true }
    }
    func saveContract() {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !draft.rules.isEmpty else { message = "Choose a CSV header and name this contract first."; return }
        cancel()
        if sampleMode { sampleContract = draft; sampleBaseline = nil; runSample(); return }
        if let i = state.contracts.firstIndex(where: { $0.id == draft.id }) {
            if state.contracts[i] != draft { state.baselines.removeValue(forKey: draft.id.uuidString); result = nil }
            state.contracts[i] = draft
        } else { state.contracts.append(draft) }
        selected = draft.id; save(); stale = true; message = "Contract saved. Check a new delivery using these explicit rules."
    }
    func choose(headerOnly: Bool = false) {
        DispatchQueue.main.async { self.presentPicker(headerOnly: headerOnly) }
    }
    private func presentPicker(headerOnly: Bool) {
        guard !sampleMode else { runSample(); return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = headerOnly ? "Choose a UTF8 CSV. Only the header becomes your contract. No values are inferred." : "Choose a delivery to check. The source file is never changed."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { self.message = "Selection cancelled. The last completed baseline is preserved."; return }
            self.acceptSelection(url, headerOnly: headerOnly)
        }
        if let window = NSApp.windows.first(where: { $0.title == "ColumnLatch" }) { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func acceptSelection(_ url: URL, headerOnly: Bool) {
        if headerOnly {
            do {
                let data = try read(url)
                let names = try CSV.header(data, delimiter: draft.delimiter.first ?? ",")
                let delimiter = draft.delimiter
                draft = Contract(name: "New supplier", rules: names.map { Rule($0) }); draft.delimiter = delimiter
                selected = nil; inputURL = nil; inputDate = nil
                result = nil; stale = false; incomplete = false; message = "Header loaded. Name the supplier and edit rules in Contract, then save."
            } catch { fail(error) }
        } else { check(url) }
    }
    private func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try InputReader.read(url)
    }
    func checkSaved() {
        if sampleMode { runSample(); return }
        guard let bookmark = state.bookmarks[draft.id.uuidString] else { choose(); return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard !isStale else { stale = true; message = "Saved permission is stale. Choose again to restore access."; return }
            check(url)
        } catch { fail(error) }
    }
    func check(_ url: URL) {
        guard !draft.rules.isEmpty else { message = "Create and save a contract from a header first."; return }
        saveContract()
        let currentContract = draft, previous = activeBaseline
        let cancellation = CancellationFlag(); flag = cancellation; busy = true; stale = true; incomplete = false; message = "Checking every logical record. Cancel preserves the last completed baseline."
        let runToken = UUID(); token = runToken
        let access = url.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) {
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let before = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let data = try InputReader.read(url, cancelled: { cancellation.cancelled })
                let summary = try Validator.run(data, contract: currentContract, cancelled: { cancellation.cancelled })
                let after = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                guard before == after else { throw NSError(domain: "ColumnLatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Input changed during the check. Choose again and retry."]) }
                let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                await MainActor.run {
                    guard self.token == runToken, !cancellation.cancelled else { return }
                    let compared = Validator.compare(summary, previous: previous)
                    self.result = compared; self.state.commit(compared, contract: currentContract)
                    self.state.bookmarks[currentContract.id.uuidString] = bookmark
                    self.inputURL = url; self.inputDate = after; self.stale = false; self.incomplete = false; self.busy = false
                    self.message = summary.failed ? "Delivery has findings. Review the affected columns and record numbers." : "All required rules passed. Review warnings before importing."
                    self.save()
                }
            } catch { await MainActor.run { if self.token == runToken { self.busy = false; self.fail(error) } } }
        }
    }
    func fail(_ error: Error) {
        stale = true; incomplete = true
        message = error is CancellationError ? "Incomplete. Check cancelled. The completed baseline is preserved." : "Incomplete. \(error.localizedDescription) Choose again if access was denied. The completed baseline is preserved."
    }
    func cancel() { if busy { flag?.cancel(); busy = false; stale = true; incomplete = true; message = "Incomplete. Cancelled. Previous baseline preserved." }; token = UUID() }
    func becameActive() {
        if let url = inputURL {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if date != inputDate { stale = true; message = "Input changed or is unavailable. Check again. Previous result is stale." }
        }
    }
    func copyReport() {
        guard let result else { return }
        var report = result.report(contract: draft, sample: sampleMode)
        if outdated || busy { report = "STALE OR INCOMPLETE · Last completed result only\n" + report }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string)
        message = "Value redacted report copied. Column names and contract rules are included."
    }
    func pin() { state.pinned = draft.id; save() }
    func clear() { cancel(); state = SavedState(); selected = nil; result = nil; inputURL = nil; sampleBaseline = nil; sampleContract = .sample; sampleMode = false; draft = Contract(name: "New supplier", rules: []); stale = false; incomplete = false; save(); message = "Local contracts, bookmarks and summaries removed. Source files were not changed." }
    func registerShortcut() {
        UserDefaults.standard.set(shortcutKey, forKey: "shortcutKey")
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { AppModel.openPanel?(); NSApp.activate(ignoringOtherApps: true) }; return noErr
            }, 1, &spec, nil, &handler)
            if installStatus != noErr { shortcutError = "Shortcut handler unavailable. Error \(installStatus)."; return }
        }
        let keys: [UInt32] = [UInt32(kVK_ANSI_L), UInt32(kVK_ANSI_K), UInt32(kVK_ANSI_J)]
        let status = RegisterEventHotKey(keys[min(max(shortcutKey, 0), 2)], UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x434C4154, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        shortcutError = status == noErr ? "" : "Shortcut unavailable. Choose another key. Error \(status)."
    }
}
