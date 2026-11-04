import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import CostBarCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var preferences: Preferences
    @Published var snapshots: [Provider: SpendSnapshot] = [:]
    @Published var connected: Set<Provider> = []
    @Published var errors: [Provider: String] = [:]
    @Published var refreshing: Set<Provider> = []
    @Published var settingsMessage: String?
    @Published var notificationMessage: String?
    @Published var loginEnabled = AppModel.loginRequested(SMAppService.mainApp.status)
    @Published private(set) var sample: Bool
    @Published var accessingKeys = false
    @Published var focusCredits = false
    @Published var sampleNotificationInFlight = false
    private var liveConnected: Set<Provider> = []
    private var sampleReports: [Provider: SpendSnapshot] = [:]
    private var sampleSession = UUID().uuidString
    private let sampleKeys: AsyncKeyStore
    private let requestSampleNotification: () async throws -> Bool
    static let sampleKey = "sample-costbar-demo"
    var showingExpandedCredits: Bool { focusCredits && snapshot?.remainingCredits != nil }
    private func sampleAccount(_ provider: Provider) -> String { sampleSession + "." + provider.rawValue }
    private var livePreferences: Preferences?
    private var liveSnapshots: [Provider: SpendSnapshot] = [:]
    private var liveErrors: [Provider: String] = [:]
    private var startup: Task<Void, Never>?
    private let store = LocalStore()
    private let keys: AsyncKeyStore
    private let fetchSpend: (Provider, String, Date) async throws -> SpendSnapshot
    private let clock: () -> Date
    private var periodLoop: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var observedDay: Date
    private var loop: Task<Void, Never>?
    private var jobs: [Provider: Task<Void, Never>] = [:]
    private var generations: [Provider: UUID] = [:]
    private var settingsWindow: NSWindow?

    init(sample: Bool = false, keys: AsyncKeyStore = AsyncKeyStore(),
         clock: @escaping () -> Date = Date.init,
         sampleKeys: AsyncKeyStore = AsyncKeyStore(store: KeyStore(service: (Bundle.main.bundleIdentifier ?? "com.unfinalized.costbar") + ".sample.credentials")),
         requestSampleNotification: @escaping () async throws -> Bool = AppModel.deliverSampleNotification,
         fetch: @escaping (Provider, String, Date) async throws -> SpendSnapshot = { provider, key, date in
             try await ProviderClient().fetch(provider: provider, key: key, now: date)
         }) {
        self.sampleKeys = sampleKeys
        self.requestSampleNotification = requestSampleNotification
        self.clock = clock
        self.fetchSpend = fetch
        self.observedDay = UTCClock.day(clock())
        self.sample = sample
        self.keys = keys
        preferences = sample ? Preferences() : store.preferences()
    }
    static func loginRequested(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }
    var loginPending: Bool { SMAppService.mainApp.status == .requiresApproval }
    func enterSample(load: () throws -> [Provider: SpendSnapshot] = { try SampleData.load() }) {
        guard !sample, !accessingKeys else { return }
        do {
            let samples = try load()
            livePreferences = preferences
            liveSnapshots = snapshots
            liveErrors = errors
            liveConnected = connected
            sampleReports = samples
            sampleSession = UUID().uuidString
            connected = []
            focusCredits = false
            stop()
            sample = true
            settingsWindow?.title = "CostBar Settings · Sample"
            preferences = Preferences()
            snapshots = samples
            errors = [:]
            settingsMessage = "Sample mode · no API key or network request is needed."
            notificationMessage = nil
        } catch { settingsMessage = "Sample data could not be loaded: \(error.localizedDescription)" }
    }
    func leaveSample() {
        guard sample, !accessingKeys, !sampleNotificationInFlight else { return }
        let accounts = connected.map(sampleAccount)
        let vault = sampleKeys
        Task {
            for account in accounts {
                do { try await vault.delete(account) }
                catch { self.settingsMessage = "Sample key cleanup failed: \(error.localizedDescription)" }
            }
        }
        connected = liveConnected
        focusCredits = false
        sampleReports = [:]
        sample = false
        settingsWindow?.title = "CostBar Settings"
        preferences = livePreferences ?? store.preferences()
        snapshots = liveSnapshots
        errors = liveErrors
        settingsMessage = nil
        notificationMessage = nil
        start()
    }
    func stop() {
        startup?.cancel(); startup = nil
        loop?.cancel(); loop = nil
        periodLoop?.cancel(); periodLoop = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        for provider in Provider.allCases { cancel(provider) }
    }
    var selected: Provider { preferences.selected }
    var snapshot: SpendSnapshot? {
        guard let snapshot = snapshots[selected], snapshot.isCurrentMonth(at: displayDate), snapshot.isCurrentDay(at: displayDate) else { return nil }
        return snapshot
    }
    var displayDate: Date { sample ? snapshots[selected]?.fetchedAt ?? clock() : clock() }
    var forecast: Decimal? {
        guard let snapshot, !refreshing.contains(selected), errors[selected] == nil,
              !snapshot.isStale(at: displayDate) else { return nil }
        return snapshot.projectedUSD
    }
    var forecastText: String {
        if refreshing.contains(selected) { return "Updating…" }
        guard let snapshot, !snapshot.isStale(at: displayDate) else { return "Awaiting refresh" }
        if errors[selected] != nil { return "Incomplete report" }
        return forecast.map(Money.string) ?? "Too early to project"
    }
    var coverageText: String {
        let providers = sample ? Set(Provider.allCases) : connected
        let current = providers.filter { provider in
            guard let value = snapshots[provider] else { return false }
            return !value.isStale(at: sample ? value.fetchedAt : clock()) && errors[provider] == nil && !refreshing.contains(provider)
        }.count
        return "\(sample ? "Sample · " : "")\(current) of \(providers.count) connected providers current"
    }
    var connectionIssues: String? {
        let issues = Provider.allCases.compactMap { provider in
            errors[provider].map { "\(provider.name): \($0)" }
        }
        return issues.isEmpty ? nil : issues.joined(separator: " · ")
    }
    /// Clear pre-wake values and cancel every request generation before starting new reports.
    func reportingBoundaryChanged(wake: Bool = false) {
        guard !sample else { return }
        let day = UTCClock.day(clock())
        guard wake || day != observedDay else { return }
        observedDay = day
        for provider in Provider.allCases {
            cancel(provider)
            store.removeSnapshot(for: provider)
        }
        snapshots = [:]
        refreshAll()
    }
    var budget: Budget { preferences.budget(for: selected) }
    var warning: Bool { snapshot.map { budget.fraction(spend: $0.monthlyUSD) >= Double(budget.thresholdPercent) / 100 } ?? false }
    var state: String {
        if sample { return "Sample data" }
        if errors[selected] != nil { return snapshot == nil ? "Needs attention" : "Last known spend" }
        if let snapshot, snapshot.isStale(at: displayDate) { return "Update needed" }
        if refreshing.contains(selected) { return "Refreshing" }
        return connected.contains(selected) ? "Connected" : "Connect a provider"
    }
    func select(_ provider: Provider) {
        if selected != provider { focusCredits = false }
        preferences.selected = provider
        persist()
        if !sample, connected.contains(provider), snapshots[provider]?.isStale(at: displayDate) != false { refresh(provider) }
    }
    private func persist() {
        guard !sample else { return }
        do { try store.save(preferences) }
        catch { settingsMessage = "Settings could not be saved: \(error.localizedDescription)" }
    }
    func start() {
        guard !sample, MASLaunch.isNormal, startup == nil, loop == nil else { return }
        observedDay = UTCClock.day(clock())
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reportingBoundaryChanged(wake: true) }
        }
        periodLoop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                self?.objectWillChange.send()
                self?.reportingBoundaryChanged()
            }
        }
        startup = Task { [weak self] in
            guard let self else { return }
            for provider in Provider.allCases {
                do {
                    let key = try await keys.read(provider.rawValue)
                    guard !Task.isCancelled, !sample else { return }
                    if key != nil {
                        connected.insert(provider)
                        if let cached = store.snapshot(for: provider) { snapshots[provider] = cached }
                    }
                } catch {
                    guard !Task.isCancelled, !sample else { return }
                    errors[provider] = error.localizedDescription
                }
            }
            startup = nil
            refreshAll()
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                    self?.refreshAll()
                }
            }
        }
    }
    func refreshAll() { for provider in connected { refresh(provider) } }
    func refresh(_ provider: Provider) {
        guard !refreshing.contains(provider), connected.contains(provider) else { return }
        if sample {
            snapshots[provider] = sampleReports[provider]
            errors[provider] = nil
            settingsMessage = "Sample report refreshed locally; no network request."
            if let snapshot = snapshots[provider] { previewAlert(snapshot) }
            return
        }
        refreshing.insert(provider)
        let startedAt = clock()
        let generation = UUID()
        generations[provider] = generation
        jobs[provider] = Task { [weak self] in
            guard let self else { return }
            defer {
                if generations[provider] == generation { refreshing.remove(provider); jobs[provider] = nil }
            }
            do {
                guard let key = try await keys.read(provider.rawValue) else { throw SpendError.authentication }
                guard !Task.isCancelled, !sample else { return }
                let result = try await fetchSpend(provider, key, startedAt)
                guard !Task.isCancelled, generations[provider] == generation else { return }
                guard result.provider == provider else { throw SpendError.invalidResponse }
                guard result.isCurrentDay(at: clock()),
                      UTCClock.day(startedAt) == UTCClock.day(clock()) else {
                    cancel(provider)
                    refresh(provider)
                    return
                }
                try store.save(result)
                snapshots[provider] = result
                errors[provider] = nil
                await notifyIfNeeded(result)
            } catch {
                guard !Task.isCancelled, generations[provider] == generation else { return }
                if let urlError = error as? URLError {
                    errors[provider] = urlError.code == .notConnectedToInternet ? "You are offline. Connect to the internet and refresh." : "The provider could not be reached. Try refreshing later."
                } else { errors[provider] = error.localizedDescription }
            }
        }
    }
    private func cancel(_ provider: Provider) {
        generations[provider] = UUID()
        jobs[provider]?.cancel(); jobs[provider] = nil
        refreshing.remove(provider)
    }
    func saveKey(_ text: String, provider: Provider) async -> Bool {
        if sample {
            accessingKeys = true
            defer { accessingKeys = false }
            do {
                guard try ProviderClient.normalizedKey(text) == Self.sampleKey else { throw SpendError.invalidKey }
                let account = sampleAccount(provider)
                try await sampleKeys.save(Self.sampleKey, account: account)
                guard try await sampleKeys.read(account) == Self.sampleKey else { throw SpendError.authentication }
                connected.insert(provider)
                snapshots[provider] = sampleReports[provider]
                errors[provider] = nil
                settingsMessage = "Sample key saved and read in a separate Keychain item. Sample report connected without network."
                return true
            } catch { settingsMessage = "Sample connection: \(error.localizedDescription) Use Fill sample key."; return false }
        }
        accessingKeys = true
        defer { accessingKeys = false }
        do {
            try await keys.save(text, account: provider.rawValue)
            cancel(provider)
            connected.insert(provider)
            snapshots[provider] = nil
            store.removeSnapshot(for: provider)
            errors[provider] = nil
            settingsMessage = "Key saved in Keychain. Checking access…"
            refresh(provider)
            return true
        } catch { settingsMessage = error.localizedDescription; return false }
    }
    func removeKey(_ provider: Provider) async {
        if sample {
            accessingKeys = true
            defer { accessingKeys = false }
            do {
                try await sampleKeys.delete(sampleAccount(provider))
                connected.remove(provider)
                snapshots[provider] = nil
                errors[provider] = nil
                settingsMessage = "Sample key and displayed sample report removed. Fill sample key to reconnect."
            } catch { settingsMessage = error.localizedDescription }
            return
        }
        accessingKeys = true
        defer { accessingKeys = false }
        do {
            try await keys.delete(provider.rawValue)
            cancel(provider)
            connected.remove(provider); snapshots[provider] = nil; errors[provider] = nil
            store.removeSnapshot(for: provider)
            settingsMessage = "Key and cached spend removed."
        } catch { settingsMessage = error.localizedDescription }
    }
    func saveBudget(_ text: String, threshold: Int, provider: Provider) {
        guard let amount = Money.parseBudget(text), (1...100).contains(threshold) else {
            settingsMessage = "Enter a positive USD budget with up to two decimal places."; return
        }
        preferences.budgets[provider.rawValue] = Budget(monthlyUSD: amount, thresholdPercent: threshold)
        persist()
        settingsMessage = "Budget saved for \(provider.name)."
        if let snapshot = snapshots[provider], !snapshot.isStale(at: displayDate) {
            if sample { previewAlert(snapshot) }
            else { Task { await notifyIfNeeded(snapshot) } }
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = Self.loginRequested(SMAppService.mainApp.status)
            if SMAppService.mainApp.status == .requiresApproval {
                settingsMessage = "Allow CostBar in System Settings → General → Login Items."
                SMAppService.openSystemSettingsLoginItems()
            } else { settingsMessage = enabled ? "Launch at login enabled." : "Launch at login disabled." }
        } catch { loginEnabled = Self.loginRequested(SMAppService.mainApp.status); settingsMessage = "Launch at login could not be changed: \(error.localizedDescription)" }
    }
    func setAlerts(_ enabled: Bool) {
        if sample {
            preferences.alertsEnabled = enabled
            notificationMessage = enabled ? "Sample · alerts enabled for this preview only." : "Sample · alerts disabled."
            if enabled { for snapshot in snapshots.values { previewAlert(snapshot) } }
            return
        }
        guard enabled else { preferences.alertsEnabled = false; persist(); return }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                preferences.alertsEnabled = granted
                notificationMessage = granted ? "Alerts appear once per provider, month and budget threshold." : "Allow notifications in System Settings to receive budget alerts."
                persist()
                if granted { for snapshot in snapshots.values where !snapshot.isStale(at: displayDate) { await notifyIfNeeded(snapshot) } }
            } catch { notificationMessage = "Notification permission could not be requested: \(error.localizedDescription)" }
        }
    }
    /// Explicit UI action tests real permission and OS delivery without any provider account.
    nonisolated static func deliverSampleNotification() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Sample · CostBar budget threshold reached"
        content.body = "Sample reported spend is $25.50. This is a local notification test."
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "costbar.sample." + UUID().uuidString, content: content, trigger: nil))
        return true
    }
    func testSampleNotification() async {
        guard sample, !sampleNotificationInFlight else { return }
        sampleNotificationInFlight = true
        defer { sampleNotificationInFlight = false }
        do {
            let granted = try await requestSampleNotification()
            notificationMessage = granted ? "Sample · notification sent to macOS; banner visibility follows system settings." : "Sample · allow CostBar notifications in System Settings to test a banner."
        } catch { notificationMessage = "Sample notification failed: \(error.localizedDescription)" }
    }
    private func previewAlert(_ snapshot: SpendSnapshot) {
        guard sample, preferences.alertsEnabled,
              let id = preferences.budget(for: snapshot.provider).alertID(snapshot: snapshot),
              !preferences.deliveredAlertIDs.contains(id) else { return }
        preferences.deliveredAlertIDs.append(id)
        notificationMessage = "Sample · \(snapshot.provider.name) budget threshold reached at \(Money.string(snapshot.monthlyUSD))."
    }
    private var alertsInFlight: Set<String> = []
    private func notifyIfNeeded(_ snapshot: SpendSnapshot) async {
        guard !sample, !Task.isCancelled, !snapshot.isStale(at: clock()), errors[snapshot.provider] == nil, preferences.alertsEnabled,
              let id = preferences.budget(for: snapshot.provider).alertID(snapshot: snapshot),
              !preferences.deliveredAlertIDs.contains(id), !alertsInFlight.contains(id) else { return }
        alertsInFlight.insert(id)
        defer { alertsInFlight.remove(id) }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard !sample, !Task.isCancelled, preferences.alertsEnabled else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            notificationMessage = "Allow CostBar notifications in System Settings."; return
        }
        let content = UNMutableNotificationContent()
        content.title = "\(snapshot.provider.name) budget threshold reached"
        content.body = "Reported spend is \(Money.string(snapshot.monthlyUSD)) this UTC month. Open CostBar to review your budget."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            preferences.deliveredAlertIDs = Array((preferences.deliveredAlertIDs + [id]).suffix(60))
            persist()
        } catch { notificationMessage = "Budget alert could not be delivered: \(error.localizedDescription)" }
    }
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 590), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = sample ? "CostBar Settings · Sample" : "CostBar Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(model: self))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.title = sample ? "CostBar Settings · Sample" : "CostBar Settings"
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

private enum MASLaunch {
    static var isNormal: Bool { !CommandLine.arguments.contains("--smoke") && !CommandLine.arguments.contains("--screenshots") }
}
