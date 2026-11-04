import Foundation

public enum Phase: String, Codable, Sendable { case queued, running, paused }
public struct Interruption: Codable, Equatable, Sendable {
    public var note: String
    public var date: Date
    public init(_ note: String, date: Date = Date()) { self.note = note; self.date = date }
}
public struct Action: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var estimate: Double
    public var active: Double
    public var target: Double
    public var phase: Phase
    public var notes: [Interruption]
    public var remaining: Double { target - active }
    public init(id: UUID = UUID(), title: String, minutes: Double) {
        self.id = id; self.title = title; estimate = minutes * 60; target = estimate
        active = 0; phase = .queued; notes = []
    }
}
public struct Record: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { action.id }
    public var action: Action
    public var date: Date
    public var index: Int
}
public enum QueueError: Error, Equatable { case invalidTitle, invalidDuration, invalidNote, busy, missing }
public struct Queue: Codable, Equatable, Sendable {
    public var actions: [Action] = []
    public var history: [Record] = []
    public var budget: Double = 25 * 60
    public var selectedID: UUID?
    public var lastTick: Double?
    public init() {}
    public var current: Action? { actions.first { $0.id == selectedID } }
    public mutating func add(title: String, minutes: Double) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { throw QueueError.invalidTitle }
        guard minutes.isFinite, minutes > 0, minutes <= 1440 else { throw QueueError.invalidDuration }
        actions.append(Action(title: title, minutes: minutes))
    }
    public mutating func edit(_ id: UUID, title: String, minutes: Double) throws {
        guard let i = actions.firstIndex(where: { $0.id == id }) else { throw QueueError.missing }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 120 else { throw QueueError.invalidTitle }
        guard minutes.isFinite, minutes > 0, minutes <= 1440 else { throw QueueError.invalidDuration }
        actions[i].title = clean
        actions[i].target = actions[i].active + minutes * 60
        if actions[i].active == 0 { actions[i].estimate = minutes * 60 }
    }
    public mutating func start(_ id: UUID? = nil, now: Double) throws {
        guard current == nil else { throw QueueError.busy }
        guard let i = actions.firstIndex(where: { $0.id == (id ?? actions.first?.id) }) else { throw QueueError.missing }
        selectedID = actions[i].id
        // Recovery always presents the saved place before charging more active time.
        actions[i].phase = actions[i].notes.isEmpty ? .running : .paused
        lastTick = actions[i].phase == .running ? now : nil
    }
    public mutating func tick(_ now: Double) {
        guard now.isFinite, let previous = lastTick, let i = actions.firstIndex(where: { $0.id == selectedID }), actions[i].phase == .running else { return }
        guard now >= previous else { return }
        actions[i].active += now - previous; lastTick = now
    }
    public mutating func interrupt(note: String, now: Double, date: Date = Date()) throws {
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 240 else { throw QueueError.invalidNote }
        guard let i = actions.firstIndex(where: { $0.id == selectedID }), actions[i].phase == .running else { throw QueueError.missing }
        tick(now); actions[i].phase = .paused; actions[i].notes.append(Interruption(clean, date: date)); lastTick = nil
    }
    public mutating func resume(now: Double) throws {
        guard let i = actions.firstIndex(where: { $0.id == selectedID }), actions[i].phase == .paused else { throw QueueError.missing }
        actions[i].phase = .running; lastTick = now
    }
    public mutating func sleep(now: Double) {
        if current?.phase == .running { try? interrupt(note: "Paused for sleep", now: now) }
    }
    public mutating func recoverAfterLaunch() {
        if let i = actions.firstIndex(where: { $0.id == selectedID }), actions[i].phase == .running {
            actions[i].phase = .paused; actions[i].notes.append(Interruption("Paused when the app closed"))
        }
        lastTick = nil
    }
    public mutating func finish(now: Double, date: Date = Date()) throws {
        guard let i = actions.firstIndex(where: { $0.id == selectedID }) else { throw QueueError.missing }
        tick(now); history.append(Record(action: actions.remove(at: i), date: date, index: i)); selectedID = nil; lastTick = nil
    }
    public mutating func undo() throws {
        guard let record = history.popLast() else { throw QueueError.missing }
        var action = record.action; action.phase = .queued
        if action.notes.isEmpty { action.notes.append(Interruption("Completion undone. Review your place before resuming.")) }
        actions.insert(action, at: min(record.index, actions.count))
    }
    public mutating func deferCurrent(now: Double) throws {
        guard let i = actions.firstIndex(where: { $0.id == selectedID }) else { throw QueueError.missing }
        tick(now); var action = actions.remove(at: i); action.phase = .queued
        actions.append(action); selectedID = nil; lastTick = nil
    }
    public mutating func reviseRemaining(minutes: Double, now: Double) throws {
        guard let id = selectedID, let title = current?.title else { throw QueueError.missing }
        guard minutes.isFinite, minutes > 0, minutes <= 1440 else { throw QueueError.invalidDuration }
        tick(now); try edit(id, title: title, minutes: minutes)
    }
    public mutating func move(_ id: UUID, by offset: Int) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        let destination = max(0, min(actions.count - 1, index + offset))
        let action = actions.remove(at: index); actions.insert(action, at: destination)
    }
    public mutating func delete(_ id: UUID) {
        guard id != selectedID else { return }; actions.removeAll { $0.id == id }
    }
    public var fittingIDs: Set<UUID> {
        guard budget.isFinite, budget > 0 else { return [] }
        var used = 0.0; var ids = Set<UUID>()
        for action in actions {
            let effort = max(0, action.remaining)
            guard used + effort <= budget else { break }
            used += effort; ids.insert(action.id)
        }
        return ids
    }
    public mutating func retainHistory(days: Int, now: Date = Date()) {
        guard days > 0 else { return }; history.removeAll { now.timeIntervalSince($0.date) > Double(days) * 86400 }
    }
    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decoded(_ data: Data) throws -> Queue {
        let state = try JSONDecoder().decode(Queue.self, from: data)
        guard state.budget.isFinite, state.budget > 0, Set(state.actions.map(\.id)).count == state.actions.count,
              state.actions.allSatisfy({ !$0.title.isEmpty && $0.estimate.isFinite && $0.estimate > 0 && $0.active.isFinite && $0.active >= 0 && $0.target.isFinite && $0.target > 0 }),
              state.selectedID == nil || state.actions.contains(where: { $0.id == state.selectedID }),
              state.actions.filter({ $0.phase != .queued }).allSatisfy({ $0.id == state.selectedID }) else { throw QueueError.invalidDuration }
        return state
    }
    public static func sample() -> Queue {
        var q = Queue()
        try! q.add(title: "Draft summary", minutes: 8)
        try! q.add(title: "Check links", minutes: 6)
        try! q.add(title: "Send handoff", minutes: 12)
        q.actions[0].active = 540
        q.actions[1].active = 120; q.actions[1].phase = .paused
        q.actions[1].notes = [Interruption("Continue at the support link")]
        q.selectedID = q.actions[1].id; q.budget = 10 * 60
        return q
    }
}
public enum TimeText {
    public static func clock(_ seconds: Double) -> String {
        let value = Int(abs(seconds).rounded(.up))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
