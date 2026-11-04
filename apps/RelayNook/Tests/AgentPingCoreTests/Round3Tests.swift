import Foundation
import Testing
import UserNotifications
@testable import AgentPingCore
@testable import AgentPing

// Fixture tokens, events, notification services and write counters isolate model logic.
private final class WriteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [History] = []
    private var mainThreadWrite = false
    func write(_ history: History, _ url: URL) {
        lock.lock(); defer { lock.unlock() }
        snapshots.append(history)
        mainThreadWrite = mainThreadWrite || Thread.isMainThread
    }
    var values: [History] { lock.lock(); defer { lock.unlock() }; return snapshots }
    var wroteOnMain: Bool { lock.lock(); defer { lock.unlock() }; return mainThreadWrite }
}
struct Round3Tests {
    let token = "0123456789abcdef0123456789abcdef"
    func event(_ agent: String, _ kind: EventKind) -> AgentEvent {
        AgentEvent(agent: agent, kind: kind, title: "Fixture", project: "", session: "shared")
    }
    @Test @MainActor func rejectedBurstUsesOneBackgroundSnapshotThroughModel() async {
        let probe = WriteProbe()
        let model = AppModel(token: token, historyURL: URL(fileURLWithPath: "/unused-fixture"), historyWriter: probe.write)
        for _ in 0..<500 { model.receive(URL(string: "agentping://event?token=invalid")!) }
        #expect(model.history.rejectedCount == 500)
        #expect(model.history.events.isEmpty)
        #expect(probe.values.isEmpty)
        await model.flushHistory()
        #expect(probe.values.count == 1)
        #expect(probe.values.last?.rejectedCount == 500)
        #expect(!probe.wroteOnMain)
    }
    @Test @MainActor func batchedPersistenceAutomaticallyWritesLatestRealFile() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".test-data/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let model = AppModel(token: token, historyURL: url)
        for _ in 0..<500 { model.receive(URL(string: "agentping://event?token=invalid")!) }
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(try History.load(from: url).rejectedCount == 500)
        model.clear()
        await model.flushHistory()
        #expect(try History.load(from: url).events.isEmpty)
    }
    @Test func interleavedAgentsKeepIndependentWaitingSessions() throws {
        var history = History()
        history.receive(event("A", .waiting)); history.receive(event("B", .waiting))
        #expect(history.waitingCount == 2)
        history.receive(event("B", .done))
        #expect(history.waitingCount == 1)
        let data = try JSONEncoder().encode(history)
        var reloaded = try JSONDecoder().decode(History.self, from: data)
        reloaded.receive(event("A", .done))
        #expect(reloaded.waitingCount == 0)
    }
    @Test func legacyWaitingHistoryMigratesAgentIdentity() throws {
        // Fixture uses the previous waitingSessions string array schema.
        let data = try JSONEncoder().encode([event("A", .waiting), event("B", .waiting), event("B", .done)])
        let json = "{\"events\":\(String(decoding: data, as: UTF8.self)),\"waitingSessions\":[\"shared\",\"older-than-ring\"],\"rejectedCount\":7}"
        var history = try JSONDecoder().decode(History.self, from: Data(json.utf8))
        history.receive(event("B", .done))
        #expect(history.waitingCount == 1) // Only A/shared has a known identity.
        #expect(history.unresolvedLegacySessions == ["older-than-ring"])
        history.receive(event("A", .done))
        #expect(history.waitingCount == 0)
        #expect(history.unresolvedLegacyCount == 1)
        #expect(history.rejectedCount == 7)
    }
    @Test @MainActor func deliveryRefreshesPermissionAndRetainsEvent() async {
        var delivered: [UNNotificationRequest] = []
        let model = AppModel(token: token, historyWriter: { _, _ in },
                             notificationAuthorization: { .authorized },
                             notificationDelivery: { delivered.append($0) })
        #expect(!model.notificationsAllowed)
        model.receive(URL(string: "agentping://event?agent=Fixture&kind=info&title=Retained&project=&session=s&token=\(token)")!)
        for _ in 0..<100 { await Task.yield() }
        #expect(delivered.count == 1)
        #expect(delivered.first?.content.body == "Retained")
        #expect(model.notificationsAllowed)
        await model.flushHistory()
    }
}
