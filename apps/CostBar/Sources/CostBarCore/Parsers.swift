import Foundation

public enum CostParser {
    private struct KeyResponse: Decodable {
        struct Key: Decodable { let usage_daily: Decimal; let usage_monthly: Decimal; let usage_weekly: Decimal?; let usage: Decimal? }
        let data: Key
    }
    private struct CreditsResponse: Decodable {
        struct Credits: Decodable { let total_credits: Decimal; let total_usage: Decimal }
        let data: Credits
    }
    private struct AnthropicResponse: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable { let amount: String; let currency: String }
            let starting_at: String; let ending_at: String; let results: [Result]
        }
        let data: [Bucket]; let has_more: Bool; let next_page: String?
    }
    private struct OpenAIResponse: Decodable {
        struct Bucket: Decodable {
            struct Result: Decodable {
                struct Amount: Decodable { let value: Decimal; let currency: String }
                let amount: Amount
            }
            let start_time: Double; let end_time: Double; let results: [Result]
        }
        let data: [Bucket]; let has_more: Bool; let next_page: String?
    }
    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw SpendError.invalidResponse }
    }
    public static func openRouterKey(_ data: Data, now: Date) throws -> SpendSnapshot {
        let key = try decode(KeyResponse.self, data).data
        guard [key.usage_daily, key.usage_monthly] .allSatisfy({ !$0.isNaN && $0 >= 0 }),
              [key.usage_weekly, key.usage].compactMap({ $0 }).allSatisfy({ !$0.isNaN && $0 >= 0 }) else { throw SpendError.invalidResponse }
        return .init(provider: .openRouter, fetchedAt: now, dailyUSD: key.usage_daily, monthlyUSD: key.usage_monthly, weeklyUSD: key.usage_weekly, lifetimeUSD: key.usage)
    }
    public static func openRouterCredits(_ data: Data) throws -> Decimal {
        let credits = try decode(CreditsResponse.self, data).data
        guard credits.total_credits >= 0, credits.total_usage >= 0 else { throw SpendError.invalidResponse }
        return credits.total_credits - credits.total_usage
    }
    private static func cursor(hasMore: Bool, next: String?) throws -> String? {
        guard hasMore else { return nil }
        guard let next, !next.isEmpty else { throw SpendError.pagination }
        return next
    }
    public static func anthropic(_ data: Data) throws -> CostPage {
        let report = try decode(AnthropicResponse.self, data)
        let buckets = try report.data.map { b -> CostBucket in
            var total: Decimal = 0
            for r in b.results {
                guard r.currency.uppercased() == "USD" else { throw SpendError.unsupportedCurrency }
                guard r.amount.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil,
                      let cents = Decimal(string: r.amount, locale: Locale(identifier: "en_US_POSIX")) else { throw SpendError.invalidResponse }
                total += cents / 100
            }
            let start = try UTCClock.parse(b.starting_at), end = try UTCClock.parse(b.ending_at)
            guard end > start else { throw SpendError.invalidResponse }
            return CostBucket(start: start, end: end, usd: total)
        }
        return CostPage(buckets: buckets, nextPage: try cursor(hasMore: report.has_more, next: report.next_page))
    }
    public static func openAI(_ data: Data) throws -> CostPage {
        let report = try decode(OpenAIResponse.self, data)
        let buckets = try report.data.map { b -> CostBucket in
            guard b.start_time.isFinite, b.end_time.isFinite, b.end_time > b.start_time else { throw SpendError.invalidResponse }
            var total: Decimal = 0
            for r in b.results {
                guard r.amount.currency.uppercased() == "USD" else { throw SpendError.unsupportedCurrency }
                total += r.amount.value
            }
            return CostBucket(start: Date(timeIntervalSince1970: b.start_time), end: Date(timeIntervalSince1970: b.end_time), usd: total)
        }
        return CostPage(buckets: buckets, nextPage: try cursor(hasMore: report.has_more, next: report.next_page))
    }
}
