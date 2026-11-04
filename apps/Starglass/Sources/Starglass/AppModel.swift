import Foundation
import AppKit
import SwiftUI
import StarglassCore
import UserNotifications

/// Drives the menu bar: fetch, cache, score, notify, sample.
@MainActor
public final class AppModel: ObservableObject {
    @Published public var tonightScore: Int?
    @Published public var outlooks: [NightOutlook] = []
    @Published public var location: SavedLocation?
    @Published public var loading = false
    @Published public var errorMessage: String?
    @Published public var sampleMode = false
    @Published public var lastUpdated: Date?
    @Published public var offline = false
    @Published public var searchResults: [Place] = []
    @Published public var searching = false
    @Published public var notifiedNightStarts: Set<Date> = []

    public let client: OpenMeteoClient
    public var store: LocationStore
    @Published public var activeForecast: Forecast?
    @Published public var notifyEnabled: Bool
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    public var displayLocation: SavedLocation? { sampleMode ? SampleData.location : location }
    public var displayTimeZone: TimeZone { calendar(for: displayLocation).timeZone }
    public var stale: Bool { !sampleMode && lastUpdated.map { Date().timeIntervalSince($0) > 3600 } == true }
    public var authorizeNotifications: () async throws -> Bool = {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    public var cancelNotifications: () -> Void = { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
    public var scheduleNotification: (UNNotificationRequest) async throws -> Void = { try await UNUserNotificationCenter.current().add($0) }


    public init(start: Bool = true, client: OpenMeteoClient = OpenMeteoClient(), store: LocationStore = LocationStore()) {
        self.client = client
        self.store = store
        location = store.location
        notifyEnabled = store.defaults.bool(forKey: "notifyEnabled")
        if start {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            })
            Task { await refresh() }
        }
    }

    public var menuBarTitle: String {
        guard let score = tonightScore else { return "" }
        return String(score)
    }

    public func refresh() async {
        if sampleMode { return }
        guard let loc = location, !loc.isEmpty else {
            clearForecast()
            errorMessage = StarglassError.noLocation.localizedDescription
            return
        }
        generation += 1
        let requestGeneration = generation
        loading = true
        errorMessage = nil
        defer { if generation == requestGeneration { loading = false } }
        do {
            let forecast = try await client.forecast(latitude: loc.latitude, longitude: loc.longitude)
            guard !sampleMode, generation == requestGeneration else { return }
            apply(forecast: forecast, offline: false)
        } catch {
            guard !sampleMode, generation == requestGeneration else { return }
            // Offline fallback: score the cached forecast.
            if let cached = store.loadForecast() {
                apply(forecast: cached, offline: true)
            } else {
                clearForecast()
                errorMessage = (error as? StarglassError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    public func apply(forecast: Forecast, offline: Bool) {
        activeForecast = forecast
        self.offline = offline
        lastUpdated = forecast.fetchedAt
        let calendar = calendar(for: location)
        let scored = NightScorer.score(forecast: forecast, latitude: location?.latitude ?? forecast.latitude,
                                       longitude: location?.longitude ?? forecast.longitude, calendar: calendar)
        outlooks = scored
        tonightScore = scored.first?.score
        if scored.isEmpty { errorMessage = "Forecast expired or unavailable. Refresh to try again." }
        if !offline, !sampleMode { store.saveForecast(forecast) }
        if notifyEnabled, !sampleMode {
            Task { await maybeNotify(scored) }
        }
    }

    public func enterSample() {
        generation += 1
        loading = false
        sampleMode = true
        let forecast = SampleData.forecast()
        activeForecast = forecast
        let calendar = calendar(for: SampleData.location)
        let scored = NightScorer.score(forecast: forecast, latitude: SampleData.location.latitude,
                                       longitude: SampleData.location.longitude, now: SampleData.epoch, calendar: calendar)
        outlooks = scored
        tonightScore = scored.first?.score
        lastUpdated = SampleData.epoch
        errorMessage = nil
        offline = false
    }

    public func exitSample() {
        generation += 1
        clearForecast()
        sampleMode = false
        Task { await refresh() }
    }

    public func search(_ query: String) async {
        guard query.count >= 2 else { searchResults = []; return }
        searching = true
        defer { searching = false }
        do {
            searchResults = try await client.geocode(query)
        } catch {
            errorMessage = (error as? StarglassError)?.errorDescription ?? error.localizedDescription
            searchResults = []
        }
    }

    public func choose(_ place: Place) {
        let saved = SavedLocation(name: place.summary, latitude: place.latitude,
                                  longitude: place.longitude, timezone: place.timezone)
        generation += 1
        sampleMode = false
        clearForecast()
        location = saved
        store.location = saved
        searchResults = []
        store.clearCache()
        Task { await refresh() }
    }

    public func clearForecast() {
        loading = false
        activeForecast = nil
        outlooks = []
        tonightScore = nil
        lastUpdated = nil
        offline = false
        errorMessage = nil
    }

    public func clearSavedData() {
        generation += 1
        sampleMode = false
        store.location = nil
        store.clearCache()
        location = nil
        clearForecast()
        notifyEnabled = false
        store.defaults.set(false, forKey: "notifyEnabled")
        cancelNotifications()
        notifiedNightStarts = []
    }

    public func setNotifications(_ enabled: Bool) async {
        notifyEnabled = enabled
        store.defaults.set(enabled, forKey: "notifyEnabled")
        if !enabled {
            cancelNotifications()
            notifiedNightStarts = []
            return
        }
        do {
            let allowed = try await authorizeNotifications()
            guard notifyEnabled else { return }
            if allowed { await maybeNotify(outlooks) }
            else { errorMessage = "Notifications are not permitted. Enable them in System Settings." }
        } catch { errorMessage = "Notification permission failed: \(error.localizedDescription)" }
    }

    func maybeNotify(_ outlooks: [NightOutlook]) async {
        guard notifyEnabled, !sampleMode, let best = NightScorer.bestNight(outlooks.filter { $0.nightStart > Date() }),
              NightScorer.isWorthNotifying(best),
              !notifiedNightStarts.contains(best.nightStart) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Clear dark night ahead"
        content.body = "\(best.label) stargazing (\(best.score)/100) coming up. Open Starglass for the timeline."
        content.sound = .default
        let triggerDate = max(Date().addingTimeInterval(60), best.nightStart.addingTimeInterval(-2 * 3600))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "starglass-\(best.nightStart.timeIntervalSince1970)",
                                            content: content, trigger: trigger)
        do {
            try await scheduleNotification(request)
            if notifyEnabled { notifiedNightStarts.insert(best.nightStart) }
            else { cancelNotifications() }
        } catch { errorMessage = "Could not schedule notification: \(error.localizedDescription)" }
    }

    func calendar(for location: SavedLocation?) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let id = location?.timezone, let tz = TimeZone(identifier: id) {
            calendar.timeZone = tz
        }
        return calendar
    }
}
