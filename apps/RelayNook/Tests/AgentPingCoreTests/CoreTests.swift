import Foundation
import Testing
@testable import AgentPingCore

// Use fixture data for URL inputs, event sequences, and JSON payloads.
struct CoreTests {
    let token = "0123456789abcdef0123456789abcdef" // Fixture credential, never a real installation token.
    func parse(_ raw: String) -> AgentEvent? { EventParser.parse(raw, token: token) }
    let base = "agentping://event?agent=test&kind=waiting&title=probe&project=mas5&session=s1&token=0123456789abcdef0123456789abcdef"
    func event(_ kind: EventKind = .waiting, session: String = "s1") -> AgentEvent {
        AgentEvent(agent: "fixture", kind: kind, title: "Fixture event", project: "fixture", session: session)
    }
    @Test func acceptsKinds() {
        for kind in EventKind.allCases { #expect(parse(base.replacingOccurrences(of: "waiting", with: kind.rawValue))?.kind == kind) }
    }
    @Test func decodesUnicodeAndReservedCharacters() {
        let parsed = parse(base.replacingOccurrences(of: "probe", with: "%E2%9C%93%20a%26b%3F%23%27%22%2B"))
        #expect(parsed?.title == "✓ a&b?#'\"+")
    }
    @Test func rejectsMalformedURLs() {
        for raw in ["", "https://event", base + "&agent=again", base + "#fragment", base.replacingOccurrences(of: "event?", with: "event/path?"), base.replacingOccurrences(of: "probe", with: "%ZZ"), base.replacingOccurrences(of: "probe", with: "%FF"), base.replacingOccurrences(of: "waiting", with: "WAITING"), base.replacingOccurrences(of: "session=s1", with: "session="), base.replacingOccurrences(of: "event?", with: "user@event?"), base.replacingOccurrences(of: "project=mas5&", with: ""), base.replacingOccurrences(of: "event?", with: "event:99?")] {
            #expect(parse(raw) == nil, "\(raw)")
        }
    }
    @Test func clampsAllTextFields() {
        let raw = "agentping://event?agent=\(String(repeating: "a", count: 100))&kind=info&title=\(String(repeating: "x", count: 400))&project=\(String(repeating: "y", count: 400))&session=\(String(repeating: "s", count: 200))&token=\(token)"
        let parsed = parse(raw)
        #expect(parsed?.agent.count == 64); #expect(parsed?.title.count == 240)
        #expect(parsed?.project.count == 240); #expect(parsed?.session.count == 128)
        #expect(EventParser.clamp(" \nhello\u{0} ", maximum: 9) == "hello")
        #expect(parse(base.replacingOccurrences(of: "test", with: "%00%20")) == nil)
        #expect(parse(base + String(repeating: "x", count: 32768)) == nil)
    }
    @Test func emptyProjectIsValid() { #expect(parse(base.replacingOccurrences(of: "project=mas5", with: "project="))?.project == "") }
    @Test func badgeStateMachine() {
        var state = History()
        state.receive(event()); state.receive(event()); #expect(state.waitingCount == 1)
        state.receive(event(session: "s2")); #expect(state.waitingCount == 2)
        state.receive(event(.done)); #expect(state.waitingCount == 1)
        state.receive(event(.info, session: "s2")); #expect(state.waitingCount == 0)
        state.receive(event()); state.receive(event(.error)); #expect(state.waitingCount == 0)
    }
    @Test func ringBufferKeepsNewestAndPreservesWaitingSession() {
        var state = History(); state.receive(event(session: "old"))
        for i in 0..<250 { state.receive(event(.info, session: "\(i)")) }
        #expect(state.events.count == 200); #expect(state.events.first?.session == "50")
        #expect(state.events.last?.session == "249"); #expect(state.waitingCount == 1)
    }
    @Test func rejectedCounterAndClear() {
        var state = History(); state.reject()
        #expect(state.rejectedCount == 1); state.receive(event()); state.clear()
        #expect(state.events.isEmpty); #expect(state.waitingCount == 0); #expect(state.rejectedCount == 1)
    }
    @Test func historyRoundtrip() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".test-data/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        var state = History(); state.receive(event()); state.reject()
        try state.save(to: url); #expect(try History.load(from: url) == state)
    }
    @Test func notificationPreferencesRoundtrip() throws {
        var preferences = Preferences(); #expect(preferences.permits(.waiting)); #expect(!preferences.sound)
        preferences.enabledKinds.remove(.info); preferences.sound = true
        #expect(!preferences.permits(.info))
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }
    @Test func quotesShellMetacharacters() {
        #expect(Snippets.shellQuote("a'b $HOME $(id) `id` \n") == "'a'\"'\"'b $HOME $(id) `id` \n'")
        #expect(Snippets.shellQuote("") == "''")
        #expect(Snippets.urlCommand(payload: "'$(id)", mode: "done", token: token).contains("'\"'\"'$(id)' 'done'"))
    }
    @Test func claudeSchemaAndCodexArgumentForwarding() throws {
        let config = try #require(JSONSerialization.jsonObject(with: Data(Snippets.claudeJSON.utf8)) as? [String: Any])
        let hooks = try #require(config["hooks"] as? [String: [[String: Any]]])
        #expect(Set(hooks.keys) == Set(["Notification", "Stop"]))
        #expect(hooks["Notification"]?.first?["matcher"] as? String == "permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input")
        let stop = try #require(hooks["Stop"]?.first?["hooks"] as? [[String: String]])
        #expect(stop.first?["type"] == "command"); #expect(stop.first?["command"]?.hasSuffix(" done") == true)
        #expect(Snippets.codexTOML.contains("$1")); #expect(Snippets.hookScript.contains("payload=${2:?Missing JSON argument}"))
        #expect(Snippets.genericFunction().contains("\"$@\""))
    }
    @Test func authenticationRejectsMissingWrongAndDuplicateTokens() {
        #expect(parse(base) != nil)
        #expect(parse(base.replacingOccurrences(of: "&token=" + token, with: "")) == nil)
        #expect(parse(base.replacingOccurrences(of: token, with: String(repeating: "f", count: 32))) == nil)
        #expect(parse(base + "&token=" + token) == nil)
        #expect(parse(base + "&%74oken=" + token) == nil)
        #expect(parse(base.replacingOccurrences(of: "token=", with: "token=%25")) == nil)
        #expect(EventParser.parse(base, token: "") == nil)
    }
    @Test func burstIsLimitedAndWindowExpiresAtSixtySeconds() {
        var ingress = EventIngress(token: token)
        var history = History()
        let start = Date(timeIntervalSince1970: 1000)
        for _ in 0..<500 {
            if let accepted = ingress.receive(base, now: start) { history.receive(accepted.event) }
            else { history.reject() }
        }
        #expect(history.events.count == 30)
        #expect(history.rejectedCount == 470)
        #expect(ingress.receive(base, now: start.addingTimeInterval(59.999)) == nil)
        #expect(ingress.receive(base, now: start.addingTimeInterval(60)) != nil)
    }
    @Test func failedAuthenticationDoesNotConsumeRateAllowance() {
        var ingress = EventIngress(token: token)
        for _ in 0..<500 { #expect(ingress.receive("bad") == nil) }
        #expect(ingress.receive(base) != nil)
    }
    @Test func duplicateNotificationsCoalescePerSessionForTenSeconds() {
        var ingress = EventIngress(token: token)
        let start = Date(timeIntervalSince1970: 1000)
        #expect(ingress.receive(base, now: start)?.shouldNotify == true)
        #expect(ingress.receive(base, now: start.addingTimeInterval(9.999))?.shouldNotify == false)
        #expect(ingress.receive(base, now: start.addingTimeInterval(10))?.shouldNotify == true)
        #expect(ingress.receive(base.replacingOccurrences(of: "session=s1", with: "session=s2"), now: start.addingTimeInterval(10))?.shouldNotify == true)
        #expect(ingress.receive(base.replacingOccurrences(of: "waiting", with: "done"), now: start.addingTimeInterval(10))?.shouldNotify == true)
    }
    @Test func stripsControlAndDirectionalOverridesWithoutDoubleDecoding() {
        #expect(EventParser.clamp("a\u{202E}b\u{2066}c\u{2069}d\u{0}e", maximum: 64) == "abcde")
        #expect(parse(base.replacingOccurrences(of: "probe", with: "%E2%80%AEhello%00"))?.title == "hello")
        #expect(parse(base.replacingOccurrences(of: "probe", with: "%2526token%253Devil"))?.title == "%26token%3Devil")
        #expect(parse(base.replacingOccurrences(of: "probe", with: "%26token%3Devil"))?.title == "&token=evil")
    }
    @Test func atomicHistoryReplacesExistingFile() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".test-data/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        var history = History()
        for i in 0..<220 {
            history.receive(event(.info, session: String(i)))
            try history.save(to: url)
            #expect(try History.load(from: url) == history)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["history.json"])
    }

}
