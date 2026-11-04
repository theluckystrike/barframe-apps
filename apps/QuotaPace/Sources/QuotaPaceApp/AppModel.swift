import AppKit
import SwiftUI
import ServiceManagement
import QuotaPaceCore

@MainActor
final class AppModel: ObservableObject {
    @Published var selected: Provider { didSet { if !sampleMode { preferences.selected = selected } } }
    @Published var grants: [Provider: FolderGrant] = [:]
    @Published var limits: [Provider: Limits] = [:]
    @Published var caches: [Provider: CachedUsage] = [:]
    @Published var errors: [Provider: String] = [:]
    @Published var warnings: [Provider: String] = [:]
    @Published var isRefreshing = false
    @Published var clock = Date()
    @Published var loginEnabled = LoginState(SMAppService.mainApp.status).isRegistered
    @Published var loginError: String?
    let preferences: Preferences
    private let service = ScanService()
    let refreshTimer = RefreshTimer()
    private var scanTask: Task<Void, Never>?
    private var paceWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var generation: [Provider: UUID] = [:]
    @Published private(set) var sampleMode: Bool

    init(sampleMode: Bool = false, preferences: Preferences = Preferences()) {
        self.preferences = preferences
        self.sampleMode = sampleMode
        selected = sampleMode ? .claude : preferences.selected
        if !sampleMode {
            for provider in Provider.allCases {
                grants[provider] = preferences.grant(for: provider)
                limits[provider] = preferences.limits(for: provider)
                caches[provider] = preferences.cache(for: provider)
                generation[provider] = UUID()
            }
        }
    }
    func start() {
        guard !refreshTimer.isRunning else { return }
        refresh()
        refreshTimer.start { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stop() {
        refreshTimer.stop()
        scanTask?.cancel(); scanTask = nil
        for provider in Provider.allCases { generation[provider] = UUID() }
        isRefreshing = false
    }
    deinit { scanTask?.cancel() }
    func setSampleMode(_ enabled: Bool) {
        guard sampleMode != enabled else { return }
        let wasRunning = refreshTimer.isRunning
        stop()
        sampleMode = enabled
        grants = [:]; caches = [:]; errors = [:]; warnings = [:]; limits = [:]
        clock = Date()
        if enabled {
            do { try loadSampleData() }
            catch { errors[selected] = "Sample data could not be loaded. Try Sample mode again." }
        } else {
            selected = preferences.selected
            for provider in Provider.allCases {
                grants[provider] = preferences.grant(for: provider)
                limits[provider] = preferences.limits(for: provider)
                caches[provider] = preferences.cache(for: provider)
            }
        }
        Task { [service] in
            for provider in Provider.allCases { await service.clear(provider: provider) }
        }
        if wasRunning { start() }
    }
    func summary(_ window: UsageWindow, provider: Provider? = nil) -> WindowSummary {
        let provider = provider ?? selected
        return WindowSummary.calculate(samples: caches[provider]?.samples ?? [], window: window,
                                       limit: limits[provider]?[window] ?? 0, now: clock)
    }
    var menuValue: String {
        guard grants[selected] != nil || sampleMode, let fraction = summary(.fiveHours).fraction else { return "" }
        let percent = (fraction * 100).rounded()
        return percent > 999 ? ">999%" : "\(Int(percent))%"
    }
    func chooseFolder(for provider: Provider) {
        guard !sampleMode else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.title = "Connect \(provider.title) logs"
        panel.message = "Choose \(provider.folderHint). QuotaPace reads token usage locally and does not edit logs."
        panel.prompt = "Connect folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let grant = try FolderGrant(url: url)
            generation[provider] = UUID()
            grants[provider] = grant; preferences.setGrant(grant, for: provider)
            caches[provider] = nil; preferences.setCache(nil, for: provider)
            errors[provider] = nil; warnings[provider] = nil
            refresh()
        } catch { errors[provider] = error.localizedDescription }
    }
    func disconnect(_ provider: Provider) {
        guard !sampleMode else { return }
        generation[provider] = UUID()
        grants[provider] = nil; caches[provider] = nil; errors[provider] = nil; warnings[provider] = nil
        preferences.setGrant(nil, for: provider); preferences.setCache(nil, for: provider)
        Task { await service.clear(provider: provider) }
    }
    func saveLimits(_ value: Limits, for provider: Provider) {
        limits[provider] = value
        if !sampleMode { preferences.setLimits(value, for: provider) }
    }
    func refresh() {
        clock = Date()
        if sampleMode { try? loadSampleData(preserveLimits: true) }
        guard !sampleMode, !isRefreshing else { return }
        isRefreshing = true
        let requested = grants
        let versions = generation
        scanTask = Task {
            for provider in Provider.allCases {
                guard !Task.isCancelled else { return }
                guard let grant = requested[provider] else { continue }
                do {
                    let (scan, refreshed) = try await service.scan(grant: grant, provider: provider)
                    guard !Task.isCancelled, generation[provider] == versions[provider] else { continue }
                    let now = Date()
                    let cache = CachedUsage(samples: scan.samples.filter { $0.date > now.addingTimeInterval(-7 * 86400) }, scannedAt: now, files: scan.files)
                    caches[provider] = cache; preferences.setCache(cache, for: provider)
                    errors[provider] = nil
                    var issues = scan.warnings
                    if scan.malformedLines > 0 { issues.insert("Skipped \(scan.malformedLines) invalid log lines.", at: 0) }
                    warnings[provider] = issues.isEmpty ? nil : issues.joined(separator: " ")
                    if let refreshed { grants[provider] = refreshed; preferences.setGrant(refreshed, for: provider) }
                } catch {
                    if !Task.isCancelled, generation[provider] == versions[provider] { errors[provider] = error.localizedDescription }
                }
            }
            guard !Task.isCancelled else { return }
            clock = Date(); isRefreshing = false; scanTask = nil
            // A folder may have been changed while an earlier scan was in flight.
            if generation != versions { refresh() }
        }
    }
    func refreshLoginStatus() {
        let state = LoginState(SMAppService.mainApp.status)
        loginEnabled = state.isRegistered
        loginError = state.needsApproval ? "Approve QuotaPace in system Login Items, or turn this toggle off to cancel." : nil
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            if LoginState(SMAppService.mainApp.status).needsApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { refreshLoginStatus(); loginError = error.localizedDescription }
    }
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 530), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "QuotaPace Settings"
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false; window.center()
            settingsWindow = window
        }
        refreshLoginStatus()
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func showPaceDetails() {
        if paceWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "QuotaPace Pace Details"
            window.contentView = NSHostingView(rootView: PaceDetailsView(model: self))
            window.isReleasedWhenClosed = false; window.center()
            paceWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); paceWindow?.makeKeyAndOrderFront(nil)
    }
    func loadSampleData(preserveLimits: Bool = false) throws {
        let anchor = JSONLParser.date("2026-10-12T10:00:00Z")!
        for provider in Provider.allCases {
            let url = try FixtureFiles.url(provider.rawValue)
            var parser = JSONLParser(provider: provider, sourceID: "sample")
            let data = try Data(contentsOf: url)
            for line in data.split(separator: 10) { parser.ingest(Data(line)) }
            let shifted = parser.samples.values.map { TokenSample(id: $0.id, date: $0.date.addingTimeInterval(clock.timeIntervalSince(anchor)), tokens: $0.tokens * 2500) }
            caches[provider] = CachedUsage(samples: shifted, scannedAt: clock, files: 1)
            if !preserveLimits { limits[provider] = Limits(fiveHours: 45_000_000, sevenDays: 200_000_000) }
        }
    }
}

enum FixtureFiles {
    static func url(_ name: String, extension ext: String = "jsonl") throws -> URL {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            let url = resources.appendingPathComponent("QuotaPace_QuotaPaceApp.bundle/Resources/\(name).\(ext)")
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw CocoaError(.fileReadNoSuchFile) }
            return url
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}

struct LoginState {
    let isRegistered: Bool
    let needsApproval: Bool
    init(_ status: SMAppService.Status) {
        isRegistered = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
}
