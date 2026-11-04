import Foundation

/// Funding paths a user can run work through. Only explicit eligibility counts toward a dollar total.
public enum Workload: String, CaseIterable, Codable, Identifiable, Sendable {
    case directAPI, agentSDK, claudeCode, subscription
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .directAPI: return "Direct API"
        case .agentSDK: return "Agent SDK"
        case .claudeCode: return "API-funded Claude Code"
        case .subscription: return "Subscription use"
        }
    }
    /// Subscription use draws on a plan allowance, never on dollar grants.
    public var usesDollarGrants: Bool { self != .subscription }
}

/// What a report covers. A provider organization cost report is not a subscription usage report.
public enum ReportingScope: String, Codable, Sendable {
    case organizationCost, singleKeySpend
    public static func scope(for provider: Provider) -> ReportingScope { provider == .openRouter ? .singleKeySpend : .organizationCost }
    public var label: String {
        switch self {
        case .organizationCost: return "Organization API cost report"
        case .singleKeySpend: return "Single saved key spend (excludes BYOK)"
        }
    }
    public var caveat: String {
        "Not a subscription usage report and not a credit balance unless a credit line says so."
    }
}

public enum DataSource: String, Codable, Sendable {
    case providerAPI, manualEntry, localLogEstimate, syntheticSample
    public var label: String {
        switch self {
        case .providerAPI: return "Provider API"
        case .manualEntry: return "Manual entry"
        case .localLogEstimate: return "Local log estimate"
        case .syntheticSample: return "Synthetic sample"
        }
    }
}

/// `manualOnly` accounts hold dated manual records and never have a key, a Keychain item or a report request.
public enum ConnectionState: String, Codable, Sendable { case connected, disconnected, manualOnly }

public struct DebtRecord: Codable, Equatable, Sendable {
    public var amountUSD: Decimal
    public var observedAt: Date
    public init(amountUSD: Decimal, observedAt: Date) { self.amountUSD = amountUSD; self.observedAt = observedAt }
}

public struct ProviderAccount: Codable, Identifiable, Equatable, Sendable {
    public static let maxLabelLength = 40
    public let id: String
    public let provider: Provider
    /// Local display name only. It can hold personal text, so it is never exported.
    public var label: String
    public let createdAt: Date
    public var connection: ConnectionState
    public var selectedWorkload: Workload
    public var debt: DebtRecord?
    public var tokenBudget: Int?
    public var isSample: Bool
    public init(id: String = UUID().uuidString.lowercased(), provider: Provider, label: String, createdAt: Date,
                connection: ConnectionState = .connected, selectedWorkload: Workload = .directAPI,
                debt: DebtRecord? = nil, tokenBudget: Int? = nil, isSample: Bool = false) {
        self.id = id; self.provider = provider; self.label = label; self.createdAt = createdAt
        self.connection = connection; self.selectedWorkload = selectedWorkload
        self.debt = debt; self.tokenBudget = tokenBudget; self.isSample = isSample
    }
    public var shortID: String { String(id.suffix(8)) }
    public static func cleanLabel(_ text: String, fallback: String) -> String {
        let cleaned = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(maxLabelLength))
    }
}

public enum FailureKind: String, Codable, Sendable { case credentialRejected, transient }

public struct AccountFailure: Codable, Equatable, Sendable {
    public var kind: FailureKind
    public var message: String
    public var at: Date
    public init(kind: FailureKind, message: String, at: Date) { self.kind = kind; self.message = message; self.at = at }
    public static func classify(_ error: Error, at: Date) -> AccountFailure {
        if let spend = error as? SpendError {
            switch spend {
            case .authentication, .forbidden, .invalidKey:
                return .init(kind: .credentialRejected, message: spend.localizedDescription + " Replace the key for this account.", at: at)
            default: return .init(kind: .transient, message: spend.localizedDescription, at: at)
            }
        }
        if let url = error as? URLError {
            return .init(kind: .transient, message: url.code == .notConnectedToInternet ? "You are offline. Connect to the internet and refresh." : "The provider could not be reached. Try refreshing later.", at: at)
        }
        // Unknown errors can carry paths or credentials in their text. Persist a fixed message only.
        return .init(kind: .transient, message: "The refresh failed unexpectedly. Try again later.", at: at)
    }
}

/// Last complete observation for one account. A failed or partial refresh never replaces it.
public struct AccountReport: Codable, Equatable, Sendable {
    public var snapshot: SpendSnapshot
    public init(snapshot: SpendSnapshot) { self.snapshot = snapshot }
    public var observedAt: Date { snapshot.fetchedAt }
}

public struct AccountStatus: Equatable, Sendable {
    public enum State: String, Sendable { case current, stale, unavailable, neverObserved, manual }
    public let state: State
    public let headline: String
    public let detail: String?
    /// Set when the stored daily or monthly figure belongs to an earlier UTC period.
    public let historicalNote: String?
    public static func evaluate(account: ProviderAccount, report: AccountReport?, failure: AccountFailure?, now: Date) -> AccountStatus {
        let observed = report.map { "Last observed " + UTCClock.iso($0.observedAt) }
        var historical: String?
        if let snapshot = report?.snapshot {
            if !snapshot.isCurrentMonth(at: now) {
                historical = "Historical: the monthly figure is for UTC month \(UTCClock.monthID(snapshot.fetchedAt)) and the daily figure is for \(dayID(snapshot.fetchedAt)) UTC."
            } else if !snapshot.isCurrentDay(at: now) {
                historical = "Historical: the daily figure is for \(dayID(snapshot.fetchedAt)) UTC, not today."
            }
        }
        if account.connection == .manualOnly {
            return .init(state: .manual, headline: "Manual records only · provider spend not connected",
                         detail: "No key is stored and no cost report is requested. Add a reporting key to see provider spend.", historicalNote: nil)
        }
        if account.connection == .disconnected {
            return .init(state: .unavailable, headline: report == nil ? "Disconnected" : "Unavailable · disconnected",
                         detail: [report == nil ? nil : "The key was removed. Figures below are the last observation.", observed].compactMap { $0 }.joined(separator: " "), historicalNote: historical)
        }
        if let failure, failure.kind == .credentialRejected {
            return .init(state: .unavailable, headline: "Unavailable · key rejected",
                         detail: [failure.message, observed].compactMap { $0 }.joined(separator: " "), historicalNote: historical)
        }
        guard let report else {
            return .init(state: .neverObserved, headline: failure == nil ? "Waiting for first report" : "No report yet",
                         detail: failure?.message, historicalNote: nil)
        }
        if let failure {
            return .init(state: .stale, headline: "Stale · last refresh failed", detail: [failure.message, observed].compactMap { $0 }.joined(separator: " "), historicalNote: historical)
        }
        if report.snapshot.isStale(at: now) {
            return .init(state: .stale, headline: historical == nil ? "Stale · refresh needed" : "Stale · historical figures", detail: observed, historicalNote: historical)
        }
        return .init(state: .current, headline: "Current", detail: observed, historicalNote: nil)
    }
    private static func dayID(_ date: Date) -> String { String(UTCClock.iso(UTCClock.day(date)).prefix(10)) }
}

/// Validation failures carry the next action for the user.
public enum AccountInputError: Error, LocalizedError, Equatable {
    case invalidAmount(String), invalidPercent, resetBeforeObservation, futureObservation
    case promotionCannotFundClaudeCode, tooManyAccounts, invalidBudget, accountMissing, sampleReadOnly
    public var errorDescription: String? {
        switch self {
        case .invalidAmount(let field): return "\(field) must be a plain non-negative USD amount such as 25 or 12.50 (up to four decimals)."
        case .invalidPercent: return "Usage must be a number from 0 to 100."
        case .resetBeforeObservation: return "The reset time must be after the observation time."
        case .futureObservation: return "The observation date and time cannot be after now. Use the time you actually saw the figure."
        case .promotionCannotFundClaudeCode: return "A Max plan API promotion cannot be marked as funding ordinary Claude Code."
        case .tooManyAccounts: return "CostBar holds up to \(AccountWorkspace.maxAccounts) accounts. Remove one first."
        case .invalidBudget: return "Enter a whole token budget between 1 and 999,999,999,999."
        case .accountMissing: return "That account is no longer connected."
        case .sampleReadOnly: return "Sample mode uses bundled synthetic data. Exit Sample mode to connect real accounts."
        }
    }
}

public enum Amounts {
    /// Strict decimal parser: no signs, exponents, NaN, infinity or grouping separators.
    public static func parseUSD(_ text: String, field: String) throws -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{1,9}(\.\d{1,4})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0 else { throw AccountInputError.invalidAmount(field) }
        return value
    }
    public static func isValid(_ value: Decimal) -> Bool { !value.isNaN && value >= 0 && value < 1_000_000_000 }
}

public enum GrantKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case prepaidCredit, promotionalCredit, maxPlanAPIPromotion, other
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .prepaidCredit: return "Prepaid credit"
        case .promotionalCredit: return "Promotional credit"
        case .maxPlanAPIPromotion: return "Max plan API promotion"
        case .other: return "Other"
        }
    }
}

/// A dated manual record. CostBar does not verify these values with a provider.
public struct CreditGrant: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let accountID: String
    public var balanceUSD: Decimal
    public var expiresAt: Date
    /// Unknown eligibility is an empty set. It is not eligible for any workload.
    public var eligible: Set<Workload>
    public var kind: GrantKind
    /// Free text for the user's own memory. Never exported.
    public var sourceLabel: String
    public var observedAt: Date
    public var isSample: Bool
    /// A record dated after `now` is not an observation yet. It can never count as available money.
    public func isObserved(at now: Date) -> Bool { observedAt <= now }
    public init(id: UUID = UUID(), accountID: String, balanceUSD: Decimal, expiresAt: Date, eligible: Set<Workload>, kind: GrantKind,
                sourceLabel: String, observedAt: Date, isSample: Bool = false) {
        self.id = id; self.accountID = accountID; self.balanceUSD = balanceUSD; self.expiresAt = expiresAt
        self.eligible = eligible; self.kind = kind; self.sourceLabel = sourceLabel; self.observedAt = observedAt; self.isSample = isSample
    }
    public static func validated(accountID: String, balanceText: String, expiresAt: Date, eligible: Set<Workload>, kind: GrantKind,
                                 sourceLabel: String, observedAt: Date, now: Date) throws -> CreditGrant {
        let balance = try Amounts.parseUSD(balanceText, field: "Credit balance")
        guard observedAt <= now else { throw AccountInputError.futureObservation }
        // The subscription workload is never funded by dollars; strip it so it cannot be recorded.
        var workloads = eligible.subtracting([.subscription])
        if kind == .maxPlanAPIPromotion {
            guard !workloads.contains(.claudeCode) else { throw AccountInputError.promotionCannotFundClaudeCode }
        }
        workloads = workloads.intersection(Workload.allCases)
        let label = AccountSafeText.clean(sourceLabel, limit: 60)
        return CreditGrant(accountID: accountID, balanceUSD: balance, expiresAt: expiresAt, eligible: workloads, kind: kind, sourceLabel: label, observedAt: observedAt)
    }
}

public enum AccountSafeText {
    public static func clean(_ text: String, limit: Int) -> String {
        String(String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}

public struct EligibilitySummary: Equatable, Sendable {
    public let workload: Workload
    /// False for subscription use: dollar grants do not apply, and no dollar total is shown.
    public let applicable: Bool
    public let totalUSD: Decimal
    public let counted: [UUID]
    public let nextExpiry: Date?
    public let expiredCount: Int
    /// Grants whose eligibility for this workload is unknown or explicitly absent.
    public let notEligibleCount: Int
    /// Grants dated after now. They are listed but not counted, whatever their eligibility.
    public let notYetObservedCount: Int
}

public enum GrantLedger {
    public static func summary(grants: [CreditGrant], accountID: String, workload: Workload, now: Date) -> EligibilitySummary {
        guard workload.usesDollarGrants else {
            return .init(workload: workload, applicable: false, totalUSD: 0, counted: [], nextExpiry: nil, expiredCount: 0, notEligibleCount: 0, notYetObservedCount: 0)
        }
        var total: Decimal = 0, counted: [CreditGrant] = [], expired = 0, notEligible = 0, future = 0
        for grant in grants where grant.accountID == accountID {
            guard Amounts.isValid(grant.balanceUSD) else { notEligible += 1; continue }
            guard grant.isObserved(at: now) else { future += 1; continue }
            if grant.expiresAt <= now { expired += 1; continue }
            // A Max plan API promotion is never ordinary Claude Code funds, even if stored data says otherwise.
            guard grant.eligible.contains(workload), !(grant.kind == .maxPlanAPIPromotion && workload == .claudeCode) else { notEligible += 1; continue }
            total += grant.balanceUSD
            counted.append(grant)
        }
        return .init(workload: workload, applicable: true, totalUSD: total, counted: counted.map(\.id),
                     nextExpiry: counted.map(\.expiresAt).min(), expiredCount: expired, notEligibleCount: notEligible, notYetObservedCount: future)
    }
}

/// Manual plan observation. A percentage and a reset time only; never a dollar value or official quota.
public struct AllowanceObservation: Codable, Equatable, Sendable {
    public var percentUsed: Double
    public var resetsAt: Date
    public var observedAt: Date
    public var label: String
    public var isSample: Bool
    public init(percentUsed: Double, resetsAt: Date, observedAt: Date, label: String, isSample: Bool = false) {
        self.percentUsed = percentUsed; self.resetsAt = resetsAt; self.observedAt = observedAt; self.label = label; self.isSample = isSample
    }
    public static func validated(percentText: String, resetsAt: Date, observedAt: Date, label: String, now: Date) throws -> AllowanceObservation {
        let trimmed = percentText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
        guard trimmed.range(of: #"^\d{1,3}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Double(trimmed), value.isFinite, (0...100).contains(value) else { throw AccountInputError.invalidPercent }
        guard observedAt <= now else { throw AccountInputError.futureObservation }
        guard resetsAt > observedAt else { throw AccountInputError.resetBeforeObservation }
        return .init(percentUsed: value, resetsAt: resetsAt, observedAt: observedAt, label: AccountSafeText.clean(label, limit: 40))
    }
    public func isOutdated(at now: Date) -> Bool { now >= resetsAt }
    /// Stored data dated after now is not current evidence.
    public func isNotYetObserved(at now: Date) -> Bool { observedAt > now }
}

/// Everything persisted for the account workflow. No keys, tokens, raw logs or file paths.
public struct AccountWorkspace: Codable, Equatable, Sendable {
    public static let maxAccounts = 10
    public var salt: String
    public var accounts: [ProviderAccount]
    public var reports: [String: AccountReport]
    public var failures: [String: AccountFailure]
    public var grants: [CreditGrant]
    public var allowances: [String: AllowanceObservation]
    public var logEstimates: [String: LogEstimate]
    public var selectedAccountID: String?
    public init(salt: String = UUID().uuidString, accounts: [ProviderAccount] = [], reports: [String: AccountReport] = [:],
                failures: [String: AccountFailure] = [:], grants: [CreditGrant] = [], allowances: [String: AllowanceObservation] = [:],
                logEstimates: [String: LogEstimate] = [:], selectedAccountID: String? = nil) {
        self.salt = salt; self.accounts = accounts; self.reports = reports; self.failures = failures
        self.grants = grants; self.allowances = allowances; self.logEstimates = logEstimates; self.selectedAccountID = selectedAccountID
    }
    public func account(_ id: String) -> ProviderAccount? { accounts.first { $0.id == id } }
    public mutating func removeAccount(_ id: String) {
        accounts.removeAll { $0.id == id }
        reports[id] = nil; failures[id] = nil; allowances[id] = nil; logEstimates[id] = nil
        grants.removeAll { $0.accountID == id }
        if selectedAccountID == id { selectedAccountID = accounts.first?.id }
    }
}

/// Non-secret account data in the app container, separate from the original provider preferences.
public final class AccountStore {
    private let defaults: UserDefaults
    private let key = "accounts.workspace.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> AccountWorkspace {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(AccountWorkspace.self, from: data) else { return AccountWorkspace() }
        return value
    }
    public func save(_ workspace: AccountWorkspace) throws { defaults.set(try JSONEncoder().encode(workspace), forKey: key) }
}
