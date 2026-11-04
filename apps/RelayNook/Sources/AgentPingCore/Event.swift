import Foundation

public enum EventKind: String, Codable, CaseIterable, Sendable {
    case waiting, done, error, info
}

public struct AgentEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var receivedAt: Date
    public var agent: String
    public var kind: EventKind
    public var title: String
    public var project: String
    public var session: String

    public init(agent: String, kind: EventKind, title: String, project: String, session: String, receivedAt: Date = Date()) {
        id = UUID()
        self.receivedAt = receivedAt
        self.agent = agent
        self.kind = kind
        self.title = title
        self.project = project
        self.session = session
    }
}

public enum EventParser {
    public static let limits = ["agent": 64, "title": 240, "project": 240, "session": 128]

    public static func clamp(_ value: String, maximum: Int) -> String {
        let clean = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value) }
        return String(String(String.UnicodeScalarView(clean)).trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximum))
    }

    public static func parse(_ raw: String, token: String) -> AgentEvent? {
        guard token.utf8.count == 32, token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), raw.utf8.count <= 32768, validEscapes(raw),
              let c = URLComponents(string: raw), c.scheme == "agentping", c.host == "event",
              c.user == nil, c.password == nil, c.port == nil, c.path.isEmpty,
              c.fragment == nil, let items = c.queryItems, items.count == 6 else { return nil }
        let names = Set(["agent", "kind", "title", "project", "session", "token"])
        // Authenticate before storing any event text.
        guard items.first(where: { $0.name == "token" })?.value == token else { return nil }
        return parseComponents(items, names: names)
    }

    private static func parseComponents(_ items: [URLQueryItem], names: Set<String>) -> AgentEvent? {
        var fields: [String: String] = [:]
        for item in items {
            guard names.contains(item.name), fields[item.name] == nil, let value = item.value else { return nil }
            fields[item.name] = value
        }
        guard Set(fields.keys) == names, let kind = EventKind(rawValue: fields["kind"] ?? "") else { return nil }
        for (key, limit) in limits { fields[key] = clamp(fields[key] ?? "", maximum: limit) }
        guard let agent = fields["agent"], !agent.isEmpty,
              let title = fields["title"], !title.isEmpty,
              let session = fields["session"], !session.isEmpty else { return nil }
        return AgentEvent(agent: agent, kind: kind, title: title, project: fields["project"] ?? "", session: session)
    }

    private static func validEscapes(_ raw: String) -> Bool {
        let bytes = Array(raw.utf8)
        func hex(_ b: UInt8) -> Bool { (48...57).contains(b) || (65...70).contains(b) || (97...102).contains(b) }
        var i = 0
        while i < bytes.count {
            if bytes[i] == 37 {
                guard i + 2 < bytes.count, hex(bytes[i + 1]), hex(bytes[i + 2]) else { return false }
                i += 3
            } else { i += 1 }
        }
        return true
    }
}
