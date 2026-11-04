import AppKit
import SwiftUI
import CostBarCore

/// Multi-account workflow. Each account has its own key (separate Keychain service), report, failure, refresh task and generation.
/// The original single-provider flow in `AppModel` is untouched and its Keychain items are never read here.
@MainActor
final class AccountsModel: ObservableObject {
    static let shared = AccountsModel()
    nonisolated static let keychainService = (Bundle.main.bundleIdentifier ?? "com.unfinalized.costbar") + ".accounts.credentials"
    @Published private(set) var workspace: AccountWorkspace
    @Published private(set) var refreshing: Set<String> = []
    @Published var message: String?
    /// Number of key operations in flight. Overlapping operations keep the busy state until the last one ends.
    @Published private(set) var keyOperations = 0
    var accessingKeys: Bool { keyOperations > 0 }
    @Published private(set) var sample = false
    private var liveWorkspace: AccountWorkspace?
    private let store: AccountStore
    private let keys: AsyncKeyStore
    private let clock: () -> Date
    private let fetchSpend: (Provider, String, Date) async throws -> SpendSnapshot
    private var jobs: [String: Task<Void, Never>] = [:]
    private var generations: [String: UUID] = [:]
    private var loop: Task<Void, Never>?
    private var window: NSWindow?

    init(store: AccountStore = AccountStore(),
         keys: AsyncKeyStore = AsyncKeyStore(store: KeyStore(service: AccountsModel.keychainService)),
         clock: @escaping () -> Date = Date.init,
         fetch: @escaping (Provider, String, Date) async throws -> SpendSnapshot = { provider, key, date in
             try await ProviderClient().fetch(provider: provider, key: key, now: date)
         }) {
        self.store = store; self.keys = keys; self.clock = clock; self.fetchSpend = fetch
        workspace = store.load()
    }

    // MARK: Derived state
    var now: Date { clock() }
    var selectedAccount: ProviderAccount? { workspace.selectedAccountID.flatMap(workspace.account) ?? workspace.accounts.first }
    func status(_ account: ProviderAccount) -> AccountStatus {
        AccountStatus.evaluate(account: account, report: workspace.reports[account.id], failure: workspace.failures[account.id], now: clock())
    }
    func eligibility(_ account: ProviderAccount) -> EligibilitySummary {
        GrantLedger.summary(grants: workspace.grants, accountID: account.id, workload: account.selectedWorkload, now: clock())
    }
    func grants(_ account: ProviderAccount) -> [CreditGrant] {
        workspace.grants.filter { $0.accountID == account.id }.sorted { $0.expiresAt < $1.expiresAt }
    }
    var summaryLine: String {
        let reporting = workspace.accounts.filter { $0.connection != .manualOnly }
        let current = reporting.filter { status($0).state == .current }.count
        let manual = workspace.accounts.count - reporting.count
        return "\(sample ? "Sample · " : "")\(workspace.accounts.count) accounts · \(current) of \(reporting.count) reporting current" + (manual > 0 ? " · \(manual) manual" : "")
    }

    // MARK: Lifecycle
    func start() {
        guard loop == nil, !sample else { return }
        refreshAll()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                self?.objectWillChange.send()
                self?.refreshAll()
            }
        }
    }
    func stop() {
        loop?.cancel(); loop = nil
        for id in Array(jobs.keys) { cancel(id) }
    }
    private func persist() {
        guard !sample else { return }
        do { try store.save(workspace) } catch { message = "Account data could not be saved: \(error.localizedDescription)" }
    }
    func select(_ id: String) { guard workspace.account(id) != nil else { return }; workspace.selectedAccountID = id; persist() }

    // MARK: Accounts and keys
    @discardableResult
    func addAccount(provider: Provider, label: String, key: String) async -> Bool {
        guard !sample else { message = AccountInputError.sampleReadOnly.localizedDescription; return false }
        guard workspace.accounts.count < AccountWorkspace.maxAccounts else { message = AccountInputError.tooManyAccounts.localizedDescription; return false }
        keyOperations += 1
        defer { keyOperations -= 1 }
        do {
            let normalized = try ProviderClient.normalizedKey(key)
            let count = workspace.accounts.filter { $0.provider == provider }.count + 1
            let account = ProviderAccount(provider: provider, label: ProviderAccount.cleanLabel(label, fallback: "\(provider.name) account \(count)"), createdAt: clock())
            try await keys.save(normalized, account: account.id)
            guard workspace.accounts.count < AccountWorkspace.maxAccounts else {
                try? await keys.delete(account.id)          // another add finished while the key was being saved
                throw AccountInputError.tooManyAccounts
            }
            workspace.accounts.append(account)
            workspace.selectedAccountID = account.id
            persist()
            message = "Key for \(account.label) saved in its own Keychain item. Requesting the first report…"
            refresh(account.id)
            return true
        } catch { message = error.localizedDescription; return false }
    }
    /// Manual-only account: no key, no Keychain operation, no network request. Personal Anthropic accounts cannot use the Admin API.
    @discardableResult
    func addManualAccount(provider: Provider, label: String) -> Bool {
        guard !sample else { message = AccountInputError.sampleReadOnly.localizedDescription; return false }
        guard workspace.accounts.count < AccountWorkspace.maxAccounts else { message = AccountInputError.tooManyAccounts.localizedDescription; return false }
        let count = workspace.accounts.filter { $0.provider == provider }.count + 1
        let account = ProviderAccount(provider: provider, label: ProviderAccount.cleanLabel(label, fallback: "\(provider.name) manual account \(count)"),
                                      createdAt: clock(), connection: .manualOnly)
        workspace.accounts.append(account)
        workspace.selectedAccountID = account.id
        persist()
        message = "Manual-only account added. No key was stored and no request was made. You can add a reporting key later; the account keeps its identity."
        return true
    }
    @discardableResult
    func replaceKey(_ id: String, key: String) async -> Bool {
        guard !sample, workspace.account(id) != nil else { message = AccountInputError.accountMissing.localizedDescription; return false }
        keyOperations += 1
        defer { keyOperations -= 1 }
        do {
            cancel(id)
            try await keys.save(key, account: id)
            guard let index = workspace.accounts.firstIndex(where: { $0.id == id }) else { throw AccountInputError.accountMissing }
            workspace.accounts[index].connection = .connected
            workspace.failures[id] = nil
            persist()
            message = "Key replaced for this account only."
            refresh(id)
            return true
        } catch { message = error.localizedDescription; return false }
    }
    /// Removes the key and stops refreshing. The last observed report and manual records stay, labelled unavailable.
    func disconnect(_ id: String) async {
        guard !sample, let before = workspace.account(id), before.connection == .connected else { return }
        keyOperations += 1
        defer { keyOperations -= 1 }
        cancel(id)
        do {
            try await keys.delete(id)
            // The actor is reentrant: find the account again by ID instead of trusting an index from before the await.
            guard let index = workspace.accounts.firstIndex(where: { $0.id == id }) else { return }
            workspace.accounts[index].connection = .disconnected
            workspace.failures[id] = nil
            persist()
            message = "Disconnected. The key was deleted; the last observation stays, labelled unavailable."
        } catch { message = error.localizedDescription }
    }
    func removeAccount(_ id: String) async {
        guard !sample, workspace.account(id) != nil else { return }
        keyOperations += 1
        defer { keyOperations -= 1 }
        cancel(id)
        do {
            if workspace.account(id)?.connection != .manualOnly { try await keys.delete(id) }
            workspace.removeAccount(id)
            persist()
            message = "Account, key, cached report and manual records removed."
        } catch { message = error.localizedDescription }
    }

    // MARK: Refresh
    func refreshAll() { for account in workspace.accounts where account.connection == .connected { refresh(account.id) } }
    func refresh(_ id: String) {
        guard !sample, let account = workspace.account(id), account.connection == .connected, !refreshing.contains(id) else { return }
        refreshing.insert(id)
        let started = clock(), generation = UUID(), provider = account.provider
        generations[id] = generation
        jobs[id] = Task { [weak self] in
            guard let self else { return }
            defer { if generations[id] == generation { refreshing.remove(id); jobs[id] = nil } }
            do {
                guard let key = try await keys.read(id) else { throw SpendError.authentication }
                try Task.checkCancellation()
                let result = try await fetchSpend(provider, key, started)
                guard !Task.isCancelled, generations[id] == generation, workspace.account(id)?.connection == .connected else { return }
                guard result.provider == provider else { throw SpendError.invalidResponse }
                workspace.reports[id] = AccountReport(snapshot: result)
                workspace.failures[id] = nil
                persist()
            } catch {
                guard !Task.isCancelled, !(error is CancellationError), generations[id] == generation, workspace.account(id) != nil else { return }
                workspace.failures[id] = AccountFailure.classify(error, at: clock())
                persist()
            }
        }
    }
    private func cancel(_ id: String) {
        generations[id] = UUID()
        jobs[id]?.cancel(); jobs[id] = nil
        refreshing.remove(id)
    }

    // MARK: Workload, grants, debt, allowance
    func setWorkload(_ workload: Workload, for id: String) {
        guard let index = workspace.accounts.firstIndex(where: { $0.id == id }) else { return }
        workspace.accounts[index].selectedWorkload = workload; persist()
    }
    @discardableResult
    func addGrant(accountID: String, balance: String, expiresAt: Date, eligible: Set<Workload>, kind: GrantKind, sourceLabel: String, observedAt: Date) -> Bool {
        do {
            guard workspace.account(accountID) != nil else { throw AccountInputError.accountMissing }
            let grant = try CreditGrant.validated(accountID: accountID, balanceText: balance, expiresAt: expiresAt, eligible: eligible, kind: kind,
                                                  sourceLabel: sourceLabel, observedAt: observedAt, now: clock())
            workspace.grants.append(isSampleAccount(accountID) ? { var g = grant; g.isSample = true; return g }() : grant)
            persist()
            message = eligible.isEmpty ? "Grant saved with unknown eligibility. It counts toward no workload until you mark one." : "Grant saved."
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func removeGrant(_ id: UUID) { workspace.grants.removeAll { $0.id == id }; persist() }
    @discardableResult
    func saveDebt(accountID: String, text: String, observedAt: Date) -> Bool {
        guard let index = workspace.accounts.firstIndex(where: { $0.id == accountID }) else { message = AccountInputError.accountMissing.localizedDescription; return false }
        do {
            let value = try Amounts.parseUSD(text, field: "Debt")
            guard observedAt <= clock() else { throw AccountInputError.futureObservation }
            workspace.accounts[index].debt = value == 0 ? nil : DebtRecord(amountUSD: value, observedAt: observedAt)
            persist(); message = value == 0 ? "Debt record cleared." : "Debt saved. It is shown separately and is never subtracted from credits."
            return true
        } catch { message = error.localizedDescription; return false }
    }
    @discardableResult
    func saveAllowance(accountID: String, percent: String, resetsAt: Date, observedAt: Date, label: String) -> Bool {
        do {
            guard workspace.account(accountID) != nil else { throw AccountInputError.accountMissing }
            var value = try AllowanceObservation.validated(percentText: percent, resetsAt: resetsAt, observedAt: observedAt, label: label, now: clock())
            value.isSample = isSampleAccount(accountID)
            workspace.allowances[accountID] = value
            persist(); message = "Manual allowance observation saved. It is not an official quota."
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func clearAllowance(_ id: String) { workspace.allowances[id] = nil; persist() }
    private func isSampleAccount(_ id: String) -> Bool { workspace.account(id)?.isSample == true }

    // MARK: Log estimate
    @discardableResult
    func importLog(accountID: String, url: URL) -> Bool {
        do { return try storeEstimate(LogEstimator.read(url: url, now: clock()), accountID: accountID) }
        catch { message = error.localizedDescription; return false }
    }
    @discardableResult
    func importLog(accountID: String, data: Data) -> Bool {
        do { return try storeEstimate(LogEstimator.estimate(data: data, now: clock()), accountID: accountID) }
        catch { message = error.localizedDescription; return false }
    }
    private func storeEstimate(_ estimate: LogEstimate, accountID: String) throws -> Bool {
        guard workspace.account(accountID) != nil else { throw AccountInputError.accountMissing }
        var value = estimate
        value.isSample = isSampleAccount(accountID)
        workspace.logEstimates[accountID] = value
        persist()
        message = "Estimated \(estimate.totalTokens) tokens from \(estimate.recordsCounted) log records. Only totals were kept; the file path was not stored."
        return true
    }
    func clearLogEstimate(_ id: String) { workspace.logEstimates[id] = nil; persist() }
    @discardableResult
    func saveTokenBudget(accountID: String, text: String) -> Bool {
        guard let index = workspace.accounts.firstIndex(where: { $0.id == accountID }) else { return false }
        if text.trimmingCharacters(in: .whitespaces).isEmpty { workspace.accounts[index].tokenBudget = nil; persist(); return true }
        do { workspace.accounts[index].tokenBudget = try LogEstimator.parseBudget(text); persist(); message = "Token budget saved. It is your own target, not a provider limit."; return true }
        catch { message = error.localizedDescription; return false }
    }

    // MARK: Export
    func exportData() throws -> Data { try RedactedExporter.data(workspace, now: clock(), synthetic: sample) }
    func export(to url: URL) -> Bool {
        do { try exportData().write(to: url, options: .atomic); message = "Redacted report saved. CostBar did not send it anywhere."; return true }
        catch { message = "The report could not be saved: \(error.localizedDescription)"; return false }
    }

    // MARK: Sample
    func enterSample() {
        guard !sample, !accessingKeys else { return }
        stop()
        liveWorkspace = workspace
        sample = true
        workspace = AccountSample.workspace(now: clock())
        message = "SAMPLE · synthetic accounts only. No key, network request or private data is involved."
    }
    func leaveSample() {
        guard sample, let live = liveWorkspace else { return }
        sample = false
        workspace = live
        liveWorkspace = nil
        message = nil
        start()
    }

    // MARK: Window
    func openWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "CostBar Accounts & Credits"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: AccountsView(model: self))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Internal launch flag: opens only the synthetic Accounts window. It starts neither provider flow and reads no Keychain item.
enum AccountsLaunch {
    static let sampleFlag = "--accounts-sample"
    static func sampleRequested(_ arguments: [String] = CommandLine.arguments) -> Bool { arguments.contains(sampleFlag) }
    @MainActor @discardableResult
    static func handle(arguments: [String] = CommandLine.arguments, model: AccountsModel? = nil, open: () -> Void) -> Bool {
        guard sampleRequested(arguments) else { return false }
        (model ?? AccountsModel.shared).enterSample()
        open()
        return true
    }
}
