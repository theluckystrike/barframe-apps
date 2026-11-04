import Foundation
import Testing
@testable import CostBarCore

private func date(_ text: String) -> Date { try! UTCClock.parse(text) }
private let now = date("2026-10-15T12:00:00Z")
private let acct = "11111111-1111-4111-8111-111111111111"
private func grant(_ balance: Decimal, expires: Date, eligible: Set<Workload>, kind: GrantKind = .prepaidCredit, account: String = acct) -> CreditGrant {
    CreditGrant(accountID: account, balanceUSD: balance, expiresAt: expires, eligible: eligible, kind: kind, sourceLabel: "", observedAt: now)
}

@Test func onlyActiveExplicitlyEligibleGrantsCount() {
    let day: TimeInterval = 86400
    let grants = [
        grant(10, expires: now.addingTimeInterval(5 * day), eligible: [.directAPI]),
        grant(20, expires: now.addingTimeInterval(2 * day), eligible: [.directAPI, .agentSDK]),
        grant(40, expires: now.addingTimeInterval(-day), eligible: [.directAPI]),          // expired
        grant(80, expires: now.addingTimeInterval(9 * day), eligible: []),                // unknown eligibility
        grant(160, expires: now.addingTimeInterval(9 * day), eligible: [.directAPI], account: "other")
    ]
    let api = GrantLedger.summary(grants: grants, accountID: acct, workload: .directAPI, now: now)
    #expect(api.totalUSD == 30)
    #expect(api.nextExpiry == now.addingTimeInterval(2 * day))
    #expect(api.expiredCount == 1)
    #expect(api.notEligibleCount == 1)
    let sdk = GrantLedger.summary(grants: grants, accountID: acct, workload: .agentSDK, now: now)
    #expect(sdk.totalUSD == 20)
    let code = GrantLedger.summary(grants: grants, accountID: acct, workload: .claudeCode, now: now)
    #expect(code.totalUSD == 0 && code.nextExpiry == nil)
}
@Test func grantExpiringAtExactNowIsNotCounted() {
    let g = grant(5, expires: now, eligible: [.directAPI])
    #expect(GrantLedger.summary(grants: [g], accountID: acct, workload: .directAPI, now: now).totalUSD == 0)
}
@Test func subscriptionNeverReceivesDollars() {
    let g = grant(50, expires: now.addingTimeInterval(86400), eligible: [.directAPI, .subscription])
    let s = GrantLedger.summary(grants: [g], accountID: acct, workload: .subscription, now: now)
    #expect(!s.applicable && s.totalUSD == 0)
    let made = try? CreditGrant.validated(accountID: acct, balanceText: "5", expiresAt: now.addingTimeInterval(1), eligible: [.subscription], kind: .other, sourceLabel: "", observedAt: now, now: now)
    #expect(made?.eligible.isEmpty == true)
}
@Test func maxPromotionCannotBecomeClaudeCodeFunds() throws {
    #expect(throws: AccountInputError.promotionCannotFundClaudeCode) {
        try CreditGrant.validated(accountID: acct, balanceText: "100", expiresAt: now.addingTimeInterval(86400), eligible: [.agentSDK, .claudeCode],
                                  kind: .maxPlanAPIPromotion, sourceLabel: "", observedAt: now, now: now)
    }
    // Stored or hand-edited data is still blocked at calculation time.
    let forged = grant(100, expires: now.addingTimeInterval(86400), eligible: [.claudeCode, .agentSDK], kind: .maxPlanAPIPromotion)
    #expect(GrantLedger.summary(grants: [forged], accountID: acct, workload: .claudeCode, now: now).totalUSD == 0)
    #expect(GrantLedger.summary(grants: [forged], accountID: acct, workload: .agentSDK, now: now).totalUSD == 100)
}
@Test func grantAmountsRejectInvalidNonFiniteAndNegative() {
    for text in ["", "NaN", "nan", "inf", "-1", "-0.01", "1e3", "1,000", "$5", "1.23456", "abc", "0x10", " ", "9999999999"] {
        #expect(throws: AccountInputError.self, "\(text)") {
            try CreditGrant.validated(accountID: acct, balanceText: text, expiresAt: now, eligible: [], kind: .other, sourceLabel: "", observedAt: now, now: now)
        }
    }
    let ok = try? CreditGrant.validated(accountID: acct, balanceText: " 12.5 ", expiresAt: now, eligible: [.directAPI], kind: .other, sourceLabel: "x", observedAt: now, now: now)
    #expect(ok?.balanceUSD == Decimal(string: "12.5"))
    let corrupt = CreditGrant(accountID: acct, balanceUSD: Decimal.nan, expiresAt: now.addingTimeInterval(1000), eligible: [.directAPI], kind: .other, sourceLabel: "", observedAt: now)
    #expect(GrantLedger.summary(grants: [corrupt], accountID: acct, workload: .directAPI, now: now).totalUSD == 0)
}
@Test func observationsAfterNowAreRejectedByEveryValidator() throws {
    for offset: TimeInterval in [1, 43_200, 86_400, 3 * 86_400] {
        let future = now.addingTimeInterval(offset)
        #expect(throws: AccountInputError.futureObservation, "grant +\(offset)") {
            try CreditGrant.validated(accountID: acct, balanceText: "1", expiresAt: future.addingTimeInterval(9999), eligible: [], kind: .other, sourceLabel: "", observedAt: future, now: now)
        }
        #expect(throws: AccountInputError.futureObservation, "allowance +\(offset)") {
            try AllowanceObservation.validated(percentText: "5", resetsAt: future.addingTimeInterval(3600), observedAt: future, label: "", now: now)
        }
    }
    #expect((try? CreditGrant.validated(accountID: acct, balanceText: "1", expiresAt: now.addingTimeInterval(9), eligible: [], kind: .other, sourceLabel: "", observedAt: now, now: now)) != nil)
    #expect((try? AllowanceObservation.validated(percentText: "5", resetsAt: now.addingTimeInterval(9), observedAt: now, label: "", now: now)) != nil)
}
@Test func storedFutureDatedGrantNeverCounts() throws {
    let day: TimeInterval = 86400
    var future = grant(100, expires: now.addingTimeInterval(30 * day), eligible: [.directAPI])
    future.observedAt = now.addingTimeInterval(2 * day)
    let valid = grant(10, expires: now.addingTimeInterval(5 * day), eligible: [.directAPI])
    let both = GrantLedger.summary(grants: [future, valid], accountID: acct, workload: .directAPI, now: now)
    #expect(both.totalUSD == 10 && both.nextExpiry == valid.expiresAt && both.notYetObservedCount == 1)
    let alone = GrantLedger.summary(grants: [future], accountID: acct, workload: .directAPI, now: now)
    #expect(alone.totalUSD == 0 && alone.nextExpiry == nil)
    // Decoded from storage, the same record is still excluded; once its date arrives it counts.
    let decoded = try JSONDecoder().decode(CreditGrant.self, from: JSONEncoder().encode(future))
    #expect(GrantLedger.summary(grants: [decoded], accountID: acct, workload: .directAPI, now: now).totalUSD == 0)
    #expect(GrantLedger.summary(grants: [decoded], accountID: acct, workload: .directAPI, now: now.addingTimeInterval(2 * day)).totalUSD == 100)
    let allowance = AllowanceObservation(percentUsed: 10, resetsAt: now.addingTimeInterval(3 * day), observedAt: now.addingTimeInterval(day), label: "")
    #expect(allowance.isNotYetObserved(at: now) && !allowance.isNotYetObserved(at: now.addingTimeInterval(day)))
    var workspace = AccountWorkspace(salt: "s", accounts: [ProviderAccount(id: acct, provider: .anthropic, label: "x", createdAt: now, connection: .manualOnly, debt: DebtRecord(amountUSD: 3, observedAt: now.addingTimeInterval(day)))],
                                     grants: [future], allowances: [acct: allowance])
    workspace.accounts[0].selectedWorkload = .directAPI
    let report = RedactedExporter.report(workspace, now: now, synthetic: false)
    let a = report.accounts[0]
    #expect(a.eligibility.first { $0.workload == "directAPI" }?.totalUSD == "0")
    #expect(a.allowance?.notYetObservedAtExport == true && a.debtNotYetObservedAtExport == true && a.grants[0].notYetObservedAtExport)
    #expect(a.reportSource == "manualEntry" && a.status == "manual" && a.spend == nil)
}
@Test func allowanceValidationAndOutdatedState() throws {
    let a = try AllowanceObservation.validated(percentText: "62.5%", resetsAt: now.addingTimeInterval(3600), observedAt: now, label: "plan", now: now)
    #expect(a.percentUsed == 62.5 && !a.isOutdated(at: now) && a.isOutdated(at: now.addingTimeInterval(3600)))
    for text in ["101", "-1", "nan", "", "1e2", "50.555"] {
        #expect(throws: AccountInputError.invalidPercent, "\(text)") {
            try AllowanceObservation.validated(percentText: text, resetsAt: now.addingTimeInterval(1), observedAt: now, label: "", now: now)
        }
    }
    #expect(throws: AccountInputError.resetBeforeObservation) {
        try AllowanceObservation.validated(percentText: "5", resetsAt: now, observedAt: now, label: "", now: now)
    }
}

// MARK: Status, UTC boundaries
private func account(_ connection: ConnectionState = .connected) -> ProviderAccount {
    ProviderAccount(id: acct, provider: .anthropic, label: "x", createdAt: now, connection: connection)
}
@Test func statusLabelsHistoricalAcrossUTCDayAndMonthBoundaries() {
    let observed = date("2026-10-31T23:59:30Z")
    let report = AccountReport(snapshot: SpendSnapshot(provider: .anthropic, fetchedAt: observed, dailyUSD: 4, monthlyUSD: 90))
    let sameDay = AccountStatus.evaluate(account: account(), report: report, failure: nil, now: observed.addingTimeInterval(60 * 4))
    #expect(sameDay.historicalNote?.contains("2026-10") == true)  // after midnight it already crossed
    let crossedDay = AccountStatus.evaluate(account: account(), report: AccountReport(snapshot: SpendSnapshot(provider: .anthropic, fetchedAt: date("2026-10-14T23:59:59Z"), dailyUSD: 1, monthlyUSD: 2)), failure: nil, now: date("2026-10-15T00:00:01Z"))
    #expect(crossedDay.state == .stale)
    #expect(crossedDay.historicalNote == "Historical: the daily figure is for 2026-10-14 UTC, not today.")
    let crossedMonth = AccountStatus.evaluate(account: account(), report: report, failure: nil, now: date("2026-11-01T00:00:10Z"))
    #expect(crossedMonth.historicalNote?.contains("UTC month 2026-10") == true)
    #expect(crossedMonth.headline.contains("historical"))
    let fresh = AccountReport(snapshot: SpendSnapshot(provider: .anthropic, fetchedAt: now, dailyUSD: 1, monthlyUSD: 2))
    let current = AccountStatus.evaluate(account: account(), report: fresh, failure: nil, now: now.addingTimeInterval(60))
    #expect(current.state == .current && current.historicalNote == nil)
}
@Test func rejectedKeyKeepsReportButIsUnavailable() {
    let fresh = AccountReport(snapshot: SpendSnapshot(provider: .anthropic, fetchedAt: now, dailyUSD: 1, monthlyUSD: 2))
    let failure = AccountFailure.classify(SpendError.authentication, at: now)
    #expect(failure.kind == .credentialRejected)
    let status = AccountStatus.evaluate(account: account(), report: fresh, failure: failure, now: now)
    #expect(status.state == .unavailable && status.detail?.contains("Last observed") == true)
    #expect(AccountFailure.classify(SpendError.rateLimited, at: now).kind == .transient)
    #expect(AccountFailure.classify(SpendError.pagination, at: now).kind == .transient)
    let transient = AccountStatus.evaluate(account: account(), report: fresh, failure: .classify(SpendError.http(500), at: now), now: now)
    #expect(transient.state == .stale)
    let disconnected = AccountStatus.evaluate(account: account(.disconnected), report: fresh, failure: nil, now: now)
    #expect(disconnected.state == .unavailable)
}

// MARK: Log parsing
@Test func genericLogEstimateSumsTokensAndSkipsUnsafeLines() throws {
    let log = """
    {"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":40,"cache_read_input_tokens":999}}}
    {"usage":{"prompt_tokens":10,"completion_tokens":5}}
    not json at all
    {"usage":{"input_tokens":-5,"output_tokens":1.5}}
    {"usage":{"input_tokens":true,"output_tokens":"7"}}
    {"text":"sk-ant-secret path /Users/someone/file"}
    {"usage":{"input_tokens":1e12,"output_tokens":2}}
    """
    let e = try LogEstimator.estimate(data: Data(log.utf8), now: now)
    #expect(e.inputTokens == 110 && e.outputTokens == 45)
    #expect(e.recordsCounted == 2 && e.linesSkipped == 5)
    #expect(e.methods == ["generic-per-record"])
    #expect(e.fractionOfBudget(nil) == nil)
    #expect(e.fractionOfBudget(1550) == 0.1)
}
@Test func invalidTokenFieldRejectsRecordEvenWithValidPeer() {
    let bad = ["-1", "1.5", "true", "\"7\"", "1000000000001", "1e999", "null", "[]"]
    for value in bad {
        for (badKey, goodKey) in [("input_tokens", "output_tokens"), ("output_tokens", "input_tokens"), ("prompt_tokens", "completion_tokens"), ("completion_tokens", "prompt_tokens")] {
            let line = "{\"usage\":{\"\(badKey)\":\(value),\"\(goodKey)\":2}}"
            #expect(throws: LogImportError.noUsage, "\(line)") { try LogEstimator.estimate(data: Data(line.utf8)) }
        }
    }
    // A nested object cannot hide the invalid record behind another valid one.
    let nested = "{\"usage\":{\"input_tokens\":-1,\"output_tokens\":2,\"detail\":{\"input_tokens\":50,\"output_tokens\":50}}}\n{\"usage\":{\"input_tokens\":1}}"
    let e = try? LogEstimator.estimate(data: Data(nested.utf8))
    #expect(e?.inputTokens == 1 && e?.outputTokens == 0 && e?.recordsCounted == 1 && e?.linesSkipped == 1)
    // Same rule inside Claude and Codex shapes.
    let shaped = """
    {"message":{"id":"m1","usage":{"input_tokens":5,"output_tokens":-1}}}
    {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":"9","output_tokens":3}}}}
    {"usage":{"input_tokens":4,"output_tokens":6}}
    """
    let s = try? LogEstimator.estimate(data: Data(shaped.utf8))
    #expect(s?.inputTokens == 4 && s?.outputTokens == 6 && s?.linesSkipped == 2)
}
@Test func claudeRepeatedMessageIDsCountOnce() throws {
    let log = """
    {"type":"assistant","message":{"id":"msg-a","usage":{"input_tokens":1000,"output_tokens":200,"cache_creation_input_tokens":300,"cache_read_input_tokens":500}}}
    {"type":"assistant","message":{"id":"msg-a","usage":{"input_tokens":1000,"output_tokens":400,"cache_creation_input_tokens":300,"cache_read_input_tokens":500}}}
    {"type":"assistant","message":{"id":"msg-b","usage":{"input_tokens":800,"output_tokens":200}}}
    {"type":"assistant","message":{"id":"msg-c","usage":{"input_tokens":800,"output_tokens":200}}}
    {"type":"user","message":{"content":"ignored"}}
    """
    let e = try LogEstimator.estimate(data: Data(log.utf8), now: now)
    #expect(e.inputTokens == 1000 + 800 + 800)       // msg-a once; msg-b and msg-c stay distinct despite equal counts
    #expect(e.outputTokens == 400 + 200 + 200)
    #expect(e.methods == ["claude-message-id"] && e.linesSkipped == 1 && e.recordsCounted == 4)
}
@Test func codexCumulativeCountersAddOnlyIncreases() throws {
    func line(_ i: Int, _ o: Int) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(i + o),\"input_tokens\":\(i),\"cached_input_tokens\":1000,\"output_tokens\":\(o)},\"last_token_usage\":{\"total_tokens\":5}}}}"
    }
    let fixture = [line(2700, 300), line(2700, 300), line(4200, 300), line(4700, 300)].joined(separator: "\n")
    let e = try LogEstimator.estimate(data: Data(fixture.utf8), now: now)
    #expect(e.inputTokens == 4700 && e.outputTokens == 300 && e.methods == ["codex-cumulative"])
    // A decrease starts a new session counted from zero; the earlier session total is not subtracted from it.
    let two = [line(4700, 300), line(100, 20), line(150, 20)].joined(separator: "\n")
    let r = try LogEstimator.estimate(data: Data(two.utf8), now: now)
    #expect(r.inputTokens == 4700 + 150 && r.outputTokens == 300 + 20)
    // A log that starts mid-session counts the first counter in full: the whole observed cumulative value.
    let mid = try LogEstimator.estimate(data: Data(line(9000, 800).utf8), now: now)
    #expect(mid.inputTokens == 9000 && mid.outputTokens == 800)
    // Codex lines without total_token_usage never fall through to the generic rule.
    let none = #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":5,"output_tokens":5}}}}"#
    #expect(throws: LogImportError.noUsage) { try LogEstimator.estimate(data: Data(none.utf8)) }
}
@Test func mixedLogMethodsAreListed() throws {
    let log = """
    {"message":{"id":"m","usage":{"input_tokens":1,"output_tokens":2}}}
    {"usage":{"input_tokens":10,"output_tokens":20}}
    """
    let e = try LogEstimator.estimate(data: Data(log.utf8), now: now)
    #expect(e.methods == ["claude-message-id", "generic-per-record"] && e.totalTokens == 33)
    #expect(e.methods.allSatisfy { LogEstimator.methodNotes[$0] != nil })
}
@Test func logImportEnforcesSizeAndNeedsUsage() throws {
    #expect(throws: LogImportError.noUsage) { try LogEstimator.estimate(data: Data("hello\n{}\n".utf8)) }
    #expect(throws: LogImportError.tooLarge(LogEstimator.maxBytes)) { try LogEstimator.estimate(data: Data(count: LogEstimator.maxBytes + 1)) }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("costbar-log-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let big = dir.appendingPathComponent("big.jsonl")
    try Data(repeating: 0x20, count: LogEstimator.maxBytes + 10).write(to: big)
    #expect(throws: LogImportError.tooLarge(LogEstimator.maxBytes)) { try LogEstimator.read(url: big) }
    let small = dir.appendingPathComponent("ok.jsonl")
    try Data("{\"usage\":{\"input_tokens\":3,\"output_tokens\":4}}\n".utf8).write(to: small)
    #expect(try LogEstimator.read(url: small, now: now).totalTokens == 7)
    #expect(throws: LogImportError.unreadable) { try LogEstimator.read(url: dir.appendingPathComponent("missing")) }
    #expect(throws: AccountInputError.invalidBudget) { try LogEstimator.parseBudget("-3") }
    #expect(try LogEstimator.parseBudget(" 5000 ") == 5000)
}

// MARK: Export redaction
@Test func exportIsRedactedAndTyped() throws {
    var workspace = AccountSample.workspace(now: now)
    workspace.accounts[0].label = "jane.doe@example.com"
    workspace.grants[0].sourceLabel = "https://console.example.com/billing?token=SECRET123 /Users/jane/receipt.pdf"
    workspace.allowances[AccountSample.activeID]?.label = "jane@example.com plan"
    let data = try RedactedExporter.data(workspace, now: now, synthetic: true)
    let text = String(decoding: data, as: UTF8.self)
    for forbidden in ["jane", "@", "example.com", "SECRET123", "http", "/Users", "token=", "sk-ant", AccountSample.activeID, AccountSample.unavailableID, "Team A", "SAMPLE active grant"] {
        #expect(!text.contains(forbidden), "leaked \(forbidden)")
    }
    let report = try { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return try d.decode(RedactedReport.self, from: data) }()
    #expect(report.synthetic && report.notes.first?.hasPrefix("SYNTHETIC SAMPLE") == true)
    #expect(report.accounts.count == 2)
    let a = report.accounts[0]
    #expect(a.accountPseudonym == RedactedExporter.pseudonym(accountID: AccountSample.activeID, salt: "sample-salt"))
    #expect(a.accountPseudonym.count == 12 && a.accountPseudonym != report.accounts[1].accountPseudonym)
    #expect(a.reportingScope == "organizationCost" && a.logEstimate?.kind == "estimate")
    #expect(a.debtUSD == "12.5" && a.allowance?.source == "manual")
    let direct = a.eligibility.first { $0.workload == "directAPI" }
    #expect(direct?.totalUSD == "40")                      // expired $25 excluded
    #expect(a.eligibility.first { $0.workload == "claudeCode" }?.totalUSD == "0")
    #expect(a.eligibility.first { $0.workload == "agentSDK" }?.totalUSD == "140")
    #expect(a.eligibility.first { $0.workload == "subscription" }?.totalUSD == nil)
    #expect(report.accounts[1].status == "unavailable")
}
@Test func pseudonymDependsOnSaltAndIsStable() {
    let a = RedactedExporter.pseudonym(accountID: acct, salt: "one")
    #expect(a == RedactedExporter.pseudonym(accountID: acct, salt: "one"))
    #expect(a != RedactedExporter.pseudonym(accountID: acct, salt: "two"))
}

// MARK: Sample content
@Test func sampleCoversRequiredCases() {
    let w = AccountSample.workspace(now: now)
    #expect(w.accounts.count == 2 && w.accounts.allSatisfy(\.isSample) && w.accounts.allSatisfy { $0.label.hasPrefix("SAMPLE") })
    #expect(w.grants.allSatisfy(\.isSample) && w.grants.allSatisfy { $0.sourceLabel.hasPrefix("SAMPLE") })
    let a = w.accounts[0]
    #expect(w.grants.contains { $0.accountID == a.id && $0.expiresAt <= now })
    #expect(w.grants.contains { $0.accountID == a.id && $0.expiresAt > now })
    #expect(GrantLedger.summary(grants: w.grants, accountID: a.id, workload: .claudeCode, now: now).totalUSD == 0)
    #expect(w.allowances[a.id] != nil)
    let b = w.accounts[1]
    #expect(AccountStatus.evaluate(account: b, report: w.reports[b.id], failure: w.failures[b.id], now: now).state == .unavailable)
}
@Test func workspaceRoundTripsThroughStoreWithoutSecrets() throws {
    let suite = "costbar.test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AccountStore(defaults: defaults)
    let w = AccountSample.workspace(now: now)
    try store.save(w)
    #expect(store.load() == w)
    let raw = String(decoding: defaults.data(forKey: "accounts.workspace.v1") ?? Data(), as: UTF8.self)
    #expect(!raw.contains("sk-"))
}

@Test func unknownErrorTextIsNeverPersistedOrExported() throws {
    let sentinel = "credential=sk-SENTINEL /Users/private-person/session.json"
    let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: sentinel])
    let failure = AccountFailure.classify(error, at: now)
    #expect(failure.kind == .transient && !failure.message.contains("SENTINEL") && !failure.message.contains("/Users"))
    var workspace = AccountSample.workspace(now: now)
    workspace.failures[AccountSample.activeID] = failure
    let suite = "costbar.test." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try AccountStore(defaults: defaults).save(workspace)
    let raw = String(decoding: defaults.data(forKey: "accounts.workspace.v1") ?? Data(), as: UTF8.self)
    #expect(!raw.contains("SENTINEL") && !raw.contains("private-person"))
    let exported = String(decoding: try RedactedExporter.data(workspace, now: now, synthetic: true), as: UTF8.self)
    #expect(!exported.contains("SENTINEL") && !exported.contains("private-person"))
}
@Test func manualOnlyStatusHasNoReportAndNoRefresh() {
    let manual = ProviderAccount(id: acct, provider: .anthropic, label: "p", createdAt: now, connection: .manualOnly)
    let s = AccountStatus.evaluate(account: manual, report: nil, failure: nil, now: now)
    #expect(s.state == .manual && s.headline.contains("provider spend not connected"))
}
