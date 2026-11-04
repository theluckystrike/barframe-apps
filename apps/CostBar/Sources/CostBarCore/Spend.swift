import Foundation

public enum Provider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openRouter, anthropic, openAI
    public var id: String { rawValue }
    public var name: String {
        switch self { case .openRouter: return "OpenRouter"; case .anthropic: return "Anthropic"; case .openAI: return "OpenAI" }
    }
    public var scope: String { self == .openRouter ? "Saved key · excludes BYOK" : "Organization · reported API costs" }
    public var keyHint: String {
        switch self {
        case .openRouter: return "API key for spend; management key for account credits."
        case .anthropic: return "Console organization Admin key. Priority Tier costs are excluded by the provider."
        case .openAI: return "Organization Admin key with permission to read costs."
        }
    }
    public var setupURL: URL {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/settings/keys")!
        case .anthropic: return URL(string: "https://platform.claude.com/docs/en/manage-claude/admin-api")!
        case .openAI: return URL(string: "https://platform.openai.com/settings/organization/admin-keys")!
        }
    }
}

public enum SpendError: Error, LocalizedError, Equatable {
    case invalidResponse, unsupportedCurrency, invalidKey, authentication, forbidden, rateLimited, http(Int), pagination, insecureURL
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The provider returned an unreadable cost report."
        case .unsupportedCurrency: return "The cost report contains a currency other than USD."
        case .invalidKey: return "Enter a key without spaces or line breaks."
        case .authentication: return "The key was rejected. Save a valid key in Settings."
        case .forbidden: return "This key cannot read costs. Check its organization permissions."
        case .rateLimited: return "The provider is limiting requests. Try again in a few minutes."
        case .http(let status): return "The provider returned HTTP \(status). Try refreshing later."
        case .pagination: return "The provider returned incomplete pagination. Try refreshing later."
        case .insecureURL: return "The request was blocked because its address is not secure."
        }
    }
}

public enum UTCClock {
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    public static func month(_ date: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)!
    }
    public static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    public static func parse(_ text: String) throws -> Date {
        let f = ISO8601DateFormatter()
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: text) else { throw SpendError.invalidResponse }
        return date
    }
    public static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    public static func monthID(_ date: Date) -> String { String(iso(month(date).start).prefix(7)) }
}

public struct CostBucket: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let usd: Decimal
    public init(start: Date, end: Date, usd: Decimal) {
        self.start = start; self.end = end; self.usd = usd
    }
}
public struct CostPage: Sendable {
    public let buckets: [CostBucket]
    public let nextPage: String?
    public init(buckets: [CostBucket], nextPage: String?) { self.buckets = buckets; self.nextPage = nextPage }
}

public struct SpendSnapshot: Codable, Equatable, Sendable {
    public let provider: Provider
    public let fetchedAt: Date
    public let dailyUSD: Decimal
    public let monthlyUSD: Decimal
    public let remainingCredits: Decimal?
    public let creditNote: String?
    public let weeklyUSD: Decimal?
    public let lifetimeUSD: Decimal?
    public init(provider: Provider, fetchedAt: Date, dailyUSD: Decimal, monthlyUSD: Decimal, remainingCredits: Decimal? = nil, creditNote: String? = nil, weeklyUSD: Decimal? = nil, lifetimeUSD: Decimal? = nil) {
        self.provider = provider; self.fetchedAt = fetchedAt; self.dailyUSD = dailyUSD; self.monthlyUSD = monthlyUSD
        self.remainingCredits = remainingCredits; self.creditNote = creditNote
        self.weeklyUSD = weeklyUSD; self.lifetimeUSD = lifetimeUSD
    }
    public static func aggregate(provider: Provider, buckets: [CostBucket], now: Date) throws -> SpendSnapshot {
        let month = UTCClock.month(now)
        let day = UTCClock.day(now)
        var monthly: Decimal = 0, daily: Decimal = 0
        var seen = Set<Date>()
        for bucket in buckets {
            guard bucket.end > bucket.start, seen.insert(bucket.start).inserted else { throw SpendError.invalidResponse }
            if bucket.start >= month.start && bucket.start < now { monthly += bucket.usd }
            if bucket.start >= day && bucket.start < now { daily += bucket.usd }
        }
        return .init(provider: provider, fetchedAt: now, dailyUSD: daily, monthlyUSD: monthly)
    }
    /// Mean reported spend per elapsed hour today. Clamp the first hour to avoid an unstable near-midnight estimate.
    public var hourlyUSD: Decimal {
        dailyUSD / Decimal(max(1, fetchedAt.timeIntervalSince(UTCClock.day(fetchedAt)) / 3600))
    }
    /// Linear extrapolation of month-to-date costs using the real UTC calendar month duration.
    public var projectedUSD: Decimal? {
        let interval = UTCClock.month(fetchedAt)
        let elapsed = fetchedAt.timeIntervalSince(interval.start)
        guard elapsed >= max(3 * 86400, interval.duration * 0.1) else { return nil }
        return max(0, monthlyUSD) * Decimal(interval.duration / elapsed)
    }
    public func isCurrentDay(at now: Date) -> Bool { UTCClock.day(fetchedAt) == UTCClock.day(now) }
    public func isCurrentMonth(at now: Date) -> Bool { UTCClock.monthID(fetchedAt) == UTCClock.monthID(now) }
    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(fetchedAt) > 900 || fetchedAt > now || !isCurrentMonth(at: now) || !isCurrentDay(at: now) }
}

public enum Money {
    public static func string(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
    public static func short(_ value: Decimal) -> String {
        let v = NSDecimalNumber(decimal: value).doubleValue
        if abs(v) >= 1_000_000 { return v < 0 ? "$-1M+" : "$1M+" }
        if abs(v) >= 1000 { return "$\(Int(v / 1000))k" }
        return String(format: "$%.0f", v)
    }
    public static func parseBudget(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{1,9}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }
}

public struct Budget: Codable, Equatable, Sendable {
    public var monthlyUSD: Decimal
    public var thresholdPercent: Int
    public init(monthlyUSD: Decimal = 100, thresholdPercent: Int = 80) {
        self.monthlyUSD = monthlyUSD; self.thresholdPercent = thresholdPercent
    }
    public func fraction(spend: Decimal) -> Double {
        guard monthlyUSD > 0 else { return 0 }
        return max(0, NSDecimalNumber(decimal: spend / monthlyUSD).doubleValue)
    }
    public func alertID(snapshot: SpendSnapshot) -> String? {
        guard monthlyUSD > 0, (1...100).contains(thresholdPercent),
              snapshot.monthlyUSD >= monthlyUSD * Decimal(thresholdPercent) / 100 else { return nil }
        return "\(snapshot.provider.rawValue)-\(UTCClock.monthID(snapshot.fetchedAt))-\(thresholdPercent)"
    }
}
