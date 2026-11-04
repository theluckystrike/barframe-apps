import Foundation

public struct AcceptedEvent: Sendable {
    public let event: AgentEvent
    public let shouldNotify: Bool
}

/// Bound authenticated ingress and notification volume independently of history.
public struct EventIngress: Sendable {
    private let token: String
    private var acceptedDates: [Date] = []
    private struct NotificationKey: Hashable, Sendable {
        let agent: String
        let session: String
        let kind: EventKind
        let title: String
        let project: String
    }
    private var notifications: [NotificationKey: Date] = [:]
    public init(token: String) { self.token = token }

    public mutating func receive(_ raw: String, now: Date = Date()) -> AcceptedEvent? {
        guard let event = EventParser.parse(raw, token: token) else { return nil }
        acceptedDates.removeAll { now.timeIntervalSince($0) >= 60 }
        guard acceptedDates.count < 30 else { return nil }
        acceptedDates.append(now)
        notifications = notifications.filter { now.timeIntervalSince($0.value) < 10 }
        let key = NotificationKey(agent: event.agent, session: event.session, kind: event.kind, title: event.title, project: event.project)
        let shouldNotify = notifications[key] == nil
        if shouldNotify { notifications[key] = now }
        var timestamped = event
        timestamped.receivedAt = now
        return AcceptedEvent(event: timestamped, shouldNotify: shouldNotify)
    }
}
