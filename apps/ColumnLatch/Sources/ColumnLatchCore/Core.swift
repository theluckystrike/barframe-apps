import Foundation

public enum CSVError: Error, Equatable, LocalizedError {
    case malformed(Int), encoding, tooLarge, empty, duplicateHeader
    public var errorDescription: String? {
        switch self {
        case .malformed(let n): return "Malformed CSV at logical record \(n). Check quotes and delimiters."
        case .encoding: return "Unsupported encoding. Choose a UTF8 CSV file."
        case .tooLarge: return "Unsupported size. The limit is 20 MB."
        case .empty: return "No header found. Choose a CSV with named columns."
        case .duplicateHeader: return "Duplicate or empty header names block validation."
        }
    }
}
public enum CSV {
    public static let limit = 20 * 1024 * 1024
    // Incremental record callback avoids retaining source rows after validation.
    public static func read(_ data: Data, delimiter: Character = ",", cancelled: () -> Bool = { false }, record: ([String], Int) throws -> Void) throws {
        guard data.count <= limit else { throw CSVError.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw CSVError.encoding }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        var fields: [String] = [], field = "", quoted = false, closed = false, atStart = true, number = 1, pending = false
        var it = text.makeIterator()
        while let c = it.next() {
            if cancelled() { throw CancellationError() }
            pending = true
            if quoted {
                if c == "\"" { quoted = false; closed = true } else { field.append(c) }
            } else if closed && c == "\"" {
                quoted = true; closed = false; field.append("\"")
            } else if c == delimiter {
                fields.append(field); field = ""; atStart = true; closed = false
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                fields.append(field); try record(fields, number); number += 1
                fields = []; field = ""; atStart = true; closed = false; pending = false
            } else if c == "\"" && atStart {
                quoted = true; atStart = false
            } else {
                if closed || c == "\"" { throw CSVError.malformed(number) }
                field.append(c); atStart = false
            }
        }
        if quoted { throw CSVError.malformed(number) }
        if pending { fields.append(field); try record(fields, number) }
    }
    public static func header(_ data: Data, delimiter: Character) throws -> [String] {
        enum Stop: Error { case done }
        var header: [String] = []
        do { try read(data, delimiter: delimiter) { row, _ in header = row; throw Stop.done } } catch Stop.done {}
        guard !header.isEmpty else { throw CSVError.empty }
        guard !header.contains("") && Set(header).count == header.count else { throw CSVError.duplicateHeader }
        return header
    }
}
public enum ValueKind: String, Codable, CaseIterable { case text = "Text", integer = "Integer", decimal = "Decimal", allowed = "Allowed values" }
public struct Rule: Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var required = true
    public var kind: ValueKind = .text
    public var allowEmpty = false
    public var allowed: [String] = []
    public init(_ name: String, required: Bool = true, kind: ValueKind = .text, allowEmpty: Bool = false, allowed: [String] = []) { self.name = name; self.required = required; self.kind = kind; self.allowEmpty = allowEmpty; self.allowed = allowed }
    public func accepts(_ value: String) -> Bool {
        if value.isEmpty { return allowEmpty }
        switch kind {
        case .text: return true
        case .integer: return value.range(of: #"\A[+-]?[0-9]+\z"#, options: .regularExpression) != nil
        case .decimal: return value.range(of: #"\A[+-]?[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil
        case .allowed: return allowed.contains(value)
        }
    }
}
public struct Contract: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var rules: [Rule]
    public var uniqueKey = ""
    public var unexpectedFails = false
    public var delimiter = ","
    public init(name: String, rules: [Rule]) { self.name = name; self.rules = rules }
    public static var sample: Contract {
        var c = Contract(name: "Sample supplier", rules: [Rule("item_id"), Rule("quantity", kind: .integer), Rule("status", required: false, kind: .allowed, allowed: ["Yes", "No"])])
        c.uniqueKey = "item_id"; return c
    }
}
public struct Finding: Codable, Equatable, Identifiable {
    public var id: String { "\(category)|\(column)|\(records)" }
    public let category: String
    public let column: String
    public let records: [Int]
    public let failure: Bool
    public init(_ category: String, _ column: String, _ records: [Int] = [], failure: Bool = true) { self.category = category; self.column = column; self.records = records; self.failure = failure }
    public var categoryKey: String { category + " · " + column }
}
public struct Summary: Codable, Equatable {
    public var timestamp = Date()
    public var complete: Bool
    public var rows: Int
    public var findings: [Finding]
    public var optionalAbsent: [String]
    public var newCategories: [String] = []
    public var contractSnapshot: Contract?
    public var failed: Bool { findings.contains { $0.failure } }
    public var categories: Set<String> { Set(findings.filter(\.failure).map(\.categoryKey)) }
    public init(complete: Bool, rows: Int, findings: [Finding], optionalAbsent: [String] = []) { self.complete = complete; self.rows = rows; self.findings = findings; self.optionalAbsent = optionalAbsent }
    public func report(contract: Contract, sample: Bool) -> String {
        let contract = contractSnapshot ?? contract
        let rules = contract.rules.map { "\($0.name) · \($0.required ? "Required" : "Optional") · \($0.kind.rawValue) · empty \($0.allowEmpty ? "allowed" : "fails")" }.joined(separator: "\n")
        let details = findings.map { "\($0.failure ? "FAIL" : "WARN") · \($0.category) · \($0.column) · records \($0.records.map(String.init).joined(separator: ", "))" }.joined(separator: "\n")
        return "\(sample ? "Sample " : "")ColumnLatch acceptance report\n\(contract.name)\n\(ISO8601DateFormatter().string(from: timestamp))\n\(complete ? "Complete" : "Incomplete") · \(rows) data records checked\nValues redacted\nUnique key · \(contract.uniqueKey.isEmpty ? "None" : contract.uniqueKey)\nUnexpected columns · \(contract.unexpectedFails ? "Fail" : "Warn")\n\(rules)\nOptional absent · \(optionalAbsent.joined(separator: ", "))\n\(details)\nNew failing categories · \(newCategories.joined(separator: ", "))"
    }
}
public enum Validator {
    public static let sampleData = Data("item_id,quantity\n001,12\n002,many\n001,4\n".utf8)
    public static func run(_ data: Data, contract: Contract, cancelled: () -> Bool = { false }) throws -> Summary {
        var headers: [String] = [], findings: [Finding] = [], rows = 0, optional: [String] = []
        var keys: [String: [Int]] = [:]
        try CSV.read(data, delimiter: contract.delimiter.first ?? ",", cancelled: cancelled) { row, number in
            if number == 1 {
                headers = row
                guard !headers.contains("") && Set(headers).count == headers.count else { throw CSVError.duplicateHeader }
                for rule in contract.rules where !headers.contains(rule.name) {
                    if rule.required { findings.append(Finding("Missing column", rule.name)) } else { optional.append(rule.name) }
                }
                if !contract.uniqueKey.isEmpty && !headers.contains(contract.uniqueKey) && !findings.contains(where: { $0.column == contract.uniqueKey }) { findings.append(Finding("Missing key column", contract.uniqueKey)) }
                for h in headers where !contract.rules.contains(where: { $0.name == h }) { findings.append(Finding("Unexpected column", h, failure: contract.unexpectedFails)) }
                return
            }
            rows += 1
            guard row.count == headers.count else { findings.append(Finding("Malformed width", "Record", [number])); return }
            for rule in contract.rules {
                guard let i = headers.firstIndex(of: rule.name) else { continue }
                if !rule.accepts(row[i]) { findings.append(Finding(row[i].isEmpty ? "Empty value" : "Invalid value", rule.name, [number])) }
            }
            if let i = headers.firstIndex(of: contract.uniqueKey) {
                if row[i].isEmpty { findings.append(Finding("Empty key", contract.uniqueKey, [number])) }
                else { keys[row[i], default: []].append(number) }
            }
        }
        guard !headers.isEmpty else { throw CSVError.empty }
        for group in keys.values.filter({ $0.count > 1 }).sorted(by: { $0[0] < $1[0] }) { findings.append(Finding("Duplicate key", contract.uniqueKey, group)) }
        var summary = Summary(complete: true, rows: rows, findings: findings, optionalAbsent: optional)
        summary.contractSnapshot = contract
        return summary
    }
    public static func compare(_ current: Summary, previous: Summary?) -> Summary {
        var result = current
        result.newCategories = Array(current.categories.subtracting(previous?.categories ?? [])).sorted()
        return result
    }
}
public struct SavedState: Codable {
    public var contracts: [Contract] = []
    public var baselines: [String: Summary] = [:]
    public var bookmarks: [String: Data] = [:]
    public var pinned: UUID?
    public init() {}
    public mutating func commit(_ summary: Summary, contract: Contract) {
        if summary.complete { baselines[contract.id.uuidString] = summary }
    }
}
public enum StateStore {
    public static func save(_ state: SavedState, at url: URL) throws { try JSONEncoder().encode(state).write(to: url, options: .atomic) }
    public static func load(at url: URL) throws -> SavedState { try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url)) }
}

public enum InputReader {
    public static func read(_ url: URL, cancelled: () -> Bool = { false }) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        if let size = values.fileSize, size > CSV.limit { throw CSVError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            if cancelled() { throw CancellationError() }
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            data.append(chunk)
            if data.count > CSV.limit { throw CSVError.tooLarge }
        }
        return data
    }
}
