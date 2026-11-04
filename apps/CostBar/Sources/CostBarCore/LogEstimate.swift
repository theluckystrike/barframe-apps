import Foundation

public enum LogImportError: Error, LocalizedError, Equatable {
    case tooLarge(Int), unreadable, noUsage
    public var errorDescription: String? {
        switch self {
        case .tooLarge(let limit): return "That file is larger than \(limit / 1_048_576) MB. Export a smaller log and try again."
        case .unreadable: return "CostBar could not read that file. Choose a text or JSON Lines log."
        case .noUsage: return "No token counts were found. CostBar reads Claude Code message usage, Codex token_count events, or JSON lines with input_tokens/output_tokens (or prompt_tokens/completion_tokens)."
        }
    }
}

/// Token totals from a user-selected local log. An estimate only: not spend, not a quota, not a subscription allowance.
public struct LogEstimate: Codable, Equatable, Sendable {
    public var inputTokens: UInt64
    public var outputTokens: UInt64
    public var recordsCounted: Int
    public var linesSkipped: Int
    public var importedAt: Date
    public var isSample: Bool
    /// Which counting rules produced the totals. See `LogEstimator.methodNotes`.
    public var methods: [String]
    public init(inputTokens: UInt64, outputTokens: UInt64, recordsCounted: Int, linesSkipped: Int, importedAt: Date, isSample: Bool = false, methods: [String] = []) {
        self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.recordsCounted = recordsCounted
        self.linesSkipped = linesSkipped; self.importedAt = importedAt; self.isSample = isSample; self.methods = methods
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try c.decode(UInt64.self, forKey: .inputTokens); outputTokens = try c.decode(UInt64.self, forKey: .outputTokens)
        recordsCounted = try c.decode(Int.self, forKey: .recordsCounted); linesSkipped = try c.decode(Int.self, forKey: .linesSkipped)
        importedAt = try c.decode(Date.self, forKey: .importedAt)
        isSample = try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
        methods = try c.decodeIfPresent([String].self, forKey: .methods) ?? []
    }
    public var totalTokens: UInt64 { inputTokens &+ outputTokens }
    public func fractionOfBudget(_ budget: Int?) -> Double? {
        guard let budget, budget > 0 else { return nil }
        return Double(totalTokens) / Double(budget)
    }
}

/// Counting rules (each is an estimate with stated limits):
/// - `claude-message-id`: a Claude Code line with `message.id` and `message.usage`. Repeated IDs are one message; the largest
///   input and the largest output seen for that ID are kept. Distinct IDs add up. Cache token fields are not counted.
/// - `codex-cumulative`: `event_msg` / `token_count` lines carry running totals for a session. Only increases are added. An unchanged
///   counter adds nothing. If either counter decreases, a new session is assumed and its value is counted from zero. The first counter in
///   the file counts in full, including usage that happened before the first line in the file.
/// - `generic-per-record`: any other JSON line with input/output token fields is one independent usage record. Repeated or cumulative
///   counters in such logs will be over-counted; CostBar cannot tell.
/// A recognized token field that is present but invalid rejects its whole record.
public enum LogEstimator {
    public static let maxBytes = 5 * 1_048_576
    static let maxLineBytes = 262_144
    static let maxTokensPerField: Double = 1_000_000_000
    public static let methodNotes: [String: String] = [
        "claude-message-id": "Claude messages counted once by ID (largest input and output seen); cache tokens excluded.",
        "codex-cumulative": "Codex running totals counted as increases; a decrease starts a new session; the first total counts in full.",
        "generic-per-record": "Each line counted as separate usage; repeated or cumulative counters are over-counted."
    ]
    private static let inputKeys = ["input_tokens", "prompt_tokens"]
    private static let outputKeys = ["output_tokens", "completion_tokens"]

    private struct Pair { var input: UInt64; var output: UInt64 }
    private enum Found { case none, invalid, usage(Pair) }

    /// Reads at most `maxBytes + 1` bytes so an oversized file is refused without loading it. The path is not kept.
    public static func read(url: URL, now: Date = Date()) throws -> LogEstimate {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw LogImportError.unreadable }
        defer { try? handle.close() }
        let data: Data
        do { data = try handle.read(upToCount: maxBytes + 1) ?? Data() } catch { throw LogImportError.unreadable }
        return try estimate(data: data, now: now)
    }

    public static func estimate(data: Data, now: Date = Date()) throws -> LogEstimate {
        guard data.count <= maxBytes else { throw LogImportError.tooLarge(maxBytes) }
        var generic = Pair(input: 0, output: 0), messages: [String: Pair] = [:], codex = Pair(input: 0, output: 0)
        var previousCodex: Pair?, counted = 0, skipped = 0, methods = Set<String>()
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard line.count <= maxLineBytes, let row = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { skipped += 1; continue }
            if row["type"] as? String == "event_msg", let payload = row["payload"] as? [String: Any], payload["type"] as? String == "token_count" {
                guard let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any],
                      case .usage(let current) = pair(total) else { skipped += 1; continue }
                if let previous = previousCodex, current.input >= previous.input, current.output >= previous.output {
                    codex.input += current.input - previous.input; codex.output += current.output - previous.output
                } else { codex.input += current.input; codex.output += current.output }   // first counter, or a new session after a decrease
                previousCodex = current; counted += 1; methods.insert("codex-cumulative")
                continue
            }
            if let message = row["message"] as? [String: Any], let id = message["id"] as? String, !id.isEmpty, let usage = message["usage"] as? [String: Any] {
                guard case .usage(let value) = pair(usage) else { skipped += 1; continue }
                let old = messages[id] ?? Pair(input: 0, output: 0)
                messages[id] = Pair(input: max(old.input, value.input), output: max(old.output, value.output))
                counted += 1; methods.insert("claude-message-id")
                continue
            }
            switch findUsage(row, depth: 0) {
            case .usage(let value): generic.input += value.input; generic.output += value.output; counted += 1; methods.insert("generic-per-record")
            case .none, .invalid: skipped += 1
            }
        }
        guard counted > 0 else { throw LogImportError.noUsage }
        let input = generic.input + codex.input + messages.values.reduce(0) { $0 + $1.input }
        let output = generic.output + codex.output + messages.values.reduce(0) { $0 + $1.output }
        return LogEstimate(inputTokens: input, outputTokens: output, recordsCounted: counted, linesSkipped: skipped, importedAt: now, methods: methods.sorted())
    }

    /// The first object holding a recognized token field, depth first. It is not searched further, so nested copies are not double counted.
    /// A present but invalid recognized field makes the record invalid; another nested object cannot replace it.
    private static func findUsage(_ value: Any, depth: Int) -> Found {
        guard depth < 5 else { return .none }
        if let dict = value as? [String: Any] {
            let found = pair(dict)
            if case .none = found {} else { return found }
            for key in dict.keys.sorted() {
                let nested = findUsage(dict[key]!, depth: depth + 1)
                if case .none = nested { continue }
                return nested
            }
        } else if let array = value as? [Any] {
            for item in array.prefix(64) {
                let nested = findUsage(item, depth: depth + 1)
                if case .none = nested { continue }
                return nested
            }
        }
        return .none
    }
    /// `.none` when no recognized field is present; `.invalid` when any present recognized field is not a safe whole number.
    private static func pair(_ dict: [String: Any]) -> Found {
        var input: UInt64?, output: UInt64?, present = false
        for (keys, isInput) in [(inputKeys, true), (outputKeys, false)] {
            for key in keys {
                guard let raw = dict[key] else { continue }
                present = true
                guard let value = token(raw) else { return .invalid }
                if isInput { input = input ?? value } else { output = output ?? value }
            }
        }
        return present ? .usage(Pair(input: input ?? 0, output: output ?? 0)) : .none
    }
    private static func token(_ value: Any) -> UInt64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let d = number.doubleValue
        guard d.isFinite, d >= 0, d <= maxTokensPerField, d == d.rounded() else { return nil }
        return UInt64(d)
    }
    public static func parseBudget(_ text: String) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{1,12}$"#, options: .regularExpression) != nil, let value = Int(trimmed), value > 0 else { throw AccountInputError.invalidBudget }
        return value
    }
}
