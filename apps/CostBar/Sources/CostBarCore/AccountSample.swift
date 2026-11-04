import Foundation

/// Explicit synthetic sample. Fixed IDs, invented amounts, no private owner data. Every record is marked as a sample.
public enum AccountSample {
    public static let activeID = "00000000-0000-4000-8000-0000000000a1"
    public static let unavailableID = "00000000-0000-4000-8000-0000000000b2"
    public static func workspace(now: Date) -> AccountWorkspace {
        let hour: TimeInterval = 3600, dayLength: TimeInterval = 86400
        let a = ProviderAccount(id: activeID, provider: .anthropic, label: "SAMPLE · Team A (synthetic)", createdAt: now.addingTimeInterval(-30 * dayLength),
                                selectedWorkload: .agentSDK, debt: DebtRecord(amountUSD: Decimal(string: "12.5")!, observedAt: now.addingTimeInterval(-dayLength)),
                                tokenBudget: 2_000_000, isSample: true)
        let b = ProviderAccount(id: unavailableID, provider: .anthropic, label: "SAMPLE · Team B (synthetic)", createdAt: now.addingTimeInterval(-60 * dayLength),
                                selectedWorkload: .directAPI, isSample: true)
        let grants = [
            CreditGrant(accountID: activeID, balanceUSD: 40, expiresAt: now.addingTimeInterval(20 * dayLength), eligible: [.directAPI, .agentSDK],
                        kind: .prepaidCredit, sourceLabel: "SAMPLE active grant", observedAt: now.addingTimeInterval(-2 * hour), isSample: true),
            CreditGrant(accountID: activeID, balanceUSD: 25, expiresAt: now.addingTimeInterval(-3 * dayLength), eligible: [.directAPI, .agentSDK],
                        kind: .promotionalCredit, sourceLabel: "SAMPLE expired grant", observedAt: now.addingTimeInterval(-10 * dayLength), isSample: true),
            CreditGrant(accountID: activeID, balanceUSD: 100, expiresAt: now.addingTimeInterval(9 * dayLength), eligible: [.agentSDK],
                        kind: .maxPlanAPIPromotion, sourceLabel: "SAMPLE Max API promotion · not for Claude Code", observedAt: now.addingTimeInterval(-hour), isSample: true),
            CreditGrant(accountID: unavailableID, balanceUSD: 15, expiresAt: now.addingTimeInterval(45 * dayLength), eligible: [.directAPI],
                        kind: .prepaidCredit, sourceLabel: "SAMPLE grant, account unavailable", observedAt: now.addingTimeInterval(-5 * dayLength), isSample: true)
        ]
        let old = now.addingTimeInterval(-3 * dayLength)
        let reports: [String: AccountReport] = [
            activeID: AccountReport(snapshot: SpendSnapshot(provider: .anthropic, fetchedAt: now, dailyUSD: Decimal(string: "3.2")!, monthlyUSD: Decimal(string: "48.75")!)),
            unavailableID: AccountReport(snapshot: SpendSnapshot(provider: .anthropic, fetchedAt: old, dailyUSD: Decimal(string: "1.1")!, monthlyUSD: Decimal(string: "22.4")!))
        ]
        return AccountWorkspace(salt: "sample-salt", accounts: [a, b], reports: reports,
            failures: [unavailableID: AccountFailure(kind: .credentialRejected, message: "SAMPLE: the key was rejected. Replace the key for this account.", at: now.addingTimeInterval(-hour))],
            grants: grants,
            allowances: [activeID: AllowanceObservation(percentUsed: 62.5, resetsAt: now.addingTimeInterval(2 * dayLength), observedAt: now.addingTimeInterval(-3 * hour), label: "SAMPLE plan window", isSample: true)],
            logEstimates: [activeID: LogEstimate(inputTokens: 812_000, outputTokens: 164_000, recordsCounted: 240, linesSkipped: 3, importedAt: now.addingTimeInterval(-hour), isSample: true)],
            selectedAccountID: activeID)
    }
}
