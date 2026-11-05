import Foundation

public struct PlanError: LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
public struct Cron: Sendable {
    public let fields: [Set<Int>]
    public let dayWildcard: Bool
    public let weekdayWildcard: Bool
    public init(_ expression: String) throws {
        let parts = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else { throw PlanError("Expression needs five fields in minute hour day month weekday order") }
        let bounds = [0...59, 0...23, 1...31, 1...12, 0...7]
        let names = ["Minute", "Hour", "Day", "Month", "Weekday"]
        var parsed: [Set<Int>] = []
        for (index, part) in parts.enumerated() {
            var values = Set<Int>()
            for item in part.split(separator: ",", omittingEmptySubsequences: false) {
                let sections = item.split(separator: "/", omittingEmptySubsequences: false)
                guard sections.count <= 2, !sections[0].isEmpty else { throw PlanError("\(names[index]) has invalid list or step syntax") }
                let step = sections.count == 2 ? Int(sections[1]) : 1
                guard let step, step > 0, step <= bounds[index].upperBound + 1 else { throw PlanError("\(names[index]) step must be positive and within the field range") }
                let base = String(sections[0]); let lower: Int; let upper: Int
                if base == "*" { lower = bounds[index].lowerBound; upper = bounds[index].upperBound }
                else {
                    let range = base.split(separator: "-", omittingEmptySubsequences: false)
                    guard range.count <= 2, let start = Int(range[0]), range.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { throw PlanError("\(names[index]) accepts only numbers stars lists ranges and steps") }
                    lower = start
                    if range.count == 2 { guard let end = Int(range[1]) else { throw PlanError("\(names[index]) range is invalid") }; upper = end }
                    else { upper = sections.count == 2 ? bounds[index].upperBound : start }
                }
                guard bounds[index].contains(lower), bounds[index].contains(upper), lower <= upper else { throw PlanError("\(names[index]) must be within \(bounds[index].lowerBound) through \(bounds[index].upperBound)") }
                for value in stride(from: lower, through: upper, by: step) { values.insert(index == 4 && value == 7 ? 0 : value) }
            }
            parsed.append(values)
        }
        fields = parsed; dayWildcard = parts[2] == "*"; weekdayWildcard = parts[4] == "*"
    }
    public func matches(_ c: DateComponents) -> Bool {
        guard let m=c.minute, let h=c.hour, let d=c.day, let mo=c.month, let w=c.weekday else { return false }
        let day = fields[2].contains(d), weekday = fields[4].contains(w-1)
        let dateMatch = !dayWildcard && !weekdayWildcard ? day || weekday : day && weekday
        return fields[0].contains(m) && fields[1].contains(h) && fields[3].contains(mo) && dateMatch
    }
}
public struct Job: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var expression: String
    public var zone: String
    public var minutes: Double
    public var resource: String
    public init(id: UUID = UUID(), name: String, expression: String, zone: String, minutes: Double, resource: String) {
        self.id=id; self.name=name; self.expression=expression; self.zone=zone; self.minutes=minutes; self.resource=resource
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlanError("Enter a job name") }
        _ = try Cron(expression)
        guard TimeZone(identifier: zone) != nil else { throw PlanError("Choose a valid IANA time zone") }
        guard minutes.isFinite && minutes > 0 && minutes <= 44640 else { throw PlanError("Duration must be positive and at most 44640 minutes") }
    }
    public var resourceKey: String { resource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
public struct Occurrence: Identifiable, Sendable {
    public var id: String { "\(job.id) \(start.timeIntervalSince1970)" }
    public let job: Job
    public let start: Date
    public var end: Date { start.addingTimeInterval(job.minutes*60) }
    public var wallLabel: String { Planner.label(start, zone: job.zone) }
}
public struct Collision: Identifiable, Equatable, Sendable {
    public let pair: String
    public let names: String
    public let resource: String
    public let start: Date
    public let end: Date
    public var id: String { "\(pair) \(start.timeIntervalSince1970) \(end.timeIntervalSince1970)" }
    public init(pair: String, names: String, resource: String, start: Date, end: Date) { self.pair=pair; self.names=names; self.resource=resource; self.start=start; self.end=end }
}
public struct Analysis: Sendable {
    public var occurrences: [Occurrence] = []
    public var collisions: [Collision] = []
    public var incomplete = false
    public var cancelled = false
    public let start: Date
    public let end: Date
    public var state: String { cancelled ? "Cancelled" : incomplete ? "Incomplete" : collisions.isEmpty ? "Clear" : "Conflict" }
}
public enum Planner {
    public static func label(_ date: Date, zone: String = "UTC") -> String {
        let f=DateFormatter(); f.locale=Locale(identifier:"en_US_POSIX"); f.timeZone=TimeZone(identifier:zone) ?? TimeZone(secondsFromGMT:0); f.dateFormat="yyyy MMM dd HH:mm " + String(repeating:"X",count:3); return f.string(from:date)
    }
    public static func analyze(_ jobs: [Job], start: Date, days: Int, limit: Int = 5000) throws -> Analysis {
        guard (1...31).contains(days), limit > 0, jobs.count <= 50 else { throw PlanError("Use 1 through 31 days and at most 50 jobs") }
        for job in jobs { try job.validate() }
        let end=start.addingTimeInterval(Double(days)*86400)
        var result=Analysis(start:start,end:end)
        let compiled=try jobs.map { job -> (Job,Cron,Calendar) in
            var cal=Calendar(identifier:.gregorian); cal.timeZone=TimeZone(identifier:job.zone)!
            return (job,try Cron(job.expression),cal)
        }
        let lookback=(jobs.map(\.minutes).max() ?? 0)*60
        var cursor=Date(timeIntervalSince1970:floor(start.addingTimeInterval(-lookback).timeIntervalSince1970/60)*60)
        expansion: while cursor < end {
            if Task.isCancelled { result.incomplete=true; result.cancelled=true; break }
            var cache: [String:DateComponents]=[:]
            for (job,cron,cal) in compiled {
                let components=cache[job.zone] ?? cal.dateComponents([.minute,.hour,.day,.month,.weekday],from:cursor)
                cache[job.zone]=components
                if cron.matches(components) && cursor.addingTimeInterval(job.minutes*60)>start {
                    if result.occurrences.count >= limit { result.incomplete=true; break expansion }
                    result.occurrences.append(Occurrence(job:job,start:cursor))
                }
            }
            cursor=cursor.addingTimeInterval(60)
        }
        var active: [Occurrence]=[]
        for occurrence in result.occurrences {
            active.removeAll { $0.end <= occurrence.start }
            for other in active where !occurrence.job.resourceKey.isEmpty && other.job.resourceKey == occurrence.job.resourceKey {
                if result.collisions.count >= limit { result.incomplete=true; return result }
                let lower=max(start,other.start,occurrence.start), upper=min(end,other.end,occurrence.end)
                if lower < upper {
                    let pair=[other.job.id.uuidString,occurrence.job.id.uuidString].sorted().joined(separator:"|")
                    result.collisions.append(Collision(pair:pair,names:"\(other.job.name) + \(occurrence.job.name)",resource:occurrence.job.resource,start:lower,end:upper))
                }
            }
            active.append(occurrence)
        }
        return result
    }
    public static func difference(_ source: [Collision], minus other: [Collision]) -> [Collision] {
        source.flatMap { item -> [Collision] in
            var fragments=[(item.start,item.end)]
            for cut in other where cut.pair == item.pair {
                fragments=fragments.flatMap { lo,hi -> [(Date,Date)] in
                    if cut.end<=lo || cut.start>=hi { return [(lo,hi)] }
                    var parts: [(Date,Date)]=[]
                    if lo<cut.start { parts.append((lo,min(hi,cut.start))) }
                    if hi>cut.end { parts.append((max(lo,cut.end),hi)) }
                    return parts
                }
            }
            return fragments.map { Collision(pair:item.pair,names:item.names,resource:item.resource,start:$0.0,end:$0.1) }
        }
    }
    public static func report(_ result: Analysis, jobs: [Job], sample: Bool) -> String {
        (["CronSpindle \(sample ? "Sample" : "Live") \(result.state)", "Coverage \(label(result.start)) to \(label(result.end))", "UTC minute expansion. Actual schedulers may use different DST rules. Blank resources are not compared."] + jobs.map { "\($0.name) | \($0.expression) | \($0.zone) | \($0.minutes) minutes | \($0.resource)" } + result.collisions.map { "\($0.names) on \($0.resource) | \(label($0.start)) to \(label($0.end))" } + (result.incomplete ? ["Incomplete coverage. Do not infer absence of collisions."] : [])).joined(separator:"\n")
    }
}
public struct Plan: Codable, Equatable, Sendable {
    public var jobs: [Job]
    public init(jobs:[Job] = []) { self.jobs=jobs }
    public static func load(_ url: URL) throws -> Plan {
        guard FileManager.default.fileExists(atPath:url.path) else { return Plan() }
        let plan=try JSONDecoder().decode(Plan.self,from:Data(contentsOf:url))
        guard plan.jobs.count<=50, Set(plan.jobs.map(\.id)).count==plan.jobs.count else { throw PlanError("Saved plan has invalid jobs") }
        for job in plan.jobs { try job.validate() }; return plan
    }
    public func save(_ url: URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(self).write(to:url,options:.atomic)
    }
}
public enum Fixtures {
    public static let start=ISO8601DateFormatter().date(from:"2026-10-14T00:00:00Z")!
    public static let autumn=ISO8601DateFormatter().date(from:"2026-11-01T04:00:00Z")!
    public static let jobs=[Job(id:UUID(uuidString:"00000000-0000-0000-0000-000000000001")!,name:"Backup",expression:"0 2 * * *",zone:"UTC",minutes:60,resource:"Disk"),Job(id:UUID(uuidString:"00000000-0000-0000-0000-000000000002")!,name:"Report",expression:"30 2 * * *",zone:"UTC",minutes:30,resource:"Disk")]
    public static let dst=[Job(name:"Autumn archive",expression:"30 1 * * *",zone:"America/New_York",minutes:20,resource:"Disk")]
}
