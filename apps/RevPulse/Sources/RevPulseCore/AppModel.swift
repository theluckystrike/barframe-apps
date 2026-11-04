import Foundation
import Combine
import ServiceManagement

@MainActor
public final class AppModel: ObservableObject {
    public static let refreshIntervals: [Double] = [60, 300, 900, 1800]
    public static let defaultGoalCents = 10_000
    @Published public private(set) var snapshot: Revenue.Snapshot?
    @Published public private(set) var sampleMode: Bool
    @Published public private(set) var isLoading = false
    @Published public var errorText: String?
    @Published public var goalCents: Int {
        didSet {
            defaults.set(goalCents, forKey: Self.goalKey)
            if sampleMode { snapshot = SampleData.snapshot(goalCents: goalCents) }
            else { snapshot?.goalCents = goalCents }
        }
    }
    @Published public var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Self.intervalKey); if started { schedule() } }
    }
    @Published public private(set) var launchAtLogin: Bool
    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Self.notifyKey) }
    }
    @Published public var failedPaymentNotificationsEnabled: Bool {
        didSet { defaults.set(failedPaymentNotificationsEnabled, forKey: Self.failedNotifyKey) }
    }
    let defaults: UserDefaults
    let keyStore: KeyStore
    var client: StripeClient?
    private let clientFactory: (String) -> StripeClient
    private let sleep: (Double) async throws -> Void
    private let loginAction: (Bool) throws -> Void
    private let post: (String, String) async -> Void
    private var refreshTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?
    private var generation = UUID()
    private var started: Bool
    private var history: NotificationHistory
    public static let goalKey = "goalCents"
    public static let intervalKey = "refreshInterval"
    public static let loginKey = "launchAtLogin"
    public static let notifyKey = "firstSaleNotificationsEnabled"
    public static let failedNotifyKey = "failedPaymentNotificationsEnabled"
    public static let historyKey = "notificationHistory"
    public init(defaults: UserDefaults = .standard, keyStore: KeyStore = KeyStore(), start: Bool = true,
                clientFactory: @escaping (String) -> StripeClient = { StripeClient(key: $0) },
                sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
                loginStatus: Bool? = nil,
                loginAction: @escaping (Bool) throws -> Void = { enabled in
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                }, post: @escaping (String, String) async -> Void = { await Notifier.post(title: $0, body: $1) }) {
        self.defaults = defaults; self.keyStore = keyStore; self.clientFactory = clientFactory
        self.sleep = sleep; self.loginAction = loginAction; self.post = post; self.started = start
        let key = keyStore.load()
        sampleMode = key == nil
        goalCents = defaults.object(forKey: Self.goalKey) as? Int ?? Self.defaultGoalCents
        let interval = defaults.object(forKey: Self.intervalKey) as? Double ?? 300
        refreshInterval = Self.refreshIntervals.contains(interval) ? interval : 300
        launchAtLogin = loginStatus ?? (SMAppService.mainApp.status == .enabled)
        notificationsEnabled = defaults.bool(forKey: Self.notifyKey)
        failedPaymentNotificationsEnabled = defaults.bool(forKey: Self.failedNotifyKey)
        history = NotificationHistory(tokens: Set(defaults.stringArray(forKey: Self.historyKey) ?? []))
        if let key { client = clientFactory(key) }
        if sampleMode { snapshot = SampleData.snapshot(goalCents: goalCents) }
        else if start { beginRefresh(); schedule() }
    }
    deinit { refreshTask?.cancel(); scheduleTask?.cancel() }
    public func stop() { started = false; invalidate() }
    private func invalidate() {
        generation = UUID(); refreshTask?.cancel(); scheduleTask?.cancel(); isLoading = false
    }
    private func beginRefresh() { refreshTask = Task { [weak self] in await self?.refresh() } }
    private func schedule() {
        scheduleTask?.cancel()
        guard started, !sampleMode, client != nil else { return }
        let interval = refreshInterval, wait = sleep
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await wait(interval); try Task.checkCancellation() } catch { return }
                guard let self, !self.sampleMode else { return }
                await self.refresh()
            }
        }
    }
    public func loadSample() {
        invalidate(); sampleMode = true; errorText = nil
        snapshot = SampleData.snapshot(goalCents: goalCents)
    }
    public func setKey(_ raw: String) throws {
        let key = StripeClient.normalizedKey(raw)
        guard StripeClient.looksRestricted(key) else { throw StripeAPIError(.http(0, "Use a restricted key starting with rk_.")) }
        try keyStore.save(key)
        useSavedKey()
    }
    public func useSavedKey() {
        guard let key = keyStore.load() else { loadSample(); return }
        invalidate(); snapshot = nil; sampleMode = false; errorText = nil; client = clientFactory(key)
        beginRefresh(); schedule()
    }
    public func hasKey() -> Bool { keyStore.load() != nil }
    public func removeKey() {
        keyStore.delete(); client = nil; defaults.removeObject(forKey: Self.historyKey)
        history = NotificationHistory(); loadSample()
    }
    public func setLaunchAtLogin(_ enabled: Bool) {
        do { try loginAction(enabled); launchAtLogin = enabled; defaults.set(enabled, forKey: Self.loginKey); errorText = nil }
        catch { errorText = "Could not change launch at login: " + error.localizedDescription }
    }
    public func sendSampleNotification(failedPayment: Bool) async {
        guard sampleMode else { return }
        await post(failedPayment ? "Sample failed payment" : "Sample first sale", "Sample notification — no real payment occurred.")
    }
    public func persistSettings() {
        defaults.set(goalCents, forKey: Self.goalKey); defaults.set(refreshInterval, forKey: Self.intervalKey)
        defaults.set(notificationsEnabled, forKey: Self.notifyKey)
        defaults.set(failedPaymentNotificationsEnabled, forKey: Self.failedNotifyKey)
    }
    public func refresh() async {
        if sampleMode { snapshot = SampleData.snapshot(goalCents: goalCents); return }
        guard let client, !isLoading else { return }
        let version = generation
        isLoading = true; errorText = nil
        defer { if generation == version { isLoading = false } }
        do {
            let now = Date()
            let account = try await client.account()
            guard let currency = account.defaultCurrency, currency.count == 3 else { throw StripeAPIError(.http(0, "Account settlement currency unavailable.")) }
            let month = Self.monthStartUnix(now: now), window = Self.fetchStartUnix(now: now)
            let charges = try await client.charges(createdGTE: window)
            let customers = try await client.customers(createdGTE: month)
            let subs = try await client.subscriptions(createdGTE: month)
            let refunds = try await client.refunds(createdGTE: month)
            let movements = try await client.balanceTransactions(createdGTE: window)
            try Task.checkCancellation()
            guard generation == version, !sampleMode else { return }
            snapshot = Revenue.snapshot(charges: charges, customers: customers, subscriptions: subs,
                refunds: refunds, currency: currency, goalCents: goalCents, now: now, balanceTransactions: movements)
            await deliverNotifications(for: charges, now: now)
        } catch {
            guard generation == version, !sampleMode else { return }
            snapshot = nil // Never present stale or partial money after a failed refresh.
            errorText = error.localizedDescription
        }
    }
    public static func monthStartUnix(now: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return Int(cal.date(from: cal.dateComponents([.year, .month], from: now))!.timeIntervalSince1970)
    }
    public static func fetchStartUnix(now: Date = Date()) -> Int {
        min(monthStartUnix(now: now), Int(Revenue.dayKey(Int(now.timeIntervalSince1970)).addingTimeInterval(-6 * 86400).timeIntervalSince1970))
    }
    func deliverNotifications(for charges: [StripeCharge], now: Date) async {
        let events = history.pending(charges: charges, now: now, firstSale: notificationsEnabled, failedPayment: failedPaymentNotificationsEnabled)
        defaults.set(Array(history.tokens), forKey: Self.historyKey)
        for event in events {
            switch event {
            case .firstSaleToday: await post("First sale today", "Your first payment of the UTC day landed.")
            case .failedPayment(_, let message): await post("Failed payment", message ?? "A charge did not go through.")
            }
        }
    }
}
