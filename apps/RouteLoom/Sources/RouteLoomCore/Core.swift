import Foundation

public enum URLRuleError: String, Error, LocalizedError {
    case https = "Use a complete HTTPS URL"
    case credentials = "Remove embedded credentials from the URL"
    case host = "Enter a valid endpoint hostname"
    public var errorDescription: String? { rawValue }
}
public enum Endpoint {
    public static func validate(_ text: String) throws -> URL {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: clean), c.scheme?.lowercased() == "https", let url = c.url else { throw URLRuleError.https }
        guard c.user == nil, c.password == nil else { throw URLRuleError.credentials }
        guard let host = c.host, !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
              !clean.contains(where: { $0.isWhitespace }), c.fragment == nil,
              c.port == nil || (1...65535).contains(c.port!) else { throw URLRuleError.host }
        return url
    }
    public static func host(_ url: URL) -> String { url.host ?? "unknown" }
}
public enum Transport: String, Codable, CaseIterable, Sendable {
    case offline, denied, tls, timeout, dns, connection, cancelled, unknown
    public static func classify(_ error: Error) -> Self {
        let e = error as NSError
        guard e.domain == NSURLErrorDomain else { return .unknown }
        switch e.code {
        case NSURLErrorNotConnectedToInternet: return .offline
        case NSURLErrorDataNotAllowed: return .denied
        case NSURLErrorTimedOut: return .timeout
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected, NSURLErrorClientCertificateRequired: return .tls
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .dns
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost: return .connection
        case NSURLErrorCancelled: return .cancelled
        default: return .unknown
        }
    }
}
public struct Observation: Codable, Equatable, Sendable {
    public var at: Date
    public var elapsed: Double
    public var status: Int?
    public var error: Transport?
    public init(at: Date, elapsed: Double, status: Int? = nil, error: Transport? = nil) { self.at = at; self.elapsed = elapsed; self.status = status; self.error = error }
    public var healthy: Bool { status.map { (200..<300).contains($0) } == true && error == nil }
    public var known: Bool { status != nil || (error != nil && error != .cancelled && error != .unknown) }
    public var summary: String { status.map { "HTTP \($0) · response received" } ?? error?.rawValue ?? "unknown" }
}
public enum PairState: String, Codable, CaseIterable, Sendable {
    case healthy, targetOnly, referenceOnly, shared, insufficient
    public var label: String {
        switch self { case .healthy: return "Healthy pair"; case .targetOnly: return "Work only failure"; case .referenceOnly: return "Reference only failure"; case .shared: return "Shared failure"; case .insufficient: return "Insufficient evidence" }
    }
    public var failing: Bool { self != .healthy && self != .insufficient }
    public static func classify(_ reference: Observation?, _ work: Observation?) -> Self {
        guard let r = reference, let w = work, r.known, w.known else { return .insufficient }
        if r.healthy && w.healthy { return .healthy }
        if r.healthy { return .targetOnly }
        if w.healthy { return .referenceOnly }
        return .shared
    }
}
public struct PairCheck: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var at: Date
    public var reference: Observation?
    public var work: Observation?
    public init(at: Date, reference: Observation?, work: Observation?) { self.at = at; self.reference = reference; self.work = work }
    public var state: PairState { .classify(reference, work) }
}
public struct Gap: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var start: Date
    public var end: Date
    public var reason: String
    public init(start: Date, end: Date, reason: String) { self.start = start; self.end = max(start, end); self.reason = reason }
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}
public struct Incident: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var start: Date
    public var end: Date?
    public var checks: [PairCheck]
    public var gaps: [Gap]
    public var observedDuration: TimeInterval {
        // Only adjacent failing observations provide an observed failure span.
        zip(checks, checks.dropFirst()).reduce(0) { sum, pair in
            let (a,b) = pair
            guard a.state.failing, b.state != .insufficient else { return sum }
            let gap = gaps.contains { $0.start < b.at && $0.end > a.at }
            return sum + (gap ? 0 : max(0, b.at.timeIntervalSince(a.at)))
        }
    }
}
public struct Session: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var referenceHost: String
    public var workHost: String
    public var started: Date
    public var ended: Date?
    public var sample: Bool
    public var checks: [PairCheck] = []
    public var gaps: [Gap] = []
    public var incidents: [Incident] = []
    public init(name: String, referenceHost: String, workHost: String, started: Date, sample: Bool) {
        self.name = name; self.referenceHost = referenceHost; self.workHost = workHost; self.started = started; self.sample = sample
    }
    public mutating func append(_ check: PairCheck) {
        guard ended == nil, checks.last.map({ check.at >= $0.at }) ?? true else { return }
        let previous = checks.last?.state
        checks.append(check)
        if let index = incidents.indices.last, incidents[index].end == nil {
            incidents[index].checks.append(check)
            if check.state == .healthy { incidents[index].end = check.at }
        } else if previous == .healthy && check.state.failing {
            incidents.append(Incident(start: check.at, end: nil, checks: [check], gaps: []))
        }
    }
    public mutating func gap(_ gap: Gap) {
        gaps.append(gap)
        if let i = incidents.indices.last, incidents[i].end == nil { incidents[i].gaps.append(gap) }
    }
    public var counts: [PairState: Int] { Dictionary(grouping: checks, by: \.state).mapValues(\.count) }
    public var current: PairState { checks.last?.state ?? .insufficient }
    public var latestIncident: Incident? { incidents.last }
}
public enum Report {
    public static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    public static func text(_ session: Session, translate: (String) -> String = { $0 }) -> String {
        let tr = translate
        var lines = [tr("RouteLoom support report") + (session.sample ? " · Sample" : ""),
            tr("Reference host") + " " + session.referenceHost, tr("Work host") + " " + session.workHost,
            tr("Started") + " " + timestamp(session.started), session.ended.map { tr("Stopped") + " " + timestamp($0) } ?? tr("Session active"),
            tr("HEAD requests with standard TLS validation. Redirects are not followed."),
            tr("Paths and query strings omitted. Observations do not establish an ISP, DNS or VPN cause."),
            tr("Observed intervals exclude unknown sleep and shutdown gaps."), ""]
        for check in session.checks {
            lines.append(timestamp(check.at) + " · " + tr(check.state.label))
            for (label, o) in [("Reference", check.reference), ("Work", check.work)] {
                let observation = o.map { value in
                    let summary = value.status.map { "HTTP \($0) · " + tr("response received") }
                        ?? tr(value.error?.rawValue ?? "unknown")
                    return timestamp(value.at) + " · " + summary + " · " + String(format: "%.0f ms", value.elapsed * 1000)
                } ?? tr("unknown")
                lines.append("  " + tr(label) + " " + observation)
            }
        }
        for gap in session.gaps { lines.append(tr("Unknown gap") + " " + timestamp(gap.start) + " " + tr("to") + " " + timestamp(gap.end) + " · " + tr(gap.reason)) }
        for incident in session.incidents { lines.append(tr("Incident") + " " + timestamp(incident.start) + " · " + tr("Observed span") + " " + String(format: "%.0f", incident.observedDuration) + " " + tr("seconds") + " · " + (incident.end.map { tr("Recovered") + " " + timestamp($0) } ?? tr("Recovery not observed"))) }
        return lines.joined(separator: "\n")
    }
    public static func comparison(_ current: Session, _ earlier: Session) -> String {
        let same = current.referenceHost == earlier.referenceHost && current.workHost == earlier.workHost
        var lines = [same ? "Same endpoint hostnames" : "Different endpoint hostnames · compare with care"]
        for state in PairState.allCases { lines.append(state.label + " · recent \(current.counts[state, default: 0]) · earlier \(earlier.counts[state, default: 0])") }
        lines.append("Checks are counts, not continuous uptime measurements")
        return lines.joined(separator: "\n")
    }
}
public enum Fixtures {
    public static let base = Date(timeIntervalSince1970: 1791968400)
    public static func observation(_ t: Date, _ error: Transport? = nil, status: Int? = nil) -> Observation {
        Observation(at: t, elapsed: error == .timeout ? 8 : 0.12, status: error == nil ? (status ?? 200) : nil, error: error)
    }
    public static func session(_ scenario: Transport = .timeout) -> Session {
        var s = Session(name: "Work connection", referenceHost: "reference.example", workHost: "work.example", started: base, sample: true)
        for (seconds, r, w) in [(0.0, nil, nil), (30.0, nil, scenario), (60.0, nil, scenario), (90.0, nil, nil), (120.0, Transport.offline, Transport.offline)] {
            let t = base.addingTimeInterval(seconds)
            if (seconds == 30 || seconds == 60) && scenario == .dns {
                s.append(PairCheck(at:t,reference:observation(t,.dns),work:observation(t)))
            } else if (seconds == 30 || seconds == 60) && scenario == .unknown {
                s.append(PairCheck(at:t,reference:nil,work:observation(t)))
            } else {
                s.append(PairCheck(at: t, reference: observation(t,r), work: observation(t,w)))
            }
        }
        s.gap(Gap(start: base.addingTimeInterval(120), end: base.addingTimeInterval(420), reason: "Sleep · time unknown"))
        let t = base.addingTimeInterval(420)
        s.append(PairCheck(at:t, reference:observation(t,.offline), work:observation(t,.offline)))
        let recovered = base.addingTimeInterval(450)
        s.append(PairCheck(at:recovered, reference:observation(recovered),work:observation(recovered)))
        s.ended = recovered
        return s
    }
    public static var earlier: Session {
        var s = Session(name: "Earlier connection", referenceHost: "reference.example", workHost: "work.example", started: base.addingTimeInterval(-3600), sample: true)
        for seconds in [0.0,30,60,90] { let t = s.started.addingTimeInterval(seconds); s.append(PairCheck(at:t,reference:observation(t),work:observation(t))) }
        s.ended = s.checks.last?.at
        return s
    }
}
