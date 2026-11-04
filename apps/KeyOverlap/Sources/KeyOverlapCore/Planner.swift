import Foundation

public enum PlanError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let value) = self { return value }; return nil }
}

public struct Chord: Codable, Equatable, Hashable {
    public let key: String
    public let modifiers: [String]
    public static let order = ["control", "option", "shift", "command"]
    public init(key: String, modifiers: [String]) throws {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases = ["esc": "escape", "enter": "return", "spacebar": "space", "plus": "+"]
        let canonical = aliases[cleaned] ?? cleaned
        let names = ["escape", "return", "space", "tab", "delete", "forwarddelete", "up", "down", "left", "right", "home", "end", "pageup", "pagedown"] + (1...20).map { "f\($0)" }
        let single = canonical.utf8.count == 1 && "abcdefghijklmnopqrstuvwxyz0123456789`-=[]\\;',./+".contains(canonical)
        guard !canonical.isEmpty, single || names.contains(canonical) else { throw PlanError.invalid("Use one letter, digit, punctuation key or a named key such as space or F5.") }
        let mods = modifiers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard mods.allSatisfy(Self.order.contains), Set(mods).count == mods.count else { throw PlanError.invalid("Modifiers must be unique command, option, shift or control values.") }
        self.key = canonical
        self.modifiers = Self.order.filter(mods.contains)
    }
    public static func parse(_ input: String) throws -> Chord {
        let parts = input.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty else { throw PlanError.invalid("Enter a chord such as command+option+k.") }
        return try Chord(key: key, modifiers: Array(parts.dropLast()))
    }
    public var text: String { (modifiers + [key == "+" ? "plus" : key]).joined(separator: "+") }
    public var display: String { display(language: "en") }
    public func display(language: String) -> String {
        let symbols = ["control":"⌃", "option":"⌥", "shift":"⇧", "command":"⌘"]
        let keys = ["space":"Space", "escape":"Esc", "return":"Return", "tab":"Tab", "delete":"Delete", "forwarddelete":"Forward Delete", "up":"↑", "down":"↓", "left":"←", "right":"→", "home":"Home", "end":"End", "pageup":"Page Up", "pagedown":"Page Down"]
        return modifiers.compactMap { symbols[$0] }.joined() + PlanText.translate(keys[key] ?? key.uppercased(), language: language)
    }
}

public struct ShortcutRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public let command: String
    public let chord: Chord
    public let scope: String?
    public let context: String?
    public init(id: UUID = UUID(), command: String, key: String, modifiers: [String], scope: String?, context: String?) throws {
        let name = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PlanError.invalid("Enter a command name.") }
        let cleanScope = Self.clean(scope)
        let cleanContext = Self.clean(context)
        guard cleanScope != "*" || cleanContext == nil else { throw PlanError.invalid("A global scope cannot have an app context.") }
        guard cleanScope != nil || cleanContext == nil else { throw PlanError.invalid("Give a context an app scope.") }
        self.id = id; self.command = name
        self.chord = try Chord(key: key, modifiers: modifiers)
        self.scope = cleanScope; self.context = cleanContext
    }
    public static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    public var searchText: String { [command, scope ?? "", context ?? "", chord.text, chord.display].joined(separator: " ") }
    public func replacing(with chord: Chord) throws -> ShortcutRecord {
        try ShortcutRecord(id: id, command: command, key: chord.key, modifiers: chord.modifiers, scope: scope, context: context)
    }
}

public struct ExclusiveContexts: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public let app: String
    public let first: String
    public let second: String
    public init(app: String, first: String, second: String) throws {
        guard let app = ShortcutRecord.clean(app), app != "*", let first = ShortcutRecord.clean(first), let second = ShortcutRecord.clean(second), first.lowercased() != second.lowercased() else { throw PlanError.invalid("Enter an app and two different contexts.") }
        self.app = app; self.first = first; self.second = second
    }
    public func separates(_ a: ShortcutRecord, _ b: ShortcutRecord) -> Bool {
        guard a.scope?.lowercased() == app.lowercased(), b.scope?.lowercased() == app.lowercased(), let ac = a.context?.lowercased(), let bc = b.context?.lowercased() else { return false }
        let pair = Set([first.lowercased(), second.lowercased()])
        return ac != bc && pair == Set([ac, bc])
    }
}

public enum OverlapKind: String, Codable, CaseIterable { case definite, possible, separate }
public struct Overlap: Identifiable, Equatable {
    public let first: ShortcutRecord
    public let second: ShortcutRecord
    public let kind: OverlapKind
    public let exclusive: Bool
    public var id: String { first.id.uuidString + second.id.uuidString }
}
public enum OverlapEngine {
    public static func compare(_ a: ShortcutRecord, _ b: ShortcutRecord, contexts: [ExclusiveContexts] = []) -> Overlap? {
        guard a.chord == b.chord else { return nil }
        if a.scope == "*" || b.scope == "*" { return Overlap(first: a, second: b, kind: .definite, exclusive: false) }
        guard let ascope = a.scope, let bscope = b.scope else { return Overlap(first: a, second: b, kind: .possible, exclusive: false) }
        if ascope.lowercased() != bscope.lowercased() { return Overlap(first: a, second: b, kind: .separate, exclusive: false) }
        let separated = contexts.contains { $0.separates(a, b) }
        return Overlap(first: a, second: b, kind: separated ? .separate : .definite, exclusive: separated)
    }
    public static func overlaps(_ records: [ShortcutRecord], contexts: [ExclusiveContexts] = []) -> [Overlap] {
        records.enumerated().flatMap { i, first in records.dropFirst(i + 1).compactMap { compare(first, $0, contexts: contexts) } }
    }
    public static func candidate(_ proposed: ShortcutRecord, in records: [ShortcutRecord], contexts: [ExclusiveContexts] = []) -> [Overlap] {
        records.compactMap { compare(proposed, $0, contexts: contexts) }
    }
    public static func search(_ records: [ShortcutRecord], query: String) -> [ShortcutRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let chord = try? Chord.parse(q)
        return q.isEmpty ? records : records.filter { $0.searchText.localizedCaseInsensitiveContains(q) || (chord != nil && $0.chord == chord) }
    }
}

public struct Replacement: Codable, Equatable, Identifiable {
    public let recordID: UUID
    public let chord: Chord
    public var id: UUID { recordID }
    public init(recordID: UUID, chord: Chord) { self.recordID = recordID; self.chord = chord }
}
public struct ShortcutPlan: Codable, Equatable {
    public var records: [ShortcutRecord]
    public var contexts: [ExclusiveContexts]
    public var replacements: [Replacement]
    public init(records: [ShortcutRecord] = [], contexts: [ExclusiveContexts] = [], replacements: [Replacement] = []) {
        self.records = records; self.contexts = contexts; self.replacements = replacements
    }
    public func validated() throws -> ShortcutPlan {
        guard Set(records.map(\.id)).count == records.count, Set(replacements.map(\.recordID)).count == replacements.count else { throw PlanError.invalid("The saved plan contains duplicate identifiers.") }
        for row in records { _ = try ShortcutRecord(id: row.id, command: row.command, key: row.chord.key, modifiers: row.chord.modifiers, scope: row.scope, context: row.context) }
        for row in contexts { _ = try ExclusiveContexts(app: row.app, first: row.first, second: row.second) }
        for row in replacements {
            guard records.contains(where: { $0.id == row.recordID }) else { throw PlanError.invalid("A replacement refers to a missing record.") }
            _ = try Chord(key: row.chord.key, modifiers: row.chord.modifiers)
        }
        return self
    }
    public var proposedRecords: [ShortcutRecord] {
        records.map { record in
            guard let replacement = replacements.first(where: { $0.recordID == record.id }) else { return record }
            return (try? record.replacing(with: replacement.chord)) ?? record
        }
    }
    public mutating func stage(id: UUID, chord: Chord) throws {
        guard let record = records.first(where: { $0.id == id }) else { throw PlanError.invalid("Select a saved record before staging a replacement.") }
        replacements.removeAll { $0.recordID == id }
        if record.chord != chord { replacements.append(Replacement(recordID: id, chord: chord)) }
    }
    public mutating func apply() { records = proposedRecords; replacements = [] }
    public mutating func remove(id: UUID) { records.removeAll { $0.id == id }; replacements.removeAll { $0.recordID == id } }
    public var checklist: String { checklist(language: "en") }
    public func checklist(language: String) -> String {
        func t(_ value: String) -> String { PlanText.translate(value, language: language) }
        let lines = replacements.compactMap { change -> String? in
            guard let record = records.first(where: { $0.id == change.recordID }) else { return nil }
            return "☐ \(record.command) \(t("in")) \(record.scope == "*" ? t("Global") : record.scope ?? t("Unknown scope"))\(record.context.map { " · " + $0 } ?? "")\n   \(record.chord.display(language: language)) → \(change.chord.display(language: language))"
        }
        return t("KeyOverlap manual change checklist") + "\n" + t("These changes affect your local plan only. Set each shortcut manually in its target app.") + "\n\n" + lines.joined(separator: "\n\n")
    }
    public static func sample() -> ShortcutPlan {
        func row(_ name: String, _ key: String, _ modifiers: [String], _ scope: String?, _ context: String? = nil) -> ShortcutRecord {
            try! ShortcutRecord(command: name, key: key, modifiers: modifiers, scope: scope, context: context)
        }
        let records = [row("Capture panel", "5", ["command", "shift"], "*"), row("Build preview", "5", ["shift", "command"], "Orbit Editor"),
                       row("Open palette", "k", ["command"], "Orbit Editor"), row("Find layer", "K", ["command"], "Mosaic Canvas"),
                       row("Format selection", "d", ["command"], "Orbit Editor", "Edit"), row("Step through", "d", ["command"], "Orbit Editor", "Debug"),
                       row("Archive note", "j", ["option", "command"], nil), row("Jump to outline", "j", ["command", "option"], "Quill Notes")]
        return ShortcutPlan(records: records, contexts: [try! ExclusiveContexts(app: "Orbit Editor", first: "Edit", second: "Debug")], replacements: [Replacement(recordID: records[0].id, chord: try! Chord(key: "6", modifiers: ["command", "shift"]))])
    }
}

public enum PlanImport {
    public static let template = """
    [
      {"command":"Open palette","key":"k","modifiers":["command"],"scope":"Orbit Editor","context":null},
      {"command":"Capture panel","key":"5","modifiers":["command","shift"],"scope":"*","context":null}
    ]
    """
    public static func decode(_ data: Data) throws -> [ShortcutRecord] {
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw PlanError.invalid("The file is not valid JSON. \(error.localizedDescription)") }
        guard let rows = root as? [Any] else { throw PlanError.invalid("The root must be a JSON array.") }
        let fields = Set(["command", "key", "modifiers", "scope", "context"])
        return try rows.enumerated().map { index, value in
            do {
                guard let row = value as? [String: Any], Set(row.keys) == fields,
                      let command = row["command"] as? String, let key = row["key"] as? String,
                      let modifiers = row["modifiers"] as? [String],
                      row["scope"] is String || row["scope"] is NSNull,
                      row["context"] is String || row["context"] is NSNull else { throw PlanError.invalid("Use exactly command, key, modifiers, scope and context with the documented types.") }
                return try ShortcutRecord(command: command, key: key, modifiers: modifiers, scope: row["scope"] as? String, context: row["context"] as? String)
            } catch { throw PlanError.invalid("Row index \(index) · \(error.localizedDescription)") }
        }
    }
    public static func importing(_ data: Data, into plan: ShortcutPlan) throws -> ShortcutPlan {
        let records = try decode(data)
        return ShortcutPlan(records: records, contexts: plan.contexts, replacements: [])
    }
}
