import Foundation

/// Calendar permission as the status line needs it.
public enum CalendarAccess: Equatable, Sendable {
    case notDetermined, denied, granted
}

/// What the menu bar item shows.
public enum MenuBarStyle: String, CaseIterable, Codable, Sendable {
    case short, compact, full, iconOnly
    public var title: String {
        switch self {
        case .short: return "Icon and time to the next call"
        case .full: return "Next call, microphone and mute"
        case .compact: return "Next call and mute"
        case .iconOnly: return "Icon only"
        }
    }
}

/// The three parts of the combined status. Pure values, so tests need no hardware.
public struct CallSnapshot: Equatable, Sendable {
    public var now: Date
    public var access: CalendarAccess
    public var nextEvent: MeetEvent?
    public var micName: String?
    public var muted: Bool?
    public var talking: Bool
    public init(now: Date, access: CalendarAccess, nextEvent: MeetEvent?, micName: String?, muted: Bool?, talking: Bool = false) {
        self.now = now; self.access = access; self.nextEvent = nextEvent
        self.micName = micName; self.muted = muted; self.talking = talking
    }
}

/// One status line for all three parts, for example "Standup in 4 min · MacBook Pro mic · Muted".
public enum CallStatus {
    public static let separator = " · "

    /// "now", "in 4 min", "in 1 h 05 min", "in 2 d 3 h". Empty when the event is over.
    public static func countdown(now: Date, event: MeetEvent) -> String {
        if now >= event.end { return "" }
        if now >= event.start { return "now" }
        let total = max(1, Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))
        let days = total / 1440, hours = (total % 1440) / 60, minutes = total % 60
        if days > 0 { return "in \(days) d \(hours) h" }
        if hours > 0 { return String(format: "in %d h %02d min", hours, minutes) }
        return "in \(minutes) min"
    }

    /// Title shortened to `limit` characters, with one line break removed.
    public static func shortTitle(_ title: String, limit: Int = 18) -> String {
        let clean = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let value = clean.isEmpty ? "Call" : clean
        guard value.count > limit, limit > 1 else { return value }
        return value.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "Standup in 4 min". Nil when the calendar part has nothing to say.
    public static func meetingPart(_ snapshot: CallSnapshot, titleLimit: Int = 18) -> String? {
        switch snapshot.access {
        case .denied: return "Calendar off"
        case .notDetermined: return nil
        case .granted:
            guard let event = snapshot.nextEvent else { return "No calls" }
            let time = countdown(now: snapshot.now, event: event)
            return time.isEmpty ? "No calls" : shortTitle(event.title, limit: titleLimit) + " " + time
        }
    }

    /// "MacBook Pro Microphone" becomes "MacBook Pro mic".
    public static func shortMicName(_ name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "No mic" }
        for suffix in [" Microphone", " microphone", " Mic"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count)) + " mic"
        }
        return name
    }

    /// "Muted", "Live" (push-to-talk held), "Mic on". Nil when the state is unknown.
    public static func mutePart(muted: Bool?, talking: Bool) -> String? {
        if talking { return "Live" }
        guard let muted else { return nil }
        return muted ? "Muted" : "Mic on"
    }

    public static func line(_ snapshot: CallSnapshot) -> String {
        [meetingPart(snapshot), shortMicName(snapshot.micName), mutePart(muted: snapshot.muted, talking: snapshot.talking)]
            .compactMap { $0 }.joined(separator: separator)
    }

    /// "4m", "1h 5m", "now". Empty when there is no call in the next 12 hours or no calendar access.
    public static func shortCountdown(_ snapshot: CallSnapshot) -> String {
        guard snapshot.access == .granted, let event = snapshot.nextEvent, snapshot.now < event.end else { return "" }
        if snapshot.now >= event.start { return "now" }
        let total = max(1, Int((event.start.timeIntervalSince(snapshot.now) / 60).rounded(.up)))
        if total < 60 { return "\(total)m" }
        if total < 600 { return "\(total / 60)h \(total % 60)m" }
        if total < 720 { return "\(total / 60)h" }
        return ""
    }

    public static func menuBarText(_ snapshot: CallSnapshot, style: MenuBarStyle) -> String {
        switch style {
        case .short: return shortCountdown(snapshot)
        case .full: return line(snapshot)
        case .compact:
            let parts = [meetingPart(snapshot, titleLimit: 14), mutePart(muted: snapshot.muted, talking: snapshot.talking)].compactMap { $0 }
            return parts.isEmpty ? shortMicName(snapshot.micName) : parts.joined(separator: separator)
        case .iconOnly: return ""
        }
    }
}

/// What to do when a call is about to start.
public struct PreCallPlan: Equatable, Sendable {
    public var checkMicrophone: Bool
    public var remindToUnmute: Bool
    public init(checkMicrophone: Bool, remindToUnmute: Bool) {
        self.checkMicrophone = checkMicrophone; self.remindToUnmute = remindToUnmute
    }
    public var isEmpty: Bool { !checkMicrophone && !remindToUnmute }
}

/// The link between the three parts: the next call starts the microphone check and the unmute reminder.
public enum PreCallCheck {
    public static let defaultLead: TimeInterval = 60

    /// The event that needs a check now: it starts within `lead` seconds, or started less than one minute ago,
    /// and it was not checked before.
    public static func dueEvent(events: [MeetEvent], now: Date, lead: TimeInterval = defaultLead, handled: Set<String>) -> MeetEvent? {
        events.filter { !$0.isAllDayOrZeroLength && !handled.contains($0.id) }
            .filter { now >= $0.start.addingTimeInterval(-lead) && now < min($0.end, $0.start.addingTimeInterval(60)) }
            .min { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    public static func plan(checkMicrophone: Bool, remindIfMuted: Bool, muted: Bool?) -> PreCallPlan {
        PreCallPlan(checkMicrophone: checkMicrophone, remindToUnmute: remindIfMuted && muted == true)
    }

    /// Text for the menu and the notification.
    public static func report(event: MeetEvent, now: Date, micName: String?, muted: Bool?, shortcut: String) -> String {
        let time = CallStatus.countdown(now: now, event: event)
        let head = CallStatus.shortTitle(event.title, limit: 40) + (time == "now" ? " starts now." : " starts \(time).")
        let mic = " Microphone: " + CallStatus.shortMicName(micName) + "."
        let mute = muted == true ? " You are muted. Press \(shortcut) to unmute." : ""
        return head + mic + mute
    }

    /// Forget events that ended more than one day ago.
    public static func prune(_ handled: [String: Date], now: Date) -> [String: Date] {
        handled.filter { now.timeIntervalSince($0.value) < 86400 }
    }
}

/// Is the Mac ready for the next call? Uses the state of all three parts.
public enum CallReadiness: Equatable, Sendable {
    case ready
    case wrongMicrophone(preferred: String)
    case muted
    case noMicrophone

    /// `currentUID` is the default input. `preferredUID` is the guard target (nil when the guard has none).
    public static func evaluate(currentUID: String?, currentName: String?, preferredUID: String?, preferredName: String?,
                                guardEnabled: Bool, muted: Bool?, talking: Bool) -> CallReadiness {
        guard currentUID != nil else { return .noMicrophone }
        if guardEnabled, let preferredUID, preferredUID != currentUID { return .wrongMicrophone(preferred: preferredName ?? "preferred mic") }
        if muted == true && !talking { return .muted }
        return .ready
    }

    public var text: String {
        switch self {
        case .ready: return "Ready"
        case .wrongMicrophone(let name): return "Not on " + CallStatus.shortMicName(name)
        case .muted: return "Muted"
        case .noMicrophone: return "No microphone"
        }
    }
    public var isReady: Bool { self == .ready }
}

/// What happens to the mute state when a call starts.
public enum CallStartMute: String, CaseIterable, Codable, Sendable {
    case keep, mute, unmute
    public var title: String {
        switch self {
        case .keep: return "Keep the current mute state"
        case .mute: return "Mute the microphone"
        case .unmute: return "Unmute the microphone"
        }
    }
    /// The mute target at call start. Nil means no change. Push-to-talk owns the state while it is held.
    public func target(currentlyMuted: Bool?, talking: Bool) -> MicTarget? {
        guard !talking, let currentlyMuted else { return nil }
        switch self {
        case .keep: return nil
        case .mute: return currentlyMuted ? nil : .muted
        case .unmute: return currentlyMuted ? .unmuted : nil
        }
    }
}

/// Notification texts. By default they do not show the meeting title, because the Mac can be unattended.
public enum CallNotice {
    /// "now", "in 1 minute", "in 10 minutes", "in 1 h 05 min".
    public static func spokenCountdown(now: Date, event: MeetEvent) -> String {
        if now >= event.start { return "now" }
        let total = max(1, Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))
        if total == 1 { return "in 1 minute" }
        if total < 60 { return "in \(total) minutes" }
        return CallStatus.countdown(now: now, event: event)
    }

    /// The reminder some minutes before a call ("Remind me before a call").
    public static func reminder(event: MeetEvent, now: Date, showTitle: Bool) -> (title: String, body: String) {
        let when = spokenCountdown(now: now, event: event)
        if showTitle { return (CallStatus.shortTitle(event.title, limit: 60), "Starts \(when). Open CallReady to join it.") }
        return ("Call \(when)", "Open CallReady to join it.")
    }

    /// The reminder one minute before the call when the microphone is muted.
    public static func unmute(event: MeetEvent, now: Date, shortcut: String, showTitle: Bool) -> (title: String, body: String) {
        let when = spokenCountdown(now: now, event: event)
        let body = "You're muted. Press \(shortcut) to unmute."
        if showTitle { return (CallStatus.shortTitle(event.title, limit: 60), "Starts \(when). " + body) }
        return ("Call \(when)", body)
    }
}
