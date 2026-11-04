import Foundation

public struct Run: Codable, Equatable, Identifiable {
    public var id: Int
    public var workflow_id: Int
    public var name: String?
    public var head_branch: String?
    public var status: String
    public var conclusion: String?
    public var run_number: Int
    public var run_attempt: Int?
    public var html_url: String
    public var updated_at: Date
    public init(id: Int, workflow: Int = 10, branch: String = "main", status: String = "completed", conclusion: String? = "failure", number: Int? = nil, attempt: Int = 1) {
        self.id=id; workflow_id=workflow; name="Build and test"; head_branch=branch; self.status=status; self.conclusion=conclusion
        run_number=number ?? id; run_attempt=attempt; html_url="https://github.com/harbor/demo/actions/runs/\(id)"; updated_at=Date(timeIntervalSince1970: 1_792_000_000 + Double(id)*60)
    }
    public var fails: Bool { status == "completed" && ["failure", "timed_out", "action_required", "startup_failure"].contains(conclusion ?? "") }
    public var succeeds: Bool { status == "completed" && conclusion == "success" }
    public var order: Position { Position(number: run_number, attempt: run_attempt ?? 1) }
}
public struct Position: Codable, Equatable, Comparable {
    public var number: Int
    public var attempt: Int
    public static func <(a: Self,b: Self) -> Bool { a.number == b.number ? a.attempt < b.attempt : a.number < b.number }
}
public struct Episode: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var key: String
    public var repository: String
    public var first: Run
    public var latest: Run
    public var recovery: Run?
    public var failures = 1
    public var acknowledged = false
    public var snoozedUntil: Date?
    public var unresolved: Bool { recovery == nil }
    public func snoozed(at date: Date) -> Bool { (snoozedUntil ?? .distantPast) > date }
}
public struct Inbox: Codable, Equatable {
    public var episodes: [Episode] = []
    // Cursors contain successful positions only. Other conclusions cannot hide a late completion.
    public var cursors: [String:Position] = [:]
    public var processed: [String:Set<String>] = [:]
    public init() {}
    enum CodingKeys: String, CodingKey { case episodes, cursors, processed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        episodes = try c.decode([Episode].self, forKey: .episodes)
        if let saved = try c.decodeIfPresent([String:Set<String>].self, forKey: .processed) {
            processed = saved
            cursors = try c.decodeIfPresent([String:Position].self, forKey: .cursors) ?? [:]
        } else {
            // Older cursors also included cancelled runs. Rebuild only from retained successes.
            for episode in episodes {
                for run in [episode.first, episode.latest, episode.recovery].compactMap({ $0 }) {
                    processed[episode.key, default: []].insert(Self.identity(run))
                }
                if let recovery = episode.recovery {
                    cursors[episode.key] = max(cursors[episode.key] ?? recovery.order, recovery.order)
                }
            }
        }
    }
    private static func identity(_ run: Run) -> String { "\(run.id)|\(run.run_attempt ?? 1)" }
    public static func key(repository: String, run: Run) -> String? {
        guard let branch=run.head_branch, !branch.isEmpty else { return nil }
        return "\(repository.lowercased())|\(run.workflow_id)|\(branch)"
    }
    public mutating func ingest(repository: String, runs: [Run]) {
        for run in runs.sorted(by: { $0.order < $1.order }) where run.fails || run.succeeds {
            guard let key=Self.key(repository: repository, run: run),
                  processed[key]?.contains(Self.identity(run)) != true else { continue }
            processed[key, default: []].insert(Self.identity(run))
            let active=episodes.firstIndex { $0.key == key && $0.unresolved }
            if run.fails {
                guard cursors[key].map({ run.order > $0 }) ?? true else { continue }
                if let i=active {
                    if run.order > episodes[i].latest.order { episodes[i].latest=run }
                    if run.order < episodes[i].first.order { episodes[i].first=run }
                    episodes[i].failures += 1
                } else { episodes.append(Episode(key:key,repository:repository,first:run,latest:run)) }
            } else {
                cursors[key]=max(cursors[key] ?? run.order, run.order)
                if let i=active, run.order > episodes[i].latest.order {
                    episodes[i].recovery=run; episodes[i].snoozedUntil=nil
                }
            }
        }
    }
    public mutating func acknowledge(_ id: UUID) { if let i=episodes.firstIndex(where:{$0.id == id}) { episodes[i].acknowledged.toggle() } }
    public mutating func snooze(_ id: UUID, until: Date?) { if let i=episodes.firstIndex(where:{$0.id == id}) { episodes[i].snoozedUntil=until } }
    public mutating func prune(before: Date) { episodes.removeAll { ($0.recovery?.updated_at ?? .distantFuture) < before } }
    public var active: [Episode] { episodes.filter(\.unresolved) }
    public var recovered: [Episode] { episodes.filter { !$0.unresolved } }
}
public enum Validation {
    public static func repository(_ input: String) -> String? {
        let s=input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces=s.split(separator:"/",omittingEmptySubsequences:false)
        guard pieces.count == 2, pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.range(of:"^[A-Za-z0-9_.-]+$",options:.regularExpression) != nil }), pieces[0].range(of:"^[A-Za-z0-9-]+$",options:.regularExpression) != nil else { return nil }
        return s.lowercased()
    }
    public static func runURL(_ input: String, repository: String) -> URL? {
        guard let u=URL(string:input), u.scheme == "https",u.host == "github.com",u.user == nil,u.password == nil,u.port == nil,u.query == nil,u.fragment == nil else { return nil }
        let parts=u.path.split(separator:"/").map(String.init)
        guard parts.count == 5, "\(parts[0])/\(parts[1])".lowercased() == repository.lowercased(),parts[2] == "actions",parts[3] == "runs",Int(parts[4]) != nil else { return nil }
        return u
    }
    public static func backoff(status: Int, headers: [String:String], now: Date) -> Date? {
        let h=Dictionary(headers.map { ($0.key.lowercased(),$0.value) },uniquingKeysWith: { a,_ in a })
        if let seconds=Double(h["retry-after"] ?? "") { return now.addingTimeInterval(max(60,seconds)) }
        if h["x-ratelimit-remaining"] == "0", let reset=Double(h["x-ratelimit-reset"] ?? "") { return max(now.addingTimeInterval(60),Date(timeIntervalSince1970:reset)) }
        return [403,429].contains(status) ? now.addingTimeInterval(900) : nil
    }
    public static func mayFetch(sample: Bool, until: Date?, now: Date) -> Bool { !sample && (until ?? .distantPast) <= now }
}
public enum Fixtures {
    public static var initial: [Run] { [Run(id:1),Run(id:2),Run(id:3,branch:"docs",conclusion:"success"),Run(id:4,workflow:20,branch:"release")] }
    public static var recovery: [Run] { initial + [Run(id:5,conclusion:"success")] }
}
