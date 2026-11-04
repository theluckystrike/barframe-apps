import Foundation
import CostBarCore

/// Bundled documentation examples, rebased to the current UTC period for an interactive preview.
enum SampleData {
    static func load(now: Date = Date(), fixture: (String) throws -> Data = Verification.fixture) throws -> [Provider: SpendSnapshot] {
        let key = try CostParser.openRouterKey(fixture("openrouter-key"), now: now)
        var result: [Provider: SpendSnapshot] = [
            .openRouter: SpendSnapshot(provider: .openRouter, fetchedAt: now, dailyUSD: key.dailyUSD,
                                      monthlyUSD: key.monthlyUSD,
                                      remainingCredits: try CostParser.openRouterCredits(fixture("openrouter-credits")),
                                      weeklyUSD: key.weeklyUSD, lifetimeUSD: key.lifetimeUSD)
        ]
        for (provider, page) in [
            (Provider.anthropic, try CostParser.anthropic(fixture("anthropic"))),
            (Provider.openAI, try CostParser.openAI(fixture("openai")))
        ] {
            let total = page.buckets.reduce(Decimal.zero) { $0 + $1.usd }
            result[provider] = SpendSnapshot(provider: provider, fetchedAt: now, dailyUSD: total, monthlyUSD: total)
        }
        return result
    }
}
