import Foundation
import Testing
@testable import AgentPingCore
@testable import AgentPing

// Fixture history and tokens reproduce migration and concurrent persistence.
private final class BlockedWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var snapshots: [History] = []
    private var blocked = false
    func write(_ history: History, _ url: URL) {
        lock.lock()
        let first = snapshots.isEmpty
        snapshots.append(history)
        blocked = first
        lock.unlock()
        if first { _ = release.wait(timeout: .now() + 5) }
    }
    var isBlocked: Bool { lock.lock(); defer { lock.unlock() }; return blocked }
    var values: [History] { lock.lock(); defer { lock.unlock() }; return snapshots }
    func unblock() { release.signal() }
}

struct Round4Tests {
    let token = "0123456789abcdef0123456789abcdef"
    func event(_ kind: EventKind) -> AgentEvent {
        AgentEvent(agent: "A", kind: kind, title: "Fixture", project: "", session: "lost")
    }
    @Test func unresolvedLegacyDoesNotDoubleCountOrStrandCompletedSession() throws {
        let legacy = Data(#"{"events":[],"waitingSessions":["lost"],"rejectedCount":0}"#.utf8)
        var history = try JSONDecoder().decode(History.self, from: legacy)
        #expect(history.waitingCount == 0)
        history.receive(event(.waiting))
        #expect(history.waitingCount == 1)
        history.receive(event(.done))
        #expect(history.waitingCount == 0)
        let reloaded = try JSONDecoder().decode(History.self, from: JSONEncoder().encode(history))
        #expect(reloaded.waitingCount == 0)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reloaded)) as? [String: Any])
        #expect(json["unresolvedLegacySessions"] as? [String] == ["lost"])
    }
    @Test func priorNilAgentMigrationLeavesOnlyExactIdentitiesInBadge() throws {
        let legacy = Data(#"{"events":[],"waitingSessions":[{"session":"lost"},{"agent":"B","session":"lost"}],"rejectedCount":0}"#.utf8)
        var history = try JSONDecoder().decode(History.self, from: legacy)
        #expect(history.waitingCount == 1)
        history.receive(AgentEvent(agent: "B", kind: .done, title: "Fixture", project: "", session: "lost"))
        #expect(history.waitingCount == 0)
        let reloaded = try JSONDecoder().decode(History.self, from: JSONEncoder().encode(history))
        #expect(reloaded.waitingCount == 0)
    }
    @Test @MainActor func flushIncludesAcceptedArrivalDuringBlockedWrite() async throws {
        let probe = BlockedWriter()
        defer { probe.unblock() }
        let model = AppModel(token: token, historyURL: URL(fileURLWithPath: "/unused-fixture"),
                             historyWriter: probe.write, notificationAuthorization: { .denied })
        let first = URL(string: "agentping://event?agent=A&kind=waiting&title=Fixture&project=&session=lost&token=\(token)")!
        model.receive(first)
        let flushing = Task { await model.flushHistory() }
        for _ in 0..<200 {
            if probe.isBlocked { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(probe.isBlocked)
        model.receive(URL(string: first.absoluteString.replacingOccurrences(of: "kind=waiting", with: "kind=done"))!)
        #expect(model.history.events.count == 2)
        probe.unblock()
        await flushing.value
        #expect(probe.values.last?.events.count == 2)
        #expect(probe.values.last?.waitingCount == 0)
    }
    @Test func unresolvedLegacyDismissalPersistsWithoutRemovingExactSessions() throws {
        let legacy = Data(#"{"events":[],"waitingSessions":["lost"],"rejectedCount":7}"#.utf8)
        var history = try JSONDecoder().decode(History.self, from: legacy)
        history.receive(event(.waiting))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".test-data/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        try history.save(to: url)
        history = try History.load(from: url)
        #expect(history.unresolvedLegacySessions == ["lost"])
        #expect(history.waitingCount == 1)
        history.dismissUnresolvedLegacySessions()
        try history.save(to: url)
        let reloaded = try History.load(from: url)
        #expect(reloaded.unresolvedLegacyCount == 0)
        #expect(reloaded.waitingCount == 1)
        #expect(reloaded.events.count == 1)
        #expect(reloaded.rejectedCount == 7)
        history.clear()
        #expect(history.waitingCount == 0)
        #expect(history.unresolvedLegacyCount == 0)
    }
    @Test @MainActor func shutdownClosesIngressBeforeBlockedFinalWrite() async throws {
        let probe = BlockedWriter()
        defer { probe.unblock() }
        let model = AppModel(token: token, historyURL: URL(fileURLWithPath: "/unused-fixture"),
                             historyWriter: probe.write, notificationAuthorization: { .denied })
        let url = URL(string: "agentping://event?agent=A&kind=waiting&title=Fixture&project=&session=lost&token=\(token)")!
        model.receive(url)
        model.beginShutdown()
        #expect(model.isShuttingDown)
        let flushing = Task { await model.flushHistory() }
        for _ in 0..<200 {
            if probe.isBlocked { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(probe.isBlocked)
        model.receive(URL(string: url.absoluteString.replacingOccurrences(of: "kind=waiting", with: "kind=done"))!)
        model.receive(URL(string: "agentping://event?token=invalid")!)
        model.sendTest()
        model.clear()
        #expect(model.history.events.count == 1)
        #expect(model.history.waitingCount == 1)
        #expect(model.history.rejectedCount == 0)
        probe.unblock()
        await flushing.value
        #expect(probe.values.last == model.history)
        model.receive(url)
        #expect(probe.values.last == model.history)
    }
}
