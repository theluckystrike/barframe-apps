import Foundation

/// A calendar event as CallReady uses it. All fields are plain values so the
/// core logic is fully testable without EventKit.
public struct MeetEvent: Equatable, Codable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    /// Combined searchable text: event URL, location and notes.
    public var searchText: String
    public var isAllDay: Bool
    public var calendarID: String

    public init(id: String, title: String, start: Date, end: Date, searchText: String = "", isAllDay: Bool = false, calendarID: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.searchText = searchText
        self.isAllDay = isAllDay
        self.calendarID = calendarID
    }

    public var isAllDayOrZeroLength: Bool { isAllDay || end <= start }
}

/// Joins a meeting by opening the first Zoom / Meet / Teams / Webex link
/// found in the event URL, location or notes.
public enum JoinParser {

    public static let hosts: [String: String] = [
        "zoom.us": "Zoom",
        "meet.google.com": "Google Meet",
        "teams.microsoft.com": "Microsoft Teams",
        "webex.com": "Webex",
    ]

    /// Returns the first joinable meeting link in the text, or nil.
    /// Accepts plain URLs and common obfuscated forms ("<Meet link>", bare
    /// host without scheme, markdown links).
    public static func firstJoinLink(in text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        // markdown [label](url) and bare URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var candidates: [URL] = []
        if let detector {
            detector.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
                if let url = match?.url { candidates.append(url) }
            }
        }
        for part in text.split(separator: "\n") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("http"), let url = URL(string: trimmed), !candidates.contains(url) {
                candidates.append(url)
            }
        }
        for url in candidates {
            if isJoinLink(url) { return normalized(url) }
        }
        return nil
    }

    public static func service(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        for (suffix, name) in hosts where host == suffix || host.hasSuffix("." + suffix) {
            return name
        }
        return nil
    }

    public static func isJoinLink(_ url: URL) -> Bool {
        if service(for: url) != nil { return true }
        #if DEBUG
        // Debug builds only: the screenshot demo event uses a placeholder link.
        return url.host?.lowercased() == "example.com" && url.path.hasPrefix("/j/")
        #else
        return false
        #endif
    }

    /// Preserve invitation credentials, query parameters and fragments verbatim.
    static func normalized(_ url: URL) -> URL { url }

}

/// Countdown text for the menu bar.
public enum Countdown {

    /// "now", "in 4m", "in 1h 05m", "in 2d 3h" for the next event.
    public static func menuBarText(now: Date, next: MeetEvent?, calendar: Calendar = .current) -> String {
        guard let next else { return "" }
        if now >= next.start && now < next.end { return "now" }
        if now >= next.end { return "" }
        let seconds = Int(next.start.timeIntervalSince(now))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return String(format: "in %dh %02dm", hours, minutes) }
        return "in \(max(minutes, 1))m"
    }

    /// Menu bar headline: truncated title plus countdown.
    public static func headline(now: Date, next: MeetEvent?, titleLimit: Int = 18) -> String {
        guard let next, !next.title.isEmpty else { return "" }
        let clean = next.title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let truncated = clean.count > titleLimit ? clean.prefix(titleLimit - 1).trimmingCharacters(in: .whitespaces) + "…" : clean
        let countdown = menuBarText(now: now, next: next)
        return countdown.isEmpty ? "" : truncated + " · " + countdown
    }

    /// Whether a reminder should fire: N minutes before start, once.
    public static func shouldRemind(event: MeetEvent, now: Date, minutesBefore: Int, lastFired: Date?) -> Bool {
        guard minutesBefore > 0, lastFired == nil else { return false }
        let fireAt = event.start.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        return now >= fireAt && now < event.end
    }
}

/// Day timeline: busy/free blocks and a now marker.
public enum DayTimeline {

    public struct Block: Equatable, Sendable {
        public var start: Double // 0...1 of the day window
        public var width: Double
        public var busy: Bool
    }

    /// Busy blocks clipped to [dayStart, dayEnd]. Overlapping events merge.
    public static func blocks(events: [MeetEvent], dayStart: Date, dayEnd: Date) -> [Block] {
        let span = dayEnd.timeIntervalSince(dayStart)
        guard span > 0 else { return [] }
        let clipped = events.filter { !$0.isAllDayOrZeroLength }.compactMap { event -> (Double, Double)? in
            let s = max(0, event.start.timeIntervalSince(dayStart) / span)
            let e = min(1, event.end.timeIntervalSince(dayStart) / span)
            return e > s ? (s, e) : nil
        }.sorted { $0.0 < $1.0 }
        var merged: [(Double, Double)] = []
        for (s, e) in clipped {
            if var last = merged.last, s <= last.1 {
                last.1 = max(last.1, e)
                merged[merged.count - 1] = last
            } else {
                merged.append((s, e))
            }
        }
        return merged.map { Block(start: $0.0, width: $0.1 - $0.0, busy: true) }
    }

    /// Position of "now" inside the window, or nil when outside.
    public static func nowMarker(now: Date, dayStart: Date, dayEnd: Date) -> Double? {
        let span = dayEnd.timeIntervalSince(dayStart)
        guard span > 0 else { return nil }
        let t = now.timeIntervalSince(dayStart) / span
        return (0...1).contains(t) ? t : nil
    }

    /// Window shown in the timeline bar: local day bounds for `date`.
    public static func dayWindow(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
    }

    /// Next `limit` events strictly ordered by start, excluding past events.
    public static func upcoming(events: [MeetEvent], now: Date, limit: Int = 5) -> [MeetEvent] {
        events
            .filter { $0.end > now && !$0.isAllDayOrZeroLength }
            .sorted { lhs, rhs in lhs.start == rhs.start ? lhs.title < rhs.title : lhs.start < rhs.start }
            .prefix(limit)
            .map { $0 }
    }
}

