import Foundation

public struct TaskValue: Codable, Equatable, Sendable {
    public var title: String
    public var completed: Bool
    public var due: String?
    public init(_ title: String, completed: Bool = false, due: String? = nil) { self.title = title; self.completed = completed; self.due = due }
}
public struct MarkdownTask: Equatable {
    public let line: Int
    public let id: String?
    public let value: TaskValue
}
public enum TaskText {
    static let task = try! NSRegularExpression(pattern: #"^(\s*- \[)([ xX])(\] )(.*)$"#)
    static let identity = try! NSRegularExpression(pattern: #"\s*<!-- rv:([A-Za-z0-9-]+) -->"#)
    static let escaped = try! NSRegularExpression(pattern: #"\s*<!-- rv-escaped -->$"#)
    static let date = try! NSRegularExpression(pattern: #"\s*(?<!\\)📅 (\d{4}-\d{2}-\d{2})"#)
    static func matches(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) }
    static func part(_ s: String, _ m: NSTextCheckingResult, _ i: Int) -> String { (s as NSString).substring(with: m.range(at: i)) }
    // Protect reserved due-date syntax in titles imported from Reminders.
    static func encodedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "📅", with: "\\📅")
    }
    static func decodedTitle(_ title: String) -> String {
        var result = ""; var iterator = title.makeIterator()
        while let c = iterator.next() {
            if c == "\\", let next = iterator.next() {
                if next == "\\" || next == "📅" { result.append(next) }
                else { result.append(c); result.append(next) }
            } else { result.append(c) }
        }
        return result
    }
    public static func validDate(_ s: String) -> Bool {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: s).map { f.string(from: $0) == s } ?? false
    }
    public static func parse(_ text: String) -> [MarkdownTask] {
        var fence: Character?; var fenceLength = 0; var result: [MarkdownTask] = []
        for (line, raw) in text.components(separatedBy: "\n").enumerated() {
            let s = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if let c = trimmed.first, c == "`" || c == "~" {
                let n = trimmed.prefix(while: { $0 == c }).count
                if n >= 3 {
                    if fence == nil { fence = c; fenceLength = n; continue }
                    if fence == c && n >= fenceLength { fence = nil; continue }
                }
            }
            guard fence == nil, let m = matches(task, s) else { continue }
            var body = part(s, m, 4); var id: String?; var due: String?
            var encoded = false
            if let tag = matches(identity, body) { id = part(body, tag, 1); body = identity.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: "") }
            if let tag = matches(escaped, body) { encoded = true; body = (body as NSString).replacingCharacters(in: tag.range, with: "") }
            if let d = matches(date, body), validDate(part(body, d, 1)) { due = part(body, d, 1); body = (body as NSString).replacingCharacters(in: d.range, with: "") }
            result.append(MarkdownTask(line: line, id: id, value: TaskValue(encoded ? decodedTitle(body) : body, completed: part(s, m, 2) != " ", due: due)))
        }
        return result
    }
    /// Only the selected task line changes. Newlines and all other bytes are preserved.
    public static func replacing(_ text: String, line: Int, value: TaskValue, id: String) throws -> String {
        guard !value.title.contains("\n"), !value.title.contains("\r"), !value.title.contains("<!-- rv:"), !value.title.contains("<!-- rv-escaped -->"), !id.isEmpty,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              value.due.map(validDate) ?? true else { throw VaultError.invalidTask }
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line), parse(text).contains(where: { $0.line == line }), let m = matches(task, lines[line]) else { throw VaultError.changed }
        let cr = lines[line].hasSuffix("\r") ? "\r" : ""
        let old = parse(text).first { $0.line == line }!
        if old.value == value {
            if old.id == id { return text }
            let original = cr.isEmpty ? lines[line] : String(lines[line].dropLast())
            let withoutID = identity.stringByReplacingMatches(in: original, range: NSRange(original.startIndex..., in: original), withTemplate: "")
            lines[line] = withoutID + " <!-- rv:\(id) -->" + cr
        } else {
            lines[line] = part(lines[line], m, 1) + (value.completed ? "x" : " ") + part(lines[line], m, 3) + encodedTitle(value.title) + (value.due.map { " 📅 " + $0 } ?? "") + (encodedTitle(value.title) == value.title ? "" : " <!-- rv-escaped -->") + " <!-- rv:\(id) -->" + cr
        }
        return lines.joined(separator: "\n")
    }
    public static func appended(_ text: String, value: TaskValue, id: String) throws -> String {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let line = try replacing("- [ ] ", line: 0, value: value, id: id)
        return text + (text.isEmpty || text.hasSuffix("\n") ? "" : newline) + line + newline
    }
}
public enum VaultError: LocalizedError {
    case changed, invalidTask, noFolder, noList, duplicate, denied
    public var errorDescription: String? {
        switch self {
        case .changed: return "The vault or Reminders changed. Run Preview again before syncing."
        case .invalidTask: return "A task contains an unsupported line break, ID, or date."
        case .noFolder: return "Select your vault folder to begin."
        case .noList: return "Select at least one writable Reminders list in Settings."
        case .duplicate: return "Duplicate task IDs found. Remove the copied rv comment from one task, then preview again."
        case .denied: return "Reminders access is unavailable. Enable ReminderVault in System Settings → Privacy & Security → Reminders."
        }
    }
}
public enum Winner: String { case equal, markdown, reminder }
public struct Resolution {
    public let winner: Winner
    public let conflict: Bool
}
public enum Reconcile {
    public static func resolve(local: TaskValue, remote: TaskValue, baseline: TaskValue?, localDate: Date, remoteDate: Date) -> Resolution {
        if local == remote { return Resolution(winner: .equal, conflict: false) }
        let lc = baseline.map { local != $0 } ?? true
        let rc = baseline.map { remote != $0 } ?? true
        if lc && !rc { return Resolution(winner: .markdown, conflict: false) }
        if rc && !lc { return Resolution(winner: .reminder, conflict: false) }
        return Resolution(winner: localDate >= remoteDate ? .markdown : .reminder, conflict: lc && rc)
    }
}
