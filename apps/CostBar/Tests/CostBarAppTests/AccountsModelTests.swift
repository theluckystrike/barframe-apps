import Foundation
import Testing
import CostBarCore
@testable import CostBarApp

private final class MemoryKeys: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var reads: [String] = []
    func read(_ account: String) throws -> String? { lock.withLock { reads.append(account); return values[account] } }
    func save(_ value: String, account: String) throws { lock.withLock { ops += 1; values[account] = value } }
    private var pausedAccount: String?
    private let entered = DispatchSemaphore(value: 0)
    private let proceed = DispatchSemaphore(value: 0)
    private var ops = 0
    func delete(_ account: String) throws {
        let pause = lock.withLock { () -> Bool in ops += 1; if pausedAccount == account { pausedAccount = nil; return true }; return false }
        if pause { entered.signal(); proceed.wait() }
        lock.withLock { values[account] = nil }
    }
    /// The next delete of this account blocks until `resumeDelete()`.
    func pauseDelete(of account: String) { lock.withLock { pausedAccount = account } }
    func resumeDelete() { proceed.signal() }
    func deleteEntered() async -> Bool {
        for _ in 0..<400 { if entered.wait(timeout: .now()) == .success { return true }; try? await Task.sleep(nanoseconds: 5_000_000) }
        return false
    }
    var totalOperations: Int { lock.withLock { ops + reads.count } }
    var readAccounts: [String] { lock.withLock { reads } }
    var stored: [String: String] { lock.withLock { values } }
}
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false
    private(set) var arrived = 0
    func wait() async { arrived += 1; if open { return }; await withCheckedContinuation { waiters.append($0) } }
    func release() { open = true; waiters.forEach { $0.resume() }; waiters = [] }
}
private struct FakeTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> HTTPResult
    func get(_ request: URLRequest) async throws -> HTTPResult { try await handler(request) }
}
private func costJSON(cents: Int, more: String? = nil) -> Data {
    let page = more.map { "\"has_more\":true,\"next_page\":\"\($0)\"" } ?? "\"has_more\":false,\"next_page\":null"
    return Data("{\"data\":[{\"starting_at\":\"2026-10-15T00:00:00Z\",\"ending_at\":\"2026-10-16T00:00:00Z\",\"results\":[{\"amount\":\"\(cents)\",\"currency\":\"USD\"}]}],\(page)}".utf8)
}
private let fixedNow = try! UTCClock.parse("2026-10-15T12:00:00Z")

@MainActor private struct Rig {
    let model: AccountsModel
    let keys: MemoryKeys
    let defaults: UserDefaults
    let suite: String
    init(handler: @escaping @Sendable (URLRequest) async throws -> HTTPResult, now: @escaping () -> Date = { fixedNow }) {
        suite = "costbar.accounts.test." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        keys = MemoryKeys()
        let client = ProviderClient(transport: FakeTransport(handler: handler))
        model = AccountsModel(store: AccountStore(defaults: defaults), keys: AsyncKeyStore(store: keys), clock: now,
                              fetch: { provider, key, date in try await client.fetch(provider: provider, key: key, now: date) })
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite) }
    func idle() async throws {
        for _ in 0..<400 where !model.refreshing.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(model.refreshing.isEmpty)
    }
}
private func keyOf(_ request: URLRequest) -> String { request.value(forHTTPHeaderField: "x-api-key") ?? "" }

@MainActor @Test func twoAccountsFromOneProviderStayIndependent() async throws {
    let rig = Rig { request in
        switch keyOf(request) {
        case "key-alpha": return HTTPResult(data: costJSON(cents: 250), status: 200)
        case "key-beta": return HTTPResult(data: costJSON(cents: 1000), status: 200)
        default: return HTTPResult(data: Data(), status: 401)
        }
    }
    defer { rig.cleanup() }
    #expect(await rig.model.addAccount(provider: .anthropic, label: "Alpha", key: "key-alpha"))
    try await rig.idle()
    #expect(await rig.model.addAccount(provider: .anthropic, label: "Beta", key: "key-beta"))
    try await rig.idle()
    let accounts = rig.model.workspace.accounts
    #expect(accounts.count == 2 && accounts[0].id != accounts[1].id && accounts.allSatisfy { $0.provider == .anthropic })
    #expect(rig.keys.stored[accounts[0].id] == "key-alpha" && rig.keys.stored[accounts[1].id] == "key-beta")
    #expect(rig.model.workspace.reports[accounts[0].id]?.snapshot.monthlyUSD == Decimal(string: "2.5"))
    #expect(rig.model.workspace.reports[accounts[1].id]?.snapshot.monthlyUSD == 10)
    // Separate settings.
    rig.model.setWorkload(.claudeCode, for: accounts[0].id)
    #expect(rig.model.workspace.accounts[0].selectedWorkload == .claudeCode && rig.model.workspace.accounts[1].selectedWorkload == .directAPI)
    // Separate persisted state survives a reload.
    let reloaded = AccountStore(defaults: rig.defaults).load()
    #expect(reloaded.accounts.map(\.id) == accounts.map(\.id) && reloaded.reports.count == 2)
}

@MainActor @Test func revokedKeyIsolatedAndKeepsLastReport() async throws {
    final class Revoked: @unchecked Sendable {            // plain flag: nothing ever waits on it, so it cannot deadlock
        private let lock = NSLock(); private var value = false
        var on: Bool { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
    }
    let revoked = Revoked()
    let rig = Rig { request in
        let key = keyOf(request)
        if key == "key-alpha", revoked.on { return HTTPResult(data: Data(), status: 401) }
        return HTTPResult(data: costJSON(cents: key == "key-alpha" ? 250 : 1000), status: 200)
    }
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "Alpha", key: "key-alpha"); try await rig.idle()
    _ = await rig.model.addAccount(provider: .anthropic, label: "Beta", key: "key-beta"); try await rig.idle()
    let a = rig.model.workspace.accounts[0], b = rig.model.workspace.accounts[1]
    revoked.on = true                    // the fake provider rejects key-alpha from now on
    rig.model.refreshAll(); try await rig.idle()
    let statusA = rig.model.status(a), statusB = rig.model.status(b)
    #expect(statusA.state == .unavailable && statusA.headline.contains("key rejected"))
    #expect(rig.model.workspace.reports[a.id]?.snapshot.monthlyUSD == Decimal(string: "2.5"))   // retained
    #expect(statusB.state == .current && rig.model.workspace.failures[b.id] == nil)
    #expect(rig.model.workspace.reports[b.id]?.snapshot.monthlyUSD == 10)
    // Replacing only A's key recovers A.
    #expect(await rig.model.replaceKey(a.id, key: "key-alpha-2"))
    #expect(rig.keys.stored[b.id] == "key-beta")
}

@MainActor @Test func incompletePaginationNeverReplacesCompleteReport() async throws {
    final class Mode: @unchecked Sendable { var broken = false }
    let mode = Mode()
    let rig = Rig { _ in
        mode.broken ? HTTPResult(data: costJSON(cents: 99999, more: "same-cursor"), status: 200) : HTTPResult(data: costJSON(cents: 400), status: 200)
    }
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "A", key: "key-a"); try await rig.idle()
    let id = rig.model.workspace.accounts[0].id
    mode.broken = true
    rig.model.refresh(id); try await rig.idle()
    #expect(rig.model.workspace.reports[id]?.snapshot.monthlyUSD == 4)        // partial $999.99 never shown
    #expect(rig.model.workspace.failures[id]?.kind == .transient)
    #expect(rig.model.status(rig.model.workspace.accounts[0]).state == .stale)
}

@MainActor @Test func removeDuringRefreshIsGenerationGuarded() async throws {
    let gate = Gate()
    let rig = Rig { _ in await gate.wait(); return HTTPResult(data: costJSON(cents: 500), status: 200) }
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "A", key: "key-a")
    for _ in 0..<400 where await gate.arrived == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
    #expect(await gate.arrived == 1)
    let id = rig.model.workspace.accounts[0].id
    #expect(rig.model.refreshing.contains(id))
    await rig.model.removeAccount(id)
    #expect(rig.model.refreshing.isEmpty && rig.keys.stored[id] == nil)
    await gate.release()
    try await Task.sleep(nanoseconds: 80_000_000)
    #expect(rig.model.workspace.accounts.isEmpty && rig.model.workspace.reports.isEmpty && rig.model.workspace.failures.isEmpty)
}

@MainActor @Test func disconnectCancelsInFlightFetchAndKeepsLastObservation() async throws {
    let gate = Gate()
    final class Hold: @unchecked Sendable { var on = false }
    let hold = Hold()
    let rig = Rig { _ in if hold.on { await gate.wait() }; return HTTPResult(data: costJSON(cents: 300), status: 200) }
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "A", key: "key-a"); try await rig.idle()
    let id = rig.model.workspace.accounts[0].id
    hold.on = true
    rig.model.refresh(id)
    for _ in 0..<400 where await gate.arrived == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
    await rig.model.disconnect(id)
    await gate.release()
    try await Task.sleep(nanoseconds: 80_000_000)
    #expect(rig.keys.stored[id] == nil)
    #expect(rig.model.workspace.reports[id]?.snapshot.monthlyUSD == 3)
    let status = rig.model.status(rig.model.workspace.accounts[0])
    #expect(status.state == .unavailable && status.headline.contains("disconnected"))
    rig.model.refresh(id)                                   // disconnected accounts do not refresh
    #expect(rig.model.refreshing.isEmpty)
}

@MainActor @Test func historicalLabelAfterUTCMidnight() async throws {
    final class Clock: @unchecked Sendable { var now = fixedNow }
    let clock = Clock()
    let rig = Rig(handler: { _ in HTTPResult(data: costJSON(cents: 300), status: 200) }, now: { clock.now })
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "A", key: "key-a"); try await rig.idle()
    #expect(rig.model.status(rig.model.workspace.accounts[0]).state == .current)
    clock.now = try UTCClock.parse("2026-11-01T00:00:05Z")
    let s = rig.model.status(rig.model.workspace.accounts[0])
    #expect(s.state == .stale && s.historicalNote?.contains("2026-10") == true)
}

@MainActor @Test func grantFormsValidateAndWorkloadSelectionChangesTotal() async throws {
    let rig = Rig { _ in HTTPResult(data: costJSON(cents: 1), status: 200) }
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "A", key: "key-a"); try await rig.idle()
    let id = rig.model.workspace.accounts[0].id
    let soon = fixedNow.addingTimeInterval(86400)
    #expect(!rig.model.addGrant(accountID: id, balance: "NaN", expiresAt: soon, eligible: [.directAPI], kind: .other, sourceLabel: "", observedAt: fixedNow))
    #expect(rig.model.message?.contains("non-negative") == true)
    #expect(!rig.model.addGrant(accountID: id, balance: "50", expiresAt: soon, eligible: [.claudeCode], kind: .maxPlanAPIPromotion, sourceLabel: "", observedAt: fixedNow))
    #expect(rig.model.addGrant(accountID: id, balance: "50", expiresAt: soon, eligible: [.directAPI, .agentSDK], kind: .prepaidCredit, sourceLabel: "console", observedAt: fixedNow))
    #expect(rig.model.addGrant(accountID: id, balance: "7", expiresAt: soon, eligible: [], kind: .other, sourceLabel: "", observedAt: fixedNow))
    #expect(rig.model.workspace.grants.count == 2)
    for (workload, expected) in [(Workload.directAPI, Decimal(50)), (.agentSDK, 50), (.claudeCode, 0), (.subscription, 0)] {
        rig.model.setWorkload(workload, for: id)
        #expect(rig.model.eligibility(rig.model.workspace.accounts[0]).totalUSD == expected)
    }
    #expect(rig.model.saveDebt(accountID: id, text: "8.25", observedAt: fixedNow))
    rig.model.setWorkload(.directAPI, for: id)
    #expect(rig.model.eligibility(rig.model.workspace.accounts[0]).totalUSD == 50)   // debt never netted
    #expect(!rig.model.saveDebt(accountID: id, text: "-1", observedAt: fixedNow))
    #expect(!rig.model.saveAllowance(accountID: id, percent: "140", resetsAt: soon, observedAt: fixedNow, label: ""))
    #expect(rig.model.saveAllowance(accountID: id, percent: "40", resetsAt: soon, observedAt: fixedNow, label: ""))
}

@MainActor @Test func logImportStoresTotalsOnlyAndExportIsRedacted() async throws {
    let rig = Rig { _ in HTTPResult(data: costJSON(cents: 1), status: 200) }
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "me@example.com", key: "sk-ant-admin-SECRETKEY"); try await rig.idle()
    let id = rig.model.workspace.accounts[0].id
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("costbar-model-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("private-name.jsonl")
    try Data("{\"usage\":{\"input_tokens\":1000,\"output_tokens\":500},\"prompt\":\"secret prompt text\"}\n".utf8).write(to: file)
    #expect(rig.model.importLog(accountID: id, url: file))
    #expect(rig.model.saveTokenBudget(accountID: id, text: "3000"))
    #expect(!rig.model.saveTokenBudget(accountID: id, text: "-1"))
    _ = rig.model.addGrant(accountID: id, balance: "5", expiresAt: fixedNow.addingTimeInterval(1000), eligible: [.directAPI], kind: .other, sourceLabel: "me@example.com receipt", observedAt: fixedNow)
    let persisted = String(decoding: rig.defaults.data(forKey: "accounts.workspace.v1") ?? Data(), as: UTF8.self)
    for forbidden in ["private-name", "secret prompt", dir.path, "SECRETKEY"] { #expect(!persisted.contains(forbidden)) }
    let out = dir.appendingPathComponent("export.json")
    #expect(rig.model.export(to: out))
    let text = try String(contentsOf: out, encoding: .utf8)
    for forbidden in ["me@example.com", "SECRETKEY", "sk-ant", "private-name", dir.path, id, "secret prompt", "http", "receipt"] { #expect(!text.contains(forbidden), "leaked \(forbidden)") }
    #expect(text.contains("\"inputTokens\" : 1000") && text.contains("\"kind\" : \"estimate\""))
}

@MainActor @Test func newAccountsNeverTouchLegacyKeychainItemsAndSampleIsLabelled() async throws {
    let legacy = (Bundle.main.bundleIdentifier ?? "com.unfinalized.costbar") + ".credentials"
    #expect(AccountsModel.keychainService != legacy && AccountsModel.keychainService.hasSuffix(".accounts.credentials"))
    let rig = Rig { _ in HTTPResult(data: costJSON(cents: 100), status: 200) }
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "A", key: "key-a"); try await rig.idle()
    let id = rig.model.workspace.accounts[0].id
    #expect(Set(rig.keys.readAccounts) == [id])                // only the new account ID is ever read
    rig.model.enterSample()
    #expect(rig.model.sample && rig.model.workspace.accounts.allSatisfy(\.isSample))
    #expect(!(await rig.model.addAccount(provider: .openAI, label: "x", key: "k")))
    rig.model.refreshAll(); #expect(rig.model.refreshing.isEmpty)
    #expect(try String(decoding: rig.model.exportData(), as: UTF8.self).contains("SYNTHETIC SAMPLE"))
    #expect(AccountStore(defaults: rig.defaults).load().accounts.map(\.id) == [id])    // sample was never persisted
    rig.model.leaveSample()
    #expect(!rig.model.sample && rig.model.workspace.accounts.map(\.id) == [id])
    rig.model.stop()
}

@MainActor @Test func accountLimitAndKeyValidation() async throws {
    let rig = Rig { _ in HTTPResult(data: costJSON(cents: 1), status: 200) }
    defer { rig.cleanup() }
    #expect(!(await rig.model.addAccount(provider: .anthropic, label: "", key: "has space")))
    #expect(rig.model.workspace.accounts.isEmpty && rig.keys.stored.isEmpty)
    for i in 0..<AccountWorkspace.maxAccounts { #expect(await rig.model.addAccount(provider: .openAI, label: "", key: "k\(i)")) }
    #expect(!(await rig.model.addAccount(provider: .openAI, label: "", key: "extra")))
    rig.model.stop()
    #expect(rig.model.workspace.accounts[0].label == "OpenAI account 1")
}

private final class CountingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var requests: Int { lock.withLock { count } }
    func get(_ request: URLRequest) async throws -> HTTPResult { lock.withLock { count += 1 }; throw SpendError.invalidResponse }
}

@MainActor @Test func manualOnlyAccountUsesNoKeyAndNoNetwork() async throws {
    let transport = CountingTransport()
    let suite = "costbar.manual.test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let keys = MemoryKeys()
    let client = ProviderClient(transport: transport)
    let model = AccountsModel(store: AccountStore(defaults: defaults), keys: AsyncKeyStore(store: keys), clock: { fixedNow },
                              fetch: { p, k, d in try await client.fetch(provider: p, key: k, now: d) })
    #expect(model.addManualAccount(provider: .anthropic, label: "Personal"))
    #expect(model.addManualAccount(provider: .anthropic, label: ""))
    let a = model.workspace.accounts[0], b = model.workspace.accounts[1]
    #expect(a.id != b.id && a.connection == .manualOnly && b.label == "Anthropic manual account 2")
    let soon = fixedNow.addingTimeInterval(86400)
    #expect(model.addGrant(accountID: a.id, balance: "30", expiresAt: soon, eligible: [.directAPI], kind: .promotionalCredit, sourceLabel: "", observedAt: fixedNow))
    #expect(model.saveDebt(accountID: a.id, text: "4", observedAt: fixedNow))
    #expect(model.saveAllowance(accountID: a.id, percent: "55", resetsAt: soon, observedAt: fixedNow, label: ""))
    model.refresh(a.id); model.refreshAll()
    #expect(model.refreshing.isEmpty)
    #expect(model.eligibility(a).totalUSD == 30 && model.eligibility(b).totalUSD == 0)
    #expect(model.status(a).state == .manual && model.workspace.reports.isEmpty)
    await model.removeAccount(b.id)                                   // removing a manual account touches no Keychain item
    #expect(keys.totalOperations == 0 && transport.requests == 0)
    #expect(model.workspace.accounts.map(\.id) == [a.id])
    // Later adding a reporting key keeps the same stable identity and records.
    #expect(await model.replaceKey(a.id, key: "key-later"))
    #expect(model.workspace.accounts[0].id == a.id && model.workspace.accounts[0].connection == .connected)
    #expect(model.workspace.grants.count == 1 && keys.stored[a.id] == "key-later")
    for _ in 0..<400 where !model.refreshing.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
}

@MainActor @Test func dateFormsRejectObservationsAfterNow() async throws {
    let rig = Rig { _ in HTTPResult(data: costJSON(cents: 1), status: 200) }
    defer { rig.cleanup() }
    #expect(rig.model.addManualAccount(provider: .openAI, label: "m"))
    let id = rig.model.workspace.accounts[0].id
    let soon = fixedNow.addingTimeInterval(86400)
    for offset: TimeInterval in [1, 43_200, 86_400] {
        let future = fixedNow.addingTimeInterval(offset)
        #expect(!rig.model.addGrant(accountID: id, balance: "5", expiresAt: soon, eligible: [.directAPI], kind: .other, sourceLabel: "", observedAt: future))
        #expect(!rig.model.saveDebt(accountID: id, text: "5", observedAt: future))
        #expect(!rig.model.saveAllowance(accountID: id, percent: "5", resetsAt: future.addingTimeInterval(60), observedAt: future, label: ""))
    }
    #expect(rig.model.workspace.grants.isEmpty && rig.model.workspace.accounts[0].debt == nil && rig.model.workspace.allowances.isEmpty)
    #expect(rig.model.saveDebt(accountID: id, text: "5", observedAt: fixedNow))
}

@MainActor @Test func disconnectSurvivesAccountRemovedDuringKeyDelete() async throws {
    let rig = Rig { _ in HTTPResult(data: costJSON(cents: 100), status: 200) }
    defer { rig.cleanup() }
    for (label, key) in [("A", "key-a"), ("B", "key-b"), ("C", "key-c")] {
        _ = await rig.model.addAccount(provider: .anthropic, label: label, key: key); try await rig.idle()
    }
    let ids = rig.model.workspace.accounts.map(\.id)
    // Remove an earlier account while B's delete is paused: a stale index would now point at C.
    rig.keys.pauseDelete(of: ids[1])
    let task = Task { await rig.model.disconnect(ids[1]) }
    #expect(await rig.keys.deleteEntered())
    #expect(rig.model.accessingKeys)
    await rig.model.removeAccount(ids[0])
    #expect(rig.model.accessingKeys)                       // still busy: the paused operation has not finished
    rig.keys.resumeDelete()
    await task.value
    let byID = Dictionary(uniqueKeysWithValues: rig.model.workspace.accounts.map { ($0.id, $0.connection) })
    #expect(byID == [ids[1]: .disconnected, ids[2]: .connected])
    #expect(!rig.model.accessingKeys)
    // The disconnecting account itself is removed during the delete: nothing may trap or change C.
    rig.keys.pauseDelete(of: ids[2])
    let second = Task { await rig.model.disconnect(ids[2]) }
    #expect(await rig.keys.deleteEntered())
    await rig.model.removeAccount(ids[2])                  // removed while the disconnect delete is still paused
    rig.keys.resumeDelete()
    await second.value
    #expect(rig.model.workspace.accounts.map(\.id) == [ids[1]] && rig.model.workspace.accounts[0].connection == .disconnected)
    #expect(!rig.model.accessingKeys)
}

@MainActor @Test func accountsSampleLaunchFlagTouchesNoKeys() async throws {
    let rig = Rig { _ in HTTPResult(data: costJSON(cents: 1), status: 200) }
    defer { rig.cleanup() }
    var opened = 0
    #expect(!AccountsLaunch.handle(arguments: ["CostBar"], model: rig.model) { opened += 1 })
    #expect(opened == 0 && !rig.model.sample)
    #expect(AccountsLaunch.handle(arguments: ["CostBar", "--accounts-sample"], model: rig.model) { opened += 1 })
    #expect(opened == 1 && rig.model.sample)
    #expect(rig.model.workspace.accounts.count == 2 && rig.model.workspace.accounts.allSatisfy(\.isSample))
    #expect(rig.keys.totalOperations == 0 && rig.defaults.data(forKey: "accounts.workspace.v1") == nil)
    #expect(AccountsLaunch.sampleFlag == "--accounts-sample")
}

@MainActor @Test func refreshFailureWithUnknownErrorStoresFixedMessage() async throws {
    struct Leaky: Error, LocalizedError { var errorDescription: String? { "token=sk-SENTINEL at /Users/private-person/x" } }
    let rig = Rig { _ in throw Leaky() }
    defer { rig.cleanup() }
    _ = await rig.model.addAccount(provider: .anthropic, label: "A", key: "key-a"); try await rig.idle()
    let id = rig.model.workspace.accounts[0].id
    #expect(rig.model.workspace.failures[id]?.message == "The refresh failed unexpectedly. Try again later.")
    let raw = String(decoding: rig.defaults.data(forKey: "accounts.workspace.v1") ?? Data(), as: UTF8.self)
    #expect(!raw.contains("SENTINEL") && !raw.contains("private-person"))
    #expect(!String(decoding: try rig.model.exportData(), as: UTF8.self).contains("SENTINEL"))
}
