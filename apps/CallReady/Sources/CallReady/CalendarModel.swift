import SwiftUI
import EventKit
import UserNotifications
import CallCore

struct CalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Delivers local notifications. Command-line test runners have no app bundle, so they get no center.
@MainActor enum LocalNotifier {
    static var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }
    static func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

/// Next call part: reads events from the selected calendars for today and tomorrow. Read only.
@MainActor final class CalendarModel: ObservableObject {
    @Published var events: [MeetEvent] = []
    @Published var accessDenied = false
    @Published var authorized = false
    @Published var statusText = ""
    @Published var now: Date
    @Published var calendars: [CalendarChoice] = []
    @Published private(set) var selectedCalendarIDs: Set<String>?
    @Published var reminderMinutes: Int {
        didSet {
            defaults.set(reminderMinutes, forKey: "reminderMinutes")
            if reminderMinutes == 0 { clearReminderHistory() }
        }
    }
    /// Off by default: notifications do not show call names while the Mac may be unattended.
    @Published var showTitlesInNotifications: Bool {
        didSet { defaults.set(showTitlesInNotifications, forKey: "notificationShowsTitle") }
    }
    let store = EKEventStore()
    private let defaults: UserDefaults
    private var timer: Timer?
    private(set) var lastFired: [String: Date] = [:]
    #if DEBUG
    var demoEvents: [MeetEvent]?
    #endif
    /// Called on every clock tick, after events load. The coordinator runs the pre-call check here.
    var onTick: ((Date) -> Void)?

    init(defaults: UserDefaults = .standard, startTimer: Bool = true, now: Date = Date()) {
        self.defaults = defaults
        self.now = now
        reminderMinutes = defaults.object(forKey: "reminderMinutes") as? Int ?? 0
        showTitlesInNotifications = defaults.bool(forKey: "notificationShowsTitle")
        selectedCalendarIDs = defaults.stringArray(forKey: "selectedCalendarIDs").map { Set($0) }
        defaults.removeObject(forKey: "lastFired")
        refreshAuthorization()
        loadEvents()
        if startTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    var access: CalendarAccess { authorized ? .granted : accessDenied ? .denied : .notDetermined }

    func refreshAuthorization() {
        #if DEBUG
        if demoMode { return }
        #endif
        applyAuthorization(EKEventStore.authorizationStatus(for: .event))
    }

    func applyAuthorization(_ status: EKAuthorizationStatus) {
        authorized = status == .fullAccess
        accessDenied = status == .denied || status == .restricted || status == .writeOnly
        if !authorized {
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

    func isCalendarSelected(_ id: String) -> Bool { selectedCalendarIDs?.contains(id) ?? true }

    func selectCalendar(_ id: String, enabled: Bool) {
        var ids = selectedCalendarIDs ?? Set(calendars.map(\.id))
        if enabled { ids.insert(id) } else { ids.remove(id) }
        selectedCalendarIDs = ids
        defaults.set(Array(ids).sorted(), forKey: "selectedCalendarIDs")
        loadEvents()
        clearReminderHistory()
    }

    func loadEvents() {
        #if DEBUG
        if demoMode { return }
        #endif
        guard authorized else { return }
        let available = store.calendars(for: .event)
        calendars = available.map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title) }
        let selected = available.filter { isCalendarSelected($0.calendarIdentifier) }
        guard !selected.isEmpty else { events = []; return }
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(172800)
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
        onTick?(date)
    }

    func clearReminderHistory() {
        lastFired = [:]
        LocalNotifier.center?.removeAllPendingNotificationRequests()
        LocalNotifier.center?.removeAllDeliveredNotifications()
    }

    func fireDueReminders() {
        guard reminderMinutes > 0, authorized else { return }
        lastFired = lastFired.filter { now.timeIntervalSince($0.value) < 172800 }
        for event in events where Countdown.shouldRemind(event: event, now: now, minutesBefore: reminderMinutes, lastFired: lastFired[event.id]) {
            lastFired[event.id] = now
            let text = CallNotice.reminder(event: event, now: now, showTitle: showTitlesInNotifications)
            LocalNotifier.post(id: event.id, title: text.title, body: text.body)
        }
    }

    func requestNotifications() {
        guard reminderMinutes > 0 else { return }
        LocalNotifier.requestPermission()
    }

    var nextEvent: MeetEvent? { DayTimeline.upcoming(events: events, now: now, limit: 1).first }
}

#if DEBUG
/// Debug builds only: one demo event for screenshots, without EventKit access. Release builds do not contain this code.
extension CalendarModel {
    static var demoArgument: String { "-demo-call" }
    var demoMode: Bool { demoEvents != nil }
    func useDemoEvent(now: Date = Date()) {
        let start = now.addingTimeInterval(4 * 60)
        demoEvents = [MeetEvent(id: "demo-design-review", title: "Design review", start: start,
                                end: start.addingTimeInterval(30 * 60), searchText: "https://example.com/j/123")]
        authorized = true; accessDenied = false
        events = demoEvents ?? []
    }
}
#endif
