import Foundation
import CryptoKit

/// Parses only usage fields. Conversation text is never retained.
public struct JSONLParser {
    public let provider: Provider
    public let sourceID: String
    public private(set) var samples: [String: TokenSample] = [:]
    public private(set) var malformedLines = 0
    public private(set) var recognizedLines = 0
    private var minimumDate: Date?
    private var previousTotal: Int?
    private var lineNumber = 0
    public init(provider: Provider, sourceID: String, minimumDate: Date? = nil) {
        self.provider = provider; self.sourceID = Self.opaqueID(sourceID); self.minimumDate = minimumDate
    }
    public mutating func retainUsage(since date: Date?) {
        minimumDate = date
        if let date { samples = samples.filter { $0.value.date > date } }
    }

    public mutating func ingest(_ line: Data) {
        lineNumber += 1
        guard !line.isEmpty else { return }
        guard let object = try? JSONSerialization.jsonObject(with: line), let row = object as? [String: Any] else {
            malformedLines += 1; return
        }
        guard let stamp = row["timestamp"] as? String, let date = Self.date(stamp) else { return }
        switch provider {
        case .claude:
            guard let message = row["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }
            let keys = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            guard Self.validFields(usage, keys: keys), let tokens = Self.sum(keys.compactMap { Self.count(usage[$0]) }) else {
                malformedLines += 1; return
            }
            guard tokens > 0 else { return }
            let identifier = (message["id"] as? String) ?? "\(sourceID):\(lineNumber)"
            let id = "claude:\(Self.opaqueID(identifier))"
            recognizedLines += 1
            if let minimumDate, date <= minimumDate { return }
            // Streaming assistant records repeat message IDs. Keep the largest complete usage record.
            if let old = samples[id] {
                samples[id] = TokenSample(id: id, date: min(old.date, date), tokens: max(old.tokens, tokens))
            } else { samples[id] = TokenSample(id: id, date: date, tokens: tokens) }
        case .codex:
            guard row["type"] as? String == "event_msg",
                  let payload = row["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else { return }
            guard let cumulative = Self.total(total) else { malformedLines += 1; return }
            var last: Int?
            if let rawLast = info["last_token_usage"] {
                guard let usage = rawLast as? [String: Any], let value = Self.total(usage) else {
                    malformedLines += 1; return
                }
                last = value
            }
            let delta: Int
            if let previous = previousTotal { delta = cumulative >= previous ? cumulative - previous : (last ?? cumulative) }
            else { delta = cumulative }
            previousTotal = cumulative
            recognizedLines += 1
            guard delta > 0 else { return }
            if let minimumDate, date <= minimumDate { return }
            let id = "codex:\(sourceID):\(lineNumber)"
            samples[id] = TokenSample(id: id, date: date, tokens: delta)
        }
    }
    public static func date(_ value: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: value) { return date }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: value)
    }
    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double < Double(Int.max), double.rounded(.down) == double else { return nil }
        return Int(double)
    }
    public static func opaqueID(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func validFields(_ usage: [String: Any], keys: [String]) -> Bool {
        keys.allSatisfy { usage[$0] == nil || count(usage[$0]) != nil }
    }
    private static func total(_ usage: [String: Any]) -> Int? {
        guard validFields(usage, keys: ["total_tokens", "input_tokens", "output_tokens", "cached_input_tokens", "reasoning_output_tokens"]) else { return nil }
        if let total = count(usage["total_tokens"]) { return total }
        // Cached input is already included in input_tokens for Codex.
        return sum([count(usage["input_tokens"]), count(usage["output_tokens"])].compactMap { $0 })
    }
    private static func sum(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        var total = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
}
import CoreFoundation
