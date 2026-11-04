import Testing
import Foundation
@testable import CallReady
@testable import CallCore

private func date(_ secondsFromNow: TimeInterval, from now: Date) -> Date {
    now.addingTimeInterval(secondsFromNow)
}

@Suite struct JoinParserTests {
    @Test func detectsFourServices() {
        for (url, expected) in [("https://zoom.us/j/123", "Zoom"),
                                ("https://meet.google.com/abc-defg", "Google Meet"),
                                ("https://teams.microsoft.com/l/meetup-join/x", "Microsoft Teams"),
                                ("https://subdomain.webex.com/meet/u", "Webex")] {
            let link = JoinParser.firstJoinLink(in: url)
            #expect(link != nil)
            #expect(link.flatMap { JoinParser.service(for: $0) } == expected)
        }
    }

    @Test func picksLinkFromLocationAndNotesMixedText() {
        let text = "Room 4\nhost notes\nhttps://example.com/other\njoin: https://meet.google.com/xyz\nBye"
        let link = JoinParser.firstJoinLink(in: text)
        #expect(JoinParser.service(for: link!) == "Google Meet")
    }

    @Test func rejectsNonMeetingLinksAndEmpty() {
        #expect(JoinParser.firstJoinLink(in: "https://example.com/call") == nil)
        #expect(JoinParser.firstJoinLink(in: "") == nil)
        #expect(JoinParser.firstJoinLink(in: "no links here") == nil)
    }

    @Test func bareHostAndTrailingText() {
        let link = JoinParser.firstJoinLink(in: "Join https://us02web.zoom.us/j/5551112222?pwd=abc now")
        #expect(link?.host == "us02web.zoom.us")
        #expect(JoinParser.service(for: link!) == "Zoom")
    }

    @Test func isJoinLinkNegative() {
        #expect(!JoinParser.isJoinLink(URL(string: "https://apple.com")!))
        #expect(JoinParser.isJoinLink(URL(string: "https://meet.google.com/aaa")!))
    }
}

@Suite struct CountdownTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func event(in seconds: TimeInterval, length: TimeInterval = 1800, title: String = "Standup") -> MeetEvent {
        MeetEvent(id: "t", title: title, start: now.addingTimeInterval(seconds), end: now.addingTimeInterval(seconds + length))
    }

    @Test func menuBarPhases() {
        #expect(Countdown.menuBarText(now: now, next: nil).isEmpty)
        #expect(Countdown.menuBarText(now: now, next: event(in: 300)) == "in 5m")
        #expect(Countdown.menuBarText(now: now, next: event(in: 0)) == "now")
        #expect(Countdown.menuBarText(now: now.addingTimeInterval(600), next: event(in: 0)) == "now")
        #expect(Countdown.menuBarText(now: now.addingTimeInterval(1900), next: event(in: 0)).isEmpty)
    }

    @Test func hoursAndDaysFormat() {
        #expect(Countdown.menuBarText(now: now, next: event(in: 2 * 86400 + 3 * 3600)).hasPrefix("in 2d 3h"))
        let text = Countdown.menuBarText(now: now, next: event(in: 2 * 3600 + 5 * 60))
        #expect(text == "in 2h 05m")
    }

    @Test func headlineTruncatesAndKeepsCountdown() {
        let long = Countdown.headline(now: now, next: event(in: 60, title: String(repeating: "A", count: 40)))
        #expect(long.count <= 18 + 1 + 1 + 6)
        #expect(long.hasSuffix("… · in 1m"))
        #expect(Countdown.headline(now: now, next: nil).isEmpty)
        #expect(Countdown.headline(now: now, next: event(in: -3600)).isEmpty)
    }

    @Test func reminderWindowFiresOnce() {
        let e = event(in: 600)
        #expect(Countdown.shouldRemind(event: e, now: now.addingTimeInterval(60), minutesBefore: 10, lastFired: nil))
        #expect(!Countdown.shouldRemind(event: e, now: now.addingTimeInterval(60), minutesBefore: 10, lastFired: now))
        #expect(!Countdown.shouldRemind(event: e, now: now.addingTimeInterval(-60), minutesBefore: 10, lastFired: nil))
        #expect(!Countdown.shouldRemind(event: e, now: now.addingTimeInterval(60), minutesBefore: 0, lastFired: nil))
        // Never suppresses reminders, including at start.
        #expect(!Countdown.shouldRemind(event: e, now: e.start, minutesBefore: 0, lastFired: nil))
        let past = event(in: -1800)
        #expect(!Countdown.shouldRemind(event: past, now: now, minutesBefore: 5, lastFired: nil))
    }
}

@Suite struct TimelineTests {
    private let day = Date(timeIntervalSince1970: 1_000_000)
    private var dayEnd: Date { day.addingTimeInterval(86400) }
    private func event(_ s: TimeInterval, _ e: TimeInterval) -> MeetEvent {
        MeetEvent(id: "\(s)", title: "E", start: day.addingTimeInterval(s), end: day.addingTimeInterval(e))
    }

    @Test func blocksClipAndMergeOverlaps() {
        let blocks = DayTimeline.blocks(events: [event(0, 3600), event(1800, 7200), event(-100, 200), event(80000, 90000)], dayStart: day, dayEnd: dayEnd)
        #expect(blocks.count == 2)
        #expect(blocks[0] == DayTimeline.Block(start: 0.0, width: 2.0 / 24.0, busy: true))
        #expect(blocks[1].start > 0.9 && blocks[1].busy)
    }

    @Test func disjointBlocksOrdered() {
        let blocks = DayTimeline.blocks(events: [event(7200, 10800), event(0, 3600)], dayStart: day, dayEnd: dayEnd)
        #expect(blocks.map(\.start) == [0, 7200 / 86400])
        #expect(blocks.allSatisfy { $0.busy })
    }

    @Test func emptyAndDegenerateWindows() {
        #expect(DayTimeline.blocks(events: [], dayStart: day, dayEnd: dayEnd).isEmpty)
        #expect(DayTimeline.blocks(events: [event(0, 100)], dayStart: day, dayEnd: day).isEmpty)
        #expect(DayTimeline.nowMarker(now: day.addingTimeInterval(43200), dayStart: day, dayEnd: dayEnd) == 0.5)
        #expect(DayTimeline.nowMarker(now: day.addingTimeInterval(-1), dayStart: day, dayEnd: dayEnd) == nil)
        #expect(DayTimeline.nowMarker(now: day.addingTimeInterval(86401), dayStart: day, dayEnd: dayEnd) == nil)
    }

    @Test func upcomingOrdersLimitsAndSkipsPastAndZeroLength() {
        let past = MeetEvent(id: "p", title: "Past", start: day.addingTimeInterval(-100), end: day.addingTimeInterval(-50))
        let zero = MeetEvent(id: "z", title: "Zero", start: day, end: day)
        let list = [past, zero, event(7200, 8000), event(3600, 4000), event(10000, 11000), event(200, 300), event(300, 400), event(400, 500)]
        let up = DayTimeline.upcoming(events: list, now: day, limit: 5)
        #expect(up.count == 5)
        #expect(up.map { $0.id } == ["200.0", "300.0", "400.0", "3600.0", "7200.0"])
    }

    @Test func serviceNamesResolve() {
        #expect(JoinParser.service(for: URL(string: "https://zoom.us/j/1")!) == "Zoom")
        #expect(JoinParser.service(for: URL(string: "https://meet.google.com/xyz")!) == "Google Meet")
        #expect(JoinParser.service(for: URL(string: "https://teams.microsoft.com/l/x")!) == "Microsoft Teams")
        #expect(JoinParser.service(for: URL(string: "https://a.webex.com/meet/b")!) == "Webex")
        #expect(JoinParser.service(for: URL(string: "https://example.com")!) == nil)
        #expect(JoinParser.service(for: URL(string: "not a url")!) == nil)
    }

    @Test func fixtureShape() {
        let events = FixtureCalendar.events(now: day)
        #expect(events.count == 6)
        #expect(events.allSatisfy { $0.title.hasPrefix("Fixture ") })
        #expect(events.filter { JoinParser.firstJoinLink(in: $0.searchText) != nil }.count == 4)
        #expect(events.filter { JoinParser.firstJoinLink(in: $0.searchText) == nil }.count == 2)
    }
}

@Suite struct AuditCoreRegressionTests {
    @Test func invitationParametersAndFragmentSurvive() {
        let value = "https://company.webex.com/company/j.php?MTID=m123456&pwd=secret#join"
        #expect(JoinParser.firstJoinLink(in: value)?.absoluteString == value)
    }
    @Test func allDayEventsAreExcluded() {
        let now = Date()
        let event = MeetEvent(id: "all", title: "All day", start: now, end: now.addingTimeInterval(86400), isAllDay: true)
        #expect(event.isAllDayOrZeroLength)
        #expect(DayTimeline.upcoming(events: [event], now: now).isEmpty)
        #expect(DayTimeline.blocks(events: [event], dayStart: now, dayEnd: event.end).isEmpty)
    }
}
