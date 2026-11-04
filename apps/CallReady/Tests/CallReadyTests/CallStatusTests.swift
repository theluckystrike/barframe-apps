import Foundation
import Testing
@testable import CallCore

@Suite struct CallStatusTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func event(_ minutes: Double, _ length: Double = 30, title: String = "Standup", id: String = "e1", allDay: Bool = false) -> MeetEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return MeetEvent(id: id, title: title, start: start, end: start.addingTimeInterval(length * 60), isAllDay: allDay)
    }
    func snap(_ e: MeetEvent?, access: CalendarAccess = .granted, mic: String? = "MacBook Pro Microphone", muted: Bool? = true, talking: Bool = false) -> CallSnapshot {
        CallSnapshot(now: now, access: access, nextEvent: e, micName: mic, muted: muted, talking: talking)
    }

    @Test func combinedLineHasAllThreeParts() {
        #expect(CallStatus.line(snap(event(4))) == "Standup in 4 min · MacBook Pro mic · Muted")
        #expect(CallStatus.line(snap(event(4), muted: false)) == "Standup in 4 min · MacBook Pro mic · Mic on")
        #expect(CallStatus.line(snap(event(4), talking: true)) == "Standup in 4 min · MacBook Pro mic · Live")
    }
    @Test func countdownFormats() {
        #expect(CallStatus.countdown(now: now, event: event(4)) == "in 4 min")
        #expect(CallStatus.countdown(now: now, event: event(3.2)) == "in 4 min")
        #expect(CallStatus.countdown(now: now, event: event(0.1)) == "in 1 min")
        #expect(CallStatus.countdown(now: now, event: event(65)) == "in 1 h 05 min")
        #expect(CallStatus.countdown(now: now, event: event(60 * 27)) == "in 1 d 3 h")
        #expect(CallStatus.countdown(now: now, event: event(-5)) == "now")
        #expect(CallStatus.countdown(now: now, event: event(-40)) == "")
    }
    @Test func calendarStatesChangeOnlyTheMeetingPart() {
        #expect(CallStatus.line(snap(nil)) == "No calls · MacBook Pro mic · Muted")
        #expect(CallStatus.line(snap(event(4), access: .denied)) == "Calendar off · MacBook Pro mic · Muted")
        #expect(CallStatus.line(snap(event(4), access: .notDetermined)) == "MacBook Pro mic · Muted")
        #expect(CallStatus.line(snap(event(-40))) == "No calls · MacBook Pro mic · Muted")
    }
    @Test func microphoneNamesShortenAndUnknownStatesDrop() {
        #expect(CallStatus.shortMicName("MacBook Pro Microphone") == "MacBook Pro mic")
        #expect(CallStatus.shortMicName("Yeti Mic") == "Yeti mic")
        #expect(CallStatus.shortMicName("Scarlett 2i2") == "Scarlett 2i2")
        #expect(CallStatus.shortMicName(nil) == "No mic")
        #expect(CallStatus.shortMicName("  ") == "No mic")
        #expect(CallStatus.line(snap(nil, mic: nil, muted: nil)) == "No calls · No mic")
    }
    @Test func longTitlesAreShortened() {
        let line = CallStatus.line(snap(event(4, title: "Quarterly planning with the whole design team")))
        #expect(line.hasPrefix("Quarterly plannin… in 4 min"))
        #expect(CallStatus.shortTitle("") == "Call")
        #expect(CallStatus.shortTitle("A\nB") == "A B")
    }
    @Test func menuBarStyles() {
        let s = snap(event(4))
        #expect(CallStatus.menuBarText(s, style: .full) == CallStatus.line(s))
        #expect(CallStatus.menuBarText(s, style: .compact) == "Standup in 4 min · Muted")
        #expect(CallStatus.menuBarText(s, style: .iconOnly) == "")
        #expect(CallStatus.menuBarText(snap(nil, access: .notDetermined, muted: nil), style: .compact) == "MacBook Pro mic")
        #expect(MenuBarStyle.allCases.count == 4)
    }
    @Test func shortLabelFitsBesideTheNotch() {
        #expect(CallStatus.menuBarText(snap(event(4)), style: .short) == "4m")
        #expect(CallStatus.menuBarText(snap(event(65)), style: .short) == "1h 5m")
        #expect(CallStatus.menuBarText(snap(event(-5)), style: .short) == "now")
        #expect(CallStatus.menuBarText(snap(event(60 * 13)), style: .short) == "")
        #expect(CallStatus.menuBarText(snap(event(-40)), style: .short) == "")
        #expect(CallStatus.menuBarText(snap(event(4), access: .denied), style: .short) == "")
        for minutes in stride(from: 0.5, to: 720, by: 7.3) {
            #expect(CallStatus.menuBarText(snap(event(minutes)), style: .short).count <= 6)
        }
    }
    @Test func notificationsAreGenericByDefault() {
        let generic = CallNotice.unmute(event: event(1), now: now, shortcut: "⇧⌥M", showTitle: false)
        #expect(generic.title == "Call in 1 minute")
        #expect(generic.body == "You're muted. Press ⇧⌥M to unmute.")
        let titled = CallNotice.unmute(event: event(1), now: now, shortcut: "⇧⌥M", showTitle: true)
        #expect(titled.title == "Standup" && titled.body.hasPrefix("Starts in 1 minute."))
        let reminder = CallNotice.reminder(event: event(10), now: now, showTitle: false)
        #expect(reminder.title == "Call in 10 minutes" && reminder.body == "Open CallReady to join it.")
        #expect(!reminder.title.contains("Standup") && !reminder.body.contains("Standup"))
        #expect(CallNotice.reminder(event: event(10), now: now, showTitle: true).title == "Standup")
        #expect(CallNotice.spokenCountdown(now: now, event: event(0)) == "now")
        #expect(CallNotice.spokenCountdown(now: now, event: event(90)) == "in 1 h 30 min")
    }
    @Test func preCallWindowIsOneMinuteBeforeToOneMinuteAfterStart() {
        let e = [event(1.02)]
        #expect(PreCallCheck.dueEvent(events: e, now: now, handled: []) == nil)
        #expect(PreCallCheck.dueEvent(events: [event(1)], now: now, handled: [])?.id == "e1")
        #expect(PreCallCheck.dueEvent(events: [event(-0.98)], now: now, handled: [])?.id == "e1")
        #expect(PreCallCheck.dueEvent(events: [event(-1.02)], now: now, handled: []) == nil)
        #expect(PreCallCheck.dueEvent(events: [event(0.5)], now: now, handled: ["e1"]) == nil)
        #expect(PreCallCheck.dueEvent(events: [event(0.5, allDay: true)], now: now, handled: []) == nil)
        #expect(PreCallCheck.dueEvent(events: [event(0.5, id: "b"), event(0.2, id: "a")], now: now, handled: [])?.id == "a")
        #expect(PreCallCheck.dueEvent(events: [event(0.5)], now: now, lead: 0, handled: []) == nil)
        #expect(PreCallCheck.dueEvent(events: [event(0)], now: now, lead: 0, handled: [])?.id == "e1")
    }
    @Test func preCallPlanAndReport() {
        #expect(PreCallCheck.plan(checkMicrophone: true, remindIfMuted: true, muted: true) == PreCallPlan(checkMicrophone: true, remindToUnmute: true))
        #expect(PreCallCheck.plan(checkMicrophone: false, remindIfMuted: true, muted: false).isEmpty)
        #expect(!PreCallCheck.plan(checkMicrophone: false, remindIfMuted: true, muted: nil).remindToUnmute)
        let text = PreCallCheck.report(event: event(1), now: now, micName: "MacBook Pro Microphone", muted: true, shortcut: "⇧⌥M")
        #expect(text == "Standup starts in 1 min. Microphone: MacBook Pro mic. You are muted. Press ⇧⌥M to unmute.")
        #expect(PreCallCheck.report(event: event(0), now: now, micName: nil, muted: false, shortcut: "⇧⌥M") == "Standup starts now. Microphone: No mic.")
        let pruned = PreCallCheck.prune(["old": now.addingTimeInterval(-90000), "new": now], now: now)
        #expect(Array(pruned.keys) == ["new"])
    }
    @Test func readinessNeedsPreferredMicAndOpenMute() {
        func r(_ current: String?, _ preferred: String?, guardOn: Bool = true, muted: Bool? = false, talking: Bool = false) -> CallReadiness {
            CallReadiness.evaluate(currentUID: current, currentName: current, preferredUID: preferred, preferredName: "Studio Microphone",
                                   guardEnabled: guardOn, muted: muted, talking: talking)
        }
        #expect(r("a", "a") == .ready)
        #expect(r("bt", "a") == .wrongMicrophone(preferred: "Studio Microphone"))
        #expect(r("bt", "a").text == "Not on Studio mic")
        #expect(r("bt", "a", guardOn: false) == .ready)
        #expect(r("a", "a", muted: true) == .muted)
        #expect(r("a", "a", muted: true, talking: true) == .ready)
        #expect(r("a", nil) == .ready)
        #expect(r(nil, "a") == .noMicrophone)
    }
    @Test func callStartMuteTargets() {
        #expect(CallStartMute.keep.target(currentlyMuted: true, talking: false) == nil)
        #expect(CallStartMute.unmute.target(currentlyMuted: true, talking: false) == .unmuted)
        #expect(CallStartMute.unmute.target(currentlyMuted: false, talking: false) == nil)
        #expect(CallStartMute.mute.target(currentlyMuted: false, talking: false) == .muted)
        #expect(CallStartMute.mute.target(currentlyMuted: true, talking: false) == nil)
        #expect(CallStartMute.mute.target(currentlyMuted: false, talking: true) == nil)
        #expect(CallStartMute.unmute.target(currentlyMuted: nil, talking: false) == nil)
    }
}
