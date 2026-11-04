import AppKit
import SwiftUI
import ServiceManagement
import PortSenseCore

@MainActor
final class AppState: ObservableObject {
    @Published var power: PowerSnapshot?
    @Published var connections = ConnectionSnapshot(usb: [], thunderbolt: [])
    @Published var powerError: String?
    @Published var connectionError: String?
    @Published var history = WattageHistory()
    @Published var refreshing = false
    @Published var selectedTab = InspectorTab.power
    @Published var ratedWatts: Double {
        didSet { UserDefaults.standard.set(ratedWatts, forKey: "chargerRatingWatts") }
    }
    @Published var showBuiltIn: Bool {
        didSet { UserDefaults.standard.set(showBuiltIn, forKey: "showBuiltInDevices") }
    }
    @Published private(set) var isSample = false
    @Published private var sampleRating: Double = 100
    private let reader: @Sendable () async -> SystemReadings
    private var generation = 0
    private var pollTask: Task<Void, Never>?
    private var refreshingTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var privacyWindow: NSWindow?
    private var supportWindow: NSWindow?
    private var notifications: SystemNotifications?
    private var pendingHardwareEvent = false
    @Published private(set) var notificationErrors: [String] = []

    init(usePreferences: Bool = true, reader: @escaping @Sendable () async -> SystemReadings = { await SystemReadings.load() }) {
        self.reader = reader
        let storedRating = UserDefaults.standard.double(forKey: "chargerRatingWatts")
        ratedWatts = usePreferences && storedRating.isFinite && (0...500).contains(storedRating) ? storedRating : 0
        showBuiltIn = usePreferences && UserDefaults.standard.bool(forKey: "showBuiltInDevices")
        // Initialization performs no system reads; start() schedules work off the main actor.
    }
    var verdict: ChargerVerdict {
        ChargerVerdict.evaluate(supply: power?.supply ?? .unknown, watts: power?.adapter?.watts, rating: effectiveRating)
    }
    var visibleUSB: [USBDevice] { connections.usb.filter { showBuiltIn || !$0.isBuiltIn } }
    var effectiveRating: Double { isSample ? sampleRating : ratedWatts }
    func setChargerRating(_ value: Double) {
        let valid = min(500, max(0, value.isFinite ? value : 0))
        if isSample { sampleRating = valid } else { ratedWatts = valid }
    }
    var menuText: String { ReadingFormat.menuValue(power) }
    var statusAccessibilityLabel: String {
        ReadingFormat.statusAccessibilityLabel(power, error: powerError, sample: isSample)
    }

    func start() {
        guard pollTask == nil, !isSample else { return }
        notifications = SystemNotifications { [weak self] event in
            Task { @MainActor [weak self] in self?.hardwareChanged(event) }
        }
        notifications?.start()
        notificationErrors = notifications?.errors ?? []
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 15_000_000_000) }
                catch { return }
                guard let self else { return }
                self.refresh(periodic: true)
            }
        }
    }
    func stop() {
        notifications?.stop(); notifications = nil
        pendingHardwareEvent = false
        notificationErrors = []
        generation += 1
        pollTask?.cancel(); pollTask = nil
        refreshingTask?.cancel(); refreshingTask = nil
        refreshing = false
    }
    deinit { pollTask?.cancel(); refreshingTask?.cancel() }

    func hardwareChanged(_ event: HardwareEvent) {
        guard !isSample else { return }
        if refreshing { pendingHardwareEvent = true }
        else { refresh() }
    }

    @discardableResult
    func refresh(periodic: Bool = false) -> Task<Void, Never>? {
        guard !refreshing else { return refreshingTask }
        if isSample {
            let snapshot = SampleReadings.power()
            power = snapshot
            powerError = nil; connectionError = nil
            connections = SampleReadings.connections
            history.record(.success(snapshot), date: snapshot.date, periodic: periodic)
            return nil
        }
        refreshing = true
        let currentGeneration = generation
        let reader = reader
        refreshingTask = Task { [weak self] in
            let readings = await reader()
            guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
            self.history.record(readings.power, date: readings.date, periodic: periodic)
            switch readings.power {
            case .success(let snapshot): self.power = snapshot; self.powerError = nil
            case .failure(let error): self.power = nil; self.powerError = error.localizedDescription
            }
            switch readings.connections {
            case .success(let snapshot): self.connections = snapshot; self.connectionError = nil
            case .failure(let error): self.connectionError = error.localizedDescription
            }
            self.refreshing = false
            if self.pendingHardwareEvent {
                self.pendingHardwareEvent = false
                self.refresh()
            }
        }
        return refreshingTask
    }
    func setSample(_ enabled: Bool) {
        guard enabled != isSample else { return }
        stop()
        isSample = enabled
        powerError = nil; connectionError = nil
        history = WattageHistory()
        if enabled {
            sampleRating = 100
            power = SampleReadings.power()
            connections = SampleReadings.connections
            history = SampleReadings.history()
        } else {
            power = nil
            connections = ConnectionSnapshot(usb: [], thunderbolt: [])
            start()
        }
    }
    func clearHistory() {
        history = WattageHistory()
        if let power { history.append(WattageSample(snapshot: power)) }
    }
    func openPrivacy() {
        if privacyWindow == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "PortSense Privacy Policy"
            window.contentViewController = NSHostingController(rootView: PrivacyPolicyView())
            window.isReleasedWhenClosed = false
            window.center()
            privacyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        privacyWindow?.makeKeyAndOrderFront(nil)
    }
    func openPage(_ page: PortPage) {
        switch PortLinks.destination(page) {
        case .web(let url):
            if !NSWorkspace.shared.open(url) { openLocalPage(page) }
        case .local: openLocalPage(page)
        }
    }
    func openLocalPage(_ page: PortPage) {
        if page == .privacy { openPrivacy(); return }
        if supportWindow == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = page.title
            window.contentViewController = NSHostingController(rootView: LocalPageView(page: page))
            window.isReleasedWhenClosed = false
            window.center()
            supportWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        supportWindow?.makeKeyAndOrderFront(nil)
    }
    func openSettings() {
        if settingsWindow == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "PortSense Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

enum InspectorTab: String, CaseIterable {
    case power = "Power", connections = "Connections", history = "History"
}

@MainActor
final class LoginPreference: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var error: String?
    @Published var needsApproval = SMAppService.mainApp.status == .requiresApproval
    func update(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            sync()
            error = nil
        } catch {
            self.error = "Launch at Login could not be changed: \(error.localizedDescription)"
            sync()
        }
    }
    func sync() {
        enabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }
}
