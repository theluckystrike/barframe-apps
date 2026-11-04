import Foundation
import CryptoKit

/// Typed, redacted report. Contains pseudonymous IDs and typed facts only. It is written locally and never sent anywhere.
public struct RedactedReport: Codable, Equatable, Sendable {
    public struct Spend: Codable, Equatable, Sendable {
        public let monthlyUSD: String, dailyUSD: String
        public let monthUTC: String, dayUTC: String
        public let observedAt: Date
        public let status: String
        public let historical: Bool
    }
    public struct Grant: Codable, Equatable, Sendable {
        public let balanceUSD: String, expiresAt: Date, observedAt: Date
        public let kind: String, eligibleWorkloads: [String]
        public let expiredAtExport: Bool, notYetObservedAtExport: Bool, source: String
    }
    public struct Eligibility: Codable, Equatable, Sendable {
        public let workload: String, applicable: Bool, totalUSD: String?, nextExpiry: Date?
    }
    public struct Allowance: Codable, Equatable, Sendable {
        public let percentUsed: Double, resetsAt: Date, observedAt: Date, source: String, outdatedAtExport: Bool, notYetObservedAtExport: Bool
    }
    public struct Tokens: Codable, Equatable, Sendable {
        public let inputTokens: UInt64, outputTokens: UInt64, records: Int, importedAt: Date, budgetTokens: Int?
        public let kind: String, note: String
    }
    public struct Account: Codable, Equatable, Sendable {
        public let accountPseudonym: String, provider: String, reportingScope: String, reportSource: String
        public let connection: String, status: String
        public let spend: Spend?
        public let debtUSD: String?, debtObservedAt: Date?, debtNotYetObservedAtExport: Bool?
        public let grants: [Grant]
        public let eligibility: [Eligibility]
        public let allowance: Allowance?
        public let logEstimate: Tokens?
    }
    public let schema: String, generatedAt: Date, synthetic: Bool, notes: [String]
    public let accounts: [Account]
}

public enum RedactedExporter {
    public static func pseudonym(accountID: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + "|" + accountID).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
    static func money(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }

    public static func report(_ workspace: AccountWorkspace, now: Date, synthetic: Bool) -> RedactedReport {
        let accounts = workspace.accounts.map { account -> RedactedReport.Account in
            let status = AccountStatus.evaluate(account: account, report: workspace.reports[account.id], failure: workspace.failures[account.id], now: now)
            let spend = workspace.reports[account.id].map { report -> RedactedReport.Spend in
                let s = report.snapshot
                return .init(monthlyUSD: money(s.monthlyUSD), dailyUSD: money(s.dailyUSD), monthUTC: UTCClock.monthID(s.fetchedAt),
                             dayUTC: String(UTCClock.iso(UTCClock.day(s.fetchedAt)).prefix(10)), observedAt: s.fetchedAt,
                             status: status.state.rawValue, historical: status.historicalNote != nil)
            }
            let grants = workspace.grants.filter { $0.accountID == account.id }.map { g in
                RedactedReport.Grant(balanceUSD: money(g.balanceUSD), expiresAt: g.expiresAt, observedAt: g.observedAt, kind: g.kind.rawValue,
                                     eligibleWorkloads: g.eligible.map(\.rawValue).sorted(), expiredAtExport: g.expiresAt <= now, notYetObservedAtExport: g.observedAt > now, source: "manual")
            }
            let eligibility = Workload.allCases.map { w -> RedactedReport.Eligibility in
                let s = GrantLedger.summary(grants: workspace.grants, accountID: account.id, workload: w, now: now)
                return .init(workload: w.rawValue, applicable: s.applicable, totalUSD: s.applicable ? money(s.totalUSD) : nil, nextExpiry: s.nextExpiry)
            }
            let allowance = workspace.allowances[account.id].map {
                RedactedReport.Allowance(percentUsed: $0.percentUsed, resetsAt: $0.resetsAt, observedAt: $0.observedAt, source: "manual", outdatedAtExport: $0.isOutdated(at: now), notYetObservedAtExport: $0.isNotYetObserved(at: now))
            }
            let tokens = workspace.logEstimates[account.id].map {
                RedactedReport.Tokens(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens, records: $0.recordsCounted, importedAt: $0.importedAt,
                                      budgetTokens: account.tokenBudget, kind: "estimate",
                                      note: "Token estimate from a local log. Not spend and not a provider quota.")
            }
            return .init(accountPseudonym: pseudonym(accountID: account.id, salt: workspace.salt), provider: account.provider.rawValue,
                         reportingScope: ReportingScope.scope(for: account.provider).rawValue,
                         reportSource: synthetic ? DataSource.syntheticSample.rawValue : (account.connection == .manualOnly ? DataSource.manualEntry.rawValue : DataSource.providerAPI.rawValue),
                         connection: account.connection.rawValue, status: status.state.rawValue, spend: spend,
                         debtUSD: account.debt.map { money($0.amountUSD) }, debtObservedAt: account.debt?.observedAt, debtNotYetObservedAtExport: account.debt.map { $0.observedAt > now },
                         grants: grants, eligibility: eligibility, allowance: allowance, logEstimate: tokens)
        }
        var notes = ["Account IDs are salted hashes. API keys, tokens, display labels, source labels, URLs and file paths are not included.",
                     "Grants, debt and allowance values are manual entries. CostBar has not verified them with the provider.",
                     "Dollar grants, debt, and subscription allowance percentages are separate facts and are never summed."]
        if synthetic { notes.insert("SYNTHETIC SAMPLE. Not real account data.", at: 0) }
        return .init(schema: "costbar.redacted-report.v1", generatedAt: now, synthetic: synthetic, notes: notes, accounts: accounts)
    }

    public static func data(_ workspace: AccountWorkspace, now: Date, synthetic: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report(workspace, now: now, synthetic: synthetic))
    }
}
