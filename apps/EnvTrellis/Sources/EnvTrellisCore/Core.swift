import Foundation

public enum Presence: String, Codable, Sendable { case present = "Present", empty = "Empty" }
public enum Rule: String, Codable, CaseIterable, Sendable { case required = "Required", optional = "Optional", forbidden = "Forbidden" }
public struct ParseIssue: Codable, Equatable, Sendable {
    public var line: Int
    public var kind: String
    public init(_ line: Int, _ kind: String) { self.line = line; self.kind = kind }
}
public struct KeyEntry: Codable, Equatable, Sendable {
    public var presence: Presence
    public var lines: [Int]
    public init(_ presence: Presence, _ lines: [Int]) { self.presence = presence; self.lines = lines }
}
public struct ParsedFile: Codable, Equatable, Sendable {
    public var keys: [String: KeyEntry] = [:]
    public var issues: [ParseIssue] = []
    public init() {}
}
/// Only key names, presence and line numbers leave this parser. No evaluation occurs.
public enum DotenvParser {
    public static func parse(_ text: String) -> ParsedFile {
        var result = ParsedFile()
        for (index, raw) in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n").enumerated() {
            let number = index + 1
            var line = raw.trimmingCharacters(in: .whitespaces)
            if number == 1, line.hasPrefix("\u{feff}") { line.removeFirst() }
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") || line.hasPrefix("export\t") {
                line = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            }
            guard let equal = line.firstIndex(of: "=") else { result.issues.append(ParseIssue(number, "Unsupported syntax")); continue }
            let key = String(line[..<equal]).trimmingCharacters(in: .whitespaces)
            guard validKey(key) else { result.issues.append(ParseIssue(number, "Invalid key syntax")); continue }
            let value = String(line[line.index(after: equal)...]).trimmingCharacters(in: .whitespaces)
            var empty = true
            var supported = true
            if let quote = value.first, quote == "\"" || quote == "'" {
                var escaped = false
                var closing: String.Index?
                for pos in value.indices.dropFirst() {
                    let char = value[pos]
                    if escaped { empty = false; escaped = false; continue }
                    if char == "\\", quote == "\"" { escaped = true; continue }
                    if char == quote { closing = pos; break }
                    if char == "$" || char == "`" { supported = false }
                    empty = false
                }
                if let closing {
                    let tail = value[value.index(after: closing)...].trimmingCharacters(in: .whitespaces)
                    if !tail.isEmpty && !tail.hasPrefix("#") { supported = false }
                } else { supported = false }
            } else {
                var content = value
                if let hash = content.firstIndex(of: "#") { content = String(content[..<hash]).trimmingCharacters(in: .whitespaces) }
                empty = content.isEmpty
                if content.contains("$") || content.contains("`") || content.hasSuffix("\\") || content.contains("\"") || content.contains("'") { supported = false }
            }
            if !supported { result.issues.append(ParseIssue(number, "Unsupported value syntax")) }
            if var existing = result.keys[key] {
                existing.lines.append(number)
                result.keys[key] = existing
                result.issues.append(ParseIssue(number, "Duplicate key \(key)"))
            } else { result.keys[key] = KeyEntry(empty ? .empty : .present, [number]) }
        }
        return result
    }
    public static func validKey(_ key: String) -> Bool {
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
}
public struct FileStamp: Codable, Equatable, Sendable {
    public var modified: Date
    public var size: Int
    public init(modified: Date, size: Int) { self.modified = modified; self.size = size }
}
public struct InputFile: Codable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var bookmark: Data
    public var stamp: FileStamp?
    public var parsed: ParsedFile?
    public var unavailable: Bool
    public init(label: String, bookmark: Data = Data()) {
        id = UUID(); self.label = label; self.bookmark = bookmark; unavailable = false
    }
}
public enum Readiness: String, Codable, Sendable { case noInputs = "Choose inputs", stale = "Stale", unknown = "Unknown", findings = "Findings", ready = "Ready" }
public struct Project: Codable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var template: InputFile?
    public var environments: [InputFile]
    public var rules: [UUID: [String: Rule]]
    public var lastScan: Date?
    public var stale: Bool
    public init(label: String) { id = UUID(); self.label = label; environments = []; rules = [:]; stale = false }
    public var keys: [String] {
        var set = Set(template?.parsed?.keys.keys.map { $0 } ?? [])
        for file in environments { set.formUnion(file.parsed?.keys.keys.map { $0 } ?? []); set.formUnion(rules[file.id]?.keys.map { $0 } ?? []) }
        return set.sorted()
    }
    public func outcome(key: String, environment: InputFile) -> String {
        guard !environment.unavailable, let parsed = environment.parsed else { return "Unknown" }
        guard let rule = rules[environment.id]?[key] else { return "Decide rule" }
        let entry = parsed.keys[key]
        switch rule {
        case .required: return entry == nil ? "Missing required" : entry?.presence == .empty ? "Empty required" : "Pass"
        case .optional: return "Pass"
        case .forbidden: return entry == nil ? "Pass" : "Forbidden present"
        }
    }
    public var readiness: Readiness {
        guard let template, !environments.isEmpty else { return .noInputs }
        if stale { return .stale }
        guard lastScan != nil, !template.unavailable, template.parsed != nil,
              environments.allSatisfy({ !$0.unavailable && $0.parsed != nil }) else { return .unknown }
        if !(template.parsed?.issues.isEmpty ?? false) || environments.contains(where: { !($0.parsed?.issues.isEmpty ?? false) }) { return .findings }
        if keys.contains(where: { key in environments.contains(where: { outcome(key: key, environment: $0) != "Pass" }) }) { return .findings }
        return .ready
    }
    public func report(sample: Bool, maskLabels: Bool = false) -> String {
        let title = maskLabels ? "Project" : label
        var lines = [sample ? "Sample release readiness report" : "Release readiness report", title, "State \(readiness.rawValue)"]
        lines.append(lastScan.map { "Last scan \(ISO8601DateFormatter().string(from: $0))" } ?? "No completed scan")
        if let template {
            lines.append("Template \(template.unavailable || template.parsed == nil ? "Unknown choose again" : "Available")")
            for issue in template.parsed?.issues ?? [] { lines.append("Template line \(issue.line) \(issue.kind)") }
        } else { lines.append("Template Unknown choose inputs") }
        for (index, environment) in environments.enumerated() {
            let label = maskLabels ? "Environment \(index + 1)" : environment.label
            lines.append(label)
            if environment.unavailable || environment.parsed == nil { lines.append("Unknown choose again"); continue }
            for key in keys {
                let entry = environment.parsed?.keys[key]
                let state = entry?.presence.rawValue ?? "Absent"
                let positions = entry?.lines.map(String.init).joined(separator: ", ") ?? "none"
                lines.append("\(key)  \(rules[environment.id]?[key]?.rawValue ?? "Decide rule")  \(state)  \(outcome(key: key, environment: environment))  lines \(positions)")
            }
            for issue in environment.parsed?.issues ?? [] { lines.append("Line \(issue.line) \(issue.kind)") }
        }
        if environments.isEmpty { lines.append("Environments Unknown choose inputs") }
        return lines.joined(separator: "\n")
    }
}
public struct SavedState: Codable, Sendable {
    public var projects: [Project]
    public var pinned: UUID?
    public init(projects: [Project] = [], pinned: UUID? = nil) { self.projects = projects; self.pinned = pinned }
    public static func decode(_ data: Data) throws -> SavedState { try JSONDecoder().decode(SavedState.self, from: data) }
    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}
public enum SampleFixtures {
    public static let template = "DATABASE_URL=\nDEBUG=\nMODE=\n"
    public static let development = "DATABASE_URL=fixture_secret_dev\nDEBUG=true\nMODE=development\nMODE=duplicate_fixture\n"
    public static let staging = "DEBUG=\nMODE=staging\n"
    public static let production = "DATABASE_URL=fixture_secret_prod\nDEBUG=true\nMODE=production\n"
    public static func project() -> Project {
        var project = Project(label: "Sample release")
        var templateFile = InputFile(label: "Template"); templateFile.parsed = DotenvParser.parse(template)
        project.template = templateFile
        for (label, text) in [("Development", development), ("Staging", staging), ("Production", production)] {
            var input = InputFile(label: label); input.parsed = DotenvParser.parse(text)
            project.environments.append(input)
            project.rules[input.id] = ["DATABASE_URL": .required, "MODE": .required, "DEBUG": label == "Production" ? .forbidden : .optional]
        }
        project.lastScan = Date()
        return project
    }
}
