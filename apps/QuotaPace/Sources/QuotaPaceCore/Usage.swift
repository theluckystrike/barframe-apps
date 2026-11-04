import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex
    public var id: String { rawValue }
    public var title: String { self == .claude ? "Claude Code" : "Codex" }
    public var folderHint: String { self == .claude ? ".claude/projects" : ".codex/sessions" }
}
public struct TokenSample: Codable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let tokens: Int
    public init(id: String, date: Date, tokens: Int) { self.id = id; self.date = date; self.tokens = tokens }
}
public enum UsageWindow: String, CaseIterable, Identifiable, Codable, Sendable {
    case fiveHours, sevenDays
    public var id: String { rawValue }
    public var duration: TimeInterval { self == .fiveHours ? 5 * 3600 : 7 * 86400 }
    public var title: String { self == .fiveHours ? "Rolling 5 hours" : "Rolling 7 days" }
}
public struct WindowSummary: Equatable, Sendable {
    public let used: Int
    public let limit: Int
    public let elapsed: TimeInterval
    public let duration: TimeInterval
    public let tokensPerHour: Double
    public let projected: Double
    public let secondsToLimit: TimeInterval?
    public var fraction: Double? { limit > 0 ? Double(used) / Double(limit) : nil }
    public var isOverLimit: Bool { limit > 0 && used >= limit }

    public static func calculate(samples: [TokenSample], window: UsageWindow, limit: Int, now: Date) -> Self {
        let active = samples.filter { $0.tokens > 0 && $0.date > now.addingTimeInterval(-window.duration) && $0.date <= now }
        let used = active.reduce(0) { partial, sample in
            let (value, overflow) = partial.addingReportingOverflow(sample.tokens)
            return overflow ? Int.max : value
        }
        let oldest = active.map(\.date).min()
        // A single recent event has no reliable rate until one minute of observation.
        let elapsed = oldest.map { min(window.duration, max(0, now.timeIntervalSince($0))) } ?? 0
        let rate = elapsed >= 60 ? Double(used) / elapsed : 0
        let forecast: Double?
        if limit > 0 && used >= limit { forecast = 0 }
        else if limit > 0 && rate > 0 {
            // Integrate steady future consumption and subtract events as they leave the rolling window.
            var balance = Double(used)
            var cursor = 0.0
            var result: Double?
            for sample in active.sorted(by: { $0.date < $1.date }) {
                let expiry = max(0, sample.date.addingTimeInterval(window.duration).timeIntervalSince(now))
                let reach = (Double(limit) - balance) / rate
                if reach >= 0 && cursor + reach <= expiry { result = cursor + reach; break }
                balance += rate * (expiry - cursor) - Double(sample.tokens)
                cursor = expiry
            }
            if result == nil {
                let reach = (Double(limit) - balance) / rate
                if reach >= 0 && cursor + reach <= window.duration { result = cursor + reach }
            }
            forecast = result
        } else { forecast = nil }
        return Self(used: used, limit: max(0, limit), elapsed: elapsed, duration: window.duration,
                    tokensPerHour: rate * 3600, projected: rate * window.duration, secondsToLimit: forecast)
    }
}
public enum UsageError: LocalizedError {
    case invalidBookmark, notDirectory, oversizedLine
    public var errorDescription: String? {
        switch self {
        case .invalidBookmark: return "Folder access expired. Choose the folder again."
        case .notDirectory: return "Choose a folder containing session logs."
        case .oversizedLine: return "A log line exceeds the 4 MB safety limit."
        }
    }
}
