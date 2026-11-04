import AppKit
import SwiftUI
import Testing
import CallCore
import EventKit
@testable import CallReady

@MainActor
@Suite(.serialized)
struct CalendarModelTests {
    private func isolatedModel(now: Date = Date()) -> CalendarModel {
        CalendarModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, startTimer: false, now: now)
    }

    @Test func grantedEventsPopulateNextEvent() {
        let model = isolatedModel()
        model.applyAuthorization(.fullAccess)
        model.events = FixtureCalendar.events(now: model.now)
        #expect(model.access == .granted)
        #expect(model.nextEvent != nil)
    }

    @Test func deniedAccessStateIsVisibleAndClearsEvents() {
        let model = isolatedModel()
        model.applyAuthorization(.denied)
        #expect(model.access == .denied)
        #expect(model.events.isEmpty)
        let fixture = FixtureApp(); defer { fixture.close() }
        let host = NSHostingView(rootView: NextCallCard(app: fixture.app, calendar: model, mute: fixture.mute))
        #expect(host.fittingSize.width > 0)
    }

    @Test func writeOnlyAccessCountsAsDenied() {
        let model = isolatedModel()
        model.applyAuthorization(.writeOnly)
        #expect(model.access == .denied)
    }

    @Test func notDeterminedAccessAsksFirst() {
        let model = isolatedModel()
        model.applyAuthorization(.notDetermined)
        #expect(model.access == .notDetermined)
        #expect(!model.authorized && !model.accessDenied)
    }

    @Test func reminderPreferenceRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = CalendarModel(defaults: defaults, startTimer: false)
        model.reminderMinutes = 15
        #expect(defaults.integer(forKey: "reminderMinutes") == 15)
        #expect(CalendarModel(defaults: defaults, startTimer: false).reminderMinutes == 15)
    }

    @Test func sharedClockAdvancesWithoutMovingEvents() {
        let model = isolatedModel()
        model.applyAuthorization(.fullAccess)
        model.events = FixtureCalendar.events(now: model.now)
        let original = model.events
        let next = model.nextEvent!
        model.tick(at: next.start)
        #expect(CallStatus.countdown(now: model.now, event: next) == "now")
        model.tick(at: next.end)
        #expect(model.nextEvent?.id != next.id)
        // Ticks reload from EventKit only when access is real; injected events survive in this runner.
        #expect(model.events.count <= original.count)
    }

    @Test func calendarSelectionPersists() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = CalendarModel(defaults: defaults, startTimer: false)
        model.calendars = [CalendarChoice(id: "a", title: "A"), CalendarChoice(id: "b", title: "B")]
        model.selectCalendar("a", enabled: false)
        #expect(model.selectedCalendarIDs == ["b"])
        let restored = CalendarModel(defaults: defaults, startTimer: false)
        #expect(restored.selectedCalendarIDs == ["b"])
        #expect(!restored.isCalendarSelected("a") && restored.isCalendarSelected("b"))
    }

    @Test func neverDefaultsToDisabledAndRemovesLegacyHistory() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(["private-id": 1.0], forKey: "lastFired")
        let model = CalendarModel(defaults: defaults, startTimer: false)
        #expect(model.reminderMinutes == 0)
        #expect(defaults.object(forKey: "lastFired") == nil)
        model.applyAuthorization(.fullAccess)
        model.events = FixtureCalendar.events(now: model.now)
        model.fireDueReminders()
        #expect(model.lastFired.isEmpty)
    }

    @Test func remindersFireOncePerEvent() {
        let model = isolatedModel()
        model.applyAuthorization(.fullAccess)
        model.events = FixtureCalendar.events(now: model.now)
        model.reminderMinutes = 10
        let next = model.nextEvent!
        model.now = next.start.addingTimeInterval(-300)
        model.fireDueReminders(); model.fireDueReminders()
        #expect(model.lastFired.count == 1 && model.lastFired[next.id] != nil)
    }

    @Test func revocationClearsLiveDataAndGrantUpdatesState() {
        let model = isolatedModel()
        model.applyAuthorization(.fullAccess)
        #expect(model.authorized)
        model.events = FixtureCalendar.events(now: Date())
        model.applyAuthorization(.denied)
        #expect(!model.authorized && model.accessDenied)
        #expect(model.events.isEmpty && model.lastFired.isEmpty)
        model.applyAuthorization(.fullAccess)
        #expect(model.authorized && !model.accessDenied)
    }

    @Test func tickCallsCoordinatorHook() {
        let model = isolatedModel()
        var ticks: [Date] = []
        model.onTick = { ticks.append($0) }
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        model.tick(at: date)
        #expect(ticks == [date])
    }
}
