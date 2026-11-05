import AppKit
import SwiftUI
import EnvTrellisCore

struct AccessFailure: Error {}
enum FileAccess {
    static func bookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    static func scoped<T>(_ file: InputFile, _ action: (URL) throws -> T) throws -> T {
        var stale = false
        let url = try URL(resolvingBookmarkData: file.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw AccessFailure() }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try action(url)
    }
    static func stamp(_ url: URL) throws -> FileStamp {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let date = values.contentModificationDate, let size = values.fileSize else { throw AccessFailure() }
        return FileStamp(modified: date, size: size)
    }
    static func scan(_ file: InputFile) -> InputFile {
        var file = file
        do {
            let pair = try scoped(file) { url -> (ParsedFile, FileStamp) in
                let before = try stamp(url)
                guard before.size <= 2 * 1024 * 1024 else { throw AccessFailure() }
                let data = try Data(contentsOf: url)
                guard data.count <= 2 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw AccessFailure() }
                let parsed = DotenvParser.parse(text)
                let after = try stamp(url)
                guard before == after else { throw AccessFailure() }
                return (parsed, after)
            }
            file.parsed = pair.0; file.stamp = pair.1; file.unavailable = false
        } catch { file.parsed = nil; file.unavailable = true; file.stamp = nil }
        return file
    }
    static func changed(_ file: InputFile) -> Bool {
        do { return try scoped(file) { try stamp($0) != file.stamp } } catch { return true }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var live = SavedState()
    @Published var sample = SampleFixtures.project()
    @Published var sampleMode = false
    @Published var scanning = false
    @Published var notice = ""
    @Published var reportCopied = false
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance"); applyAppearance() } }
    @Published var maskLabels: Bool { didSet { defaults.set(maskLabels, forKey: "maskLabels") } }
    @Published var shortcutKey: String { didSet { defaults.set(shortcutKey, forKey: "shortcutKey"); shortcutChanged?() } }
    @Published var shortcutError = ""
    var shortcutChanged: (() -> Void)?
    var openPanel: (() -> Void)?
    let defaults: UserDefaults
    let stateURL: URL
    private var generation = UUID()
    init(stateURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/EnvTrellis", isDirectory: true)
        self.stateURL = stateURL ?? folder.appendingPathComponent("live.json")
        language = defaults.string(forKey: "language") ?? "English"
        appearance = defaults.string(forKey: "appearance") ?? "System"
        maskLabels = defaults.bool(forKey: "maskLabels")
        shortcutKey = defaults.string(forKey: "shortcutKey") ?? "E"
        if FileManager.default.fileExists(atPath: self.stateURL.path) {
            do { live = try SavedState.decode(Data(contentsOf: self.stateURL)) }
            catch { notice = "Saved state could not be read. Choose inputs again or clear local data." }
        }
        if let data = try? Data(contentsOf: self.stateURL.deletingLastPathComponent().appendingPathComponent("sample.json")), let restored = try? JSONDecoder().decode(Project.self, from: data) { sample = restored }
        applyAppearance()
        refreshStale()
    }
    func t(_ text: String) -> String { language == "Español" ? Spanish.words[text] ?? text : text }
    var project: Project? { sampleMode ? sample : live.projects.first(where: { $0.id == live.pinned }) }
    var state: Readiness { project?.readiness ?? .noInputs }
    var menuState: String { scanning ? t("Scanning") : t(state.rawValue) }
    var badge: String { scanning ? "…" : state == .ready ? "✓" : state == .findings ? "!" : state == .stale ? "↻" : "?" }
    var lastScanText: String { project?.lastScan.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? t("Never scanned") }
    var report: String { project?.report(sample: sampleMode, maskLabels: maskLabels) ?? t("Choose a template and environment files to start.") }
    func save() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try live.encoded().write(to: stateURL, options: .atomic)
        } catch { notice = "Could not save local state. Changes remain in memory." }
    }
    func modify(_ action: (inout Project) -> Void) {
        guard !scanning else { return }
        if sampleMode { action(&sample); saveSample() }
        else if let index = live.projects.firstIndex(where: { $0.id == live.pinned }) { action(&live.projects[index]); save() }
        reportCopied = false
    }
    func toggleSample(_ on: Bool) {
        generation = UUID(); scanning = false; sampleMode = on; notice = ""; reportCopied = false
        if !on { refreshStale() }
    }
    func resetSample() { sample = SampleFixtures.project(); installSampleFixtures(); saveSample(); reportCopied = false }
    func saveSample() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(sample).write(to: stateURL.deletingLastPathComponent().appendingPathComponent("sample.json"), options: .atomic)
        } catch { notice = "Could not save local state. Changes remain in memory." }
    }
    func installSampleFixtures() {
        let folder = stateURL.deletingLastPathComponent().appendingPathComponent("Sample", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (file, text) in [("template.env", SampleFixtures.template), ("development.env", SampleFixtures.development), ("staging.env", SampleFixtures.staging), ("production.env", SampleFixtures.production)] {
                try Data(text.utf8).write(to: folder.appendingPathComponent(file), options: .atomic)
            }
        } catch { notice = "Sample fixtures could not be saved. Sample remains available in memory." }
    }
    func addProject() {
        guard !scanning else { return }
        toggleSample(false)
        let project = Project(label: "Project \(live.projects.count + 1)")
        live.projects.append(project); live.pinned = project.id; save()
    }
    func pin(_ id: UUID) { guard !scanning else { return }; live.pinned = id; sampleMode = false; save(); refreshStale() }
    func removeProject() {
        guard !sampleMode, !scanning else { return }
        live.projects.removeAll { $0.id == live.pinned }; live.pinned = live.projects.first?.id; save()
    }
    func chooseTemplate() { chooseFile(environmentID: nil, template: true) }
    func chooseFile(environmentID: UUID? = nil, template: Bool = false) {
        guard !sampleMode, !scanning else { return }
        if project == nil { addProject() }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = !template && environmentID == nil
        panel.message = t("Choose UTF8 files up to 2 MiB to read key names and presence. Values stay hidden and files are never changed.")
        panel.prompt = t("Choose inputs")
        guard panel.runModal() == .OK else { selectionCancelled(); return }
        do {
            var files: [InputFile] = []
            for url in panel.urls { files.append(InputFile(label: url.deletingPathExtension().lastPathComponent, bookmark: try FileAccess.bookmark(url))) }
            modify { project in
                if template { project.template = files.first }
                else if let environmentID, let index = project.environments.firstIndex(where: { $0.id == environmentID }), var file = files.first {
                    file.id = environmentID; file.label = project.environments[index].label; project.environments[index] = file
                } else { project.environments.append(contentsOf: files) }
                project.stale = project.lastScan != nil
            }
            notice = "Inputs selected. Rescan to review new keys and decide their rules."
        } catch { invalidatePreviousScan(); notice = "File access could not be saved. Choose again to grant read access." }
    }
    func invalidatePreviousScan() { modify { if $0.lastScan != nil { $0.stale = true } } }
    func selectionCancelled() { invalidatePreviousScan(); notice = "Selection cancelled. Rescan before relying on a previous result." }
    func forgetEnvironment(_ id: UUID) { modify { $0.environments.removeAll { $0.id == id }; $0.rules.removeValue(forKey: id) } }
    func rule(key: String, environment: UUID) -> Rule? { project?.rules[environment]?[key] }
    func setRule(key: String, environment: UUID, rule: Rule?) {
        modify { project in
            var rules = project.rules[environment] ?? [:]; rules[key] = rule; project.rules[environment] = rules
        }
    }
    func requireUndecided(_ environment: UUID) {
        modify { project in
            var rules = project.rules[environment] ?? [:]
            for key in project.keys where rules[key] == nil { rules[key] = .required }
            project.rules[environment] = rules
        }
    }
    func scan() {
        guard !scanning, let original = project else { notice = "Choose a template and environment files to start."; return }
        if sampleMode { sample.lastScan = Date(); sample.stale = false; saveSample(); notice = "Sample scan complete. Values remain hidden."; return }
        guard original.template != nil, !original.environments.isEmpty else { notice = "Choose a template and environment files to start."; return }
        scanning = true; notice = ""; reportCopied = false
        let token = UUID(); generation = token
        Task {
            let scanned = await Task.detached(priority: .userInitiated) {
                var updated = original
                updated.template = original.template.map { FileAccess.scan($0) }
                updated.environments = original.environments.map { FileAccess.scan($0) }
                updated.lastScan = Date(); updated.stale = false
                return updated
            }.value
            guard self.generation == token else { return }
            self.scanning = false
            if let index = self.live.projects.firstIndex(where: { $0.id == original.id }) { self.live.projects[index] = scanned; self.save() }
            self.notice = scanned.readiness == .unknown ? "Some inputs are unavailable. Choose again or check file size and UTF8 encoding." : "Scan complete. Review findings and decide rules for new keys."
        }
    }
    func refreshStale() {
        guard !sampleMode, !scanning, let index = live.projects.firstIndex(where: { $0.id == live.pinned }), live.projects[index].lastScan != nil else { return }
        let files = [live.projects[index].template].compactMap { $0 } + live.projects[index].environments
        if files.contains(where: { FileAccess.changed($0) }) { live.projects[index].stale = true; save() }
    }
    func copyReport() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string); reportCopied = true }
    func clearData() {
        generation = UUID(); scanning = false; live = SavedState(); sample = SampleFixtures.project(); sampleMode = false
        do {
            if FileManager.default.fileExists(atPath: stateURL.path) { try FileManager.default.removeItem(at: stateURL) }
            let sampleState = stateURL.deletingLastPathComponent().appendingPathComponent("sample.json")
            if FileManager.default.fileExists(atPath: sampleState.path) { try FileManager.default.removeItem(at: sampleState) }
            let fixtures = stateURL.deletingLastPathComponent().appendingPathComponent("Sample")
            if FileManager.default.fileExists(atPath: fixtures.path) { try FileManager.default.removeItem(at: fixtures) }
            notice = "Local projects, rules and bookmarks cleared. Source files were kept."
        } catch { notice = "Local data could not be removed. Try again." }
    }
    func applyAppearance() { NSApp?.appearance = appearance == "Dark" ? NSAppearance(named: .darkAqua) : appearance == "Light" ? NSAppearance(named: .aqua) : nil }
}
