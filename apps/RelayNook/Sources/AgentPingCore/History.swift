import Foundation

public struct WaitingSession: Codable, Hashable, Sendable {
    public let agent: String?
    public let session: String
    public init(agent: String?, session: String) { self.agent = agent; self.session = session }
}

public struct History: Codable, Equatable, Sendable {
    public static let capacity = 200
    public private(set) var events: [AgentEvent] = []
    public private(set) var waitingSessions: Set<WaitingSession> = []
    public private(set) var unresolvedLegacySessions: Set<String> = []
    public private(set) var rejectedCount = 0
    public var waitingCount: Int { waitingSessions.count }
    public var unresolvedLegacyCount: Int { unresolvedLegacySessions.count }
    public init() {}

    private enum CodingKeys: String, CodingKey { case events, waitingSessions, unresolvedLegacySessions, rejectedCount }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedEvents = try container.decode([AgentEvent].self, forKey: .events)
        rejectedCount = try container.decode(Int.self, forKey: .rejectedCount)
        unresolvedLegacySessions = try container.decodeIfPresent(Set<String>.self, forKey: .unresolvedLegacySessions) ?? []
        if let keys = try? container.decode(Set<WaitingSession>.self, forKey: .waitingSessions) {
            // Migrate the previous nil-agent format without inventing an identity.
            waitingSessions = Set(keys.filter { $0.agent != nil })
            unresolvedLegacySessions.formUnion(keys.filter { $0.agent == nil }.map(\.session))
        } else {
            let legacy = try container.decode(Set<String>.self, forKey: .waitingSessions)
            // Reconstruct agent identity from the available chronological event history.
            for event in storedEvents {
                let key = WaitingSession(agent: event.agent, session: event.session)
                if event.kind == .waiting { waitingSessions.insert(key) }
                else { waitingSessions.remove(key) }
            }
            let represented = Set(storedEvents.map(\.session))
            // Retain unresolved older entries without assigning an invented agent.
            unresolvedLegacySessions.formUnion(legacy.subtracting(represented))
        }
        events = Array(storedEvents.suffix(Self.capacity))
    }

    public mutating func receive(_ event: AgentEvent) {
        let key = WaitingSession(agent: event.agent, session: event.session)
        if event.kind == .waiting { waitingSessions.insert(key) }
        else { waitingSessions.remove(key) }
        events.append(event)
        if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
    }
    public mutating func reject() {
        if rejectedCount < Int.max { rejectedCount += 1 }
    }
    public mutating func dismissUnresolvedLegacySessions() { unresolvedLegacySessions.removeAll() }
    public mutating func clear() {
        events.removeAll(); waitingSessions.removeAll(); unresolvedLegacySessions.removeAll()
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> History {
        var result = try JSONDecoder().decode(History.self, from: Data(contentsOf: url))
        result.events = Array(result.events.suffix(capacity))
        return result
    }
}

public struct Preferences: Codable, Equatable {
    public var enabledKinds = Set(EventKind.allCases)
    public var sound = false
    public init() {}
    public func permits(_ kind: EventKind) -> Bool { enabledKinds.contains(kind) }
}
