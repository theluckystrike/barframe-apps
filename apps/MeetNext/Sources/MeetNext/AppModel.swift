import SwiftUI
import MeetNextCore
import EventKit
import UserNotifications

struct CalendarChoice: Identifiable {
    let id: String
    let title: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var events: [MeetEvent] = []
    @Published var sampleMode = false
    @Published var accessDenied = false
    @Published var authorized = false
    @Published var statusText = ""
    @Published var now = Date()
    @Published var calendars: [CalendarChoice] = []
    @Published private(set) var selectedCalendarIDs: Set<String>?
    @Published private(set) var sampleCalendarIDs: Set<String> = ["sample-work", "sample-personal"]
    @Published var reminderMinutes: Int {
        didSet {
            defaults.set(reminderMinutes, forKey: "reminderMinutes")
            if reminderMinutes == 0 { clearReminderHistory() }
        }
    }
    let store = EKEventStore()
    private let defaults: UserDefaults
    private var timer: Timer?
    private var sampleEvents: [MeetEvent] = []
    private(set) var lastFired: [String: Date] = [:]

    init(defaults: UserDefaults = .standard, startTimer: Bool = true) {
        self.defaults = defaults
        reminderMinutes = defaults.object(forKey: "reminderMinutes") as? Int ?? 0
        selectedCalendarIDs = defaults.stringArray(forKey: "selectedCalendarIDs").map { Set($0) }
        // Retire the old persistent event-identifier history.
        defaults.removeObject(forKey: "lastFired")
        refreshAuthorization()
        loadEvents()
        if startTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func refreshAuthorization() {
        applyAuthorization(EKEventStore.authorizationStatus(for: .event))
    }

    func applyAuthorization(_ status: EKAuthorizationStatus) {
        authorized = status == .fullAccess || status == .authorized
        accessDenied = status == .denied || status == .restricted
        if !authorized && !sampleMode {
            events = []
            calendars = []
            clearReminderHistory()
        }
    }

    func becameActive() {
        refreshAuthorization()
        loadEvents()
    }

    func requestAccess() {
        Task { @MainActor in
            do {
                _ = try await store.requestFullAccessToEvents()
                becameActive()
            } catch {
                refreshAuthorization()
                statusText = error.localizedDescription
            }
        }
    }

    var calendarChoices: [CalendarChoice] {
        sampleMode ? [CalendarChoice(id: "sample-work", title: "Sample Work"), CalendarChoice(id: "sample-personal", title: "Sample Personal")] : calendars
    }

    func isCalendarSelected(_ id: String) -> Bool {
        sampleMode ? sampleCalendarIDs.contains(id) : selectedCalendarIDs?.contains(id) ?? true
    }

    func selectCalendar(_ id: String, enabled: Bool) {
        if sampleMode {
            if enabled { sampleCalendarIDs.insert(id) } else { sampleCalendarIDs.remove(id) }
            events = sampleEvents.filter { sampleCalendarIDs.contains($0.calendarID) }
        } else {
            var ids = selectedCalendarIDs ?? Set(calendars.map(\.id))
            if enabled { ids.insert(id) } else { ids.remove(id) }
            selectedCalendarIDs = ids
            defaults.set(Array(ids).sorted(), forKey: "selectedCalendarIDs")
            loadEvents()
        }
        clearReminderHistory()
    }

    func loadEvents() {
        guard authorized, !sampleMode else { return }
        let available = store.calendars(for: .event)
        calendars = available.map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title) }
        let selected = available.filter { isCalendarSelected($0.calendarIdentifier) }
        guard !selected.isEmpty else { events = []; return }
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        events = store.events(matching: predicate).map { ek in
            MeetEvent(id: ek.eventIdentifier ?? UUID().uuidString, title: ek.title ?? "Untitled event",
                start: ek.startDate, end: ek.endDate,
                searchText: [ek.url?.absoluteString, ek.location, ek.notes].compactMap { $0 }.joined(separator: "\n"),
                isAllDay: ek.isAllDay, calendarID: ek.calendar.calendarIdentifier)
        }.filter { !$0.isAllDayOrZeroLength }
    }

    func tick(at date: Date = Date()) {
        let previous = now
        now = date
        if Int(date.timeIntervalSince1970 / 30) != Int(previous.timeIntervalSince1970 / 30) {
            refreshAuthorization()
            loadEvents()
        }
        fireDueReminders()
    }

    func toggleSample(_ on: Bool) {
        sampleMode = on
        clearReminderHistory()
        now = Date()
        if on {
            sampleEvents = SampleCalendar.events(now: now)
            events = sampleEvents.filter { sampleCalendarIDs.contains($0.calendarID) }
        } else {
            events = []
            refreshAuthorization()
            loadEvents()
        }
    }

    // UserNotifications requires an application bundle, which command-line
    // Swift Testing runners do not have.
    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }

    func clearReminderHistory() {
        lastFired = [:]
        notificationCenter?.removeAllPendingNotificationRequests()
        notificationCenter?.removeAllDeliveredNotifications()
    }

    func fireDueReminders() {
        guard reminderMinutes > 0, sampleMode || authorized else { return }
        lastFired = lastFired.filter { now.timeIntervalSince($0.value) < 172800 }
        for event in events where Countdown.shouldRemind(event: event, now: now, minutesBefore: reminderMinutes, lastFired: lastFired[event.id]) {
            lastFired[event.id] = now
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = "Meeting \(Countdown.menuBarText(now: now, next: event)). Open MeetNext to view it."
            content.sound = .default
            notificationCenter?.add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
        }
    }

    func requestNotifications() {
        guard reminderMinutes > 0 else { return }
        notificationCenter?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var nextEvent: MeetEvent? { DayTimeline.upcoming(events: events, now: now, limit: 1).first }
    var menuBarTitle: String {
        if accessDenied && !sampleMode { return "Access needed" }
        let headline = Countdown.headline(now: now, next: nextEvent)
        return (sampleMode ? "Sample · " : "") + (headline.isEmpty ? "MeetNext" : headline)
    }
}
