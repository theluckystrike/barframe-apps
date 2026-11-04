import Testing
import Foundation
@testable import StarglassCore

/// Regression tests asserting the App Review contract strings survive refactors.
@Suite("App Regression")
struct AppRegressionTests {
    @Test("sample mode city and outlooks exist")
    func sampleData() {
        #expect(SampleData.location.name == "Sample Springs")
        let outlooks = NightScorer.score(
            forecast: SampleData.forecast(),
            latitude: SampleData.location.latitude,
            longitude: SampleData.location.longitude,
            now: SampleData.epoch
        )
        #expect(!outlooks.isEmpty)
        #expect(outlooks.count >= 7)
    }

    @Test("engine returns no nights for empty hourly arrays")
    func emptyForecast() {
        let outlooks = NightScorer.score(
            forecast: Forecast(latitude: 0, longitude: 0, timezone: "UTC", hours: [], fetchedAt: SampleData.epoch),
            latitude: 0,
            longitude: 0,
            now: SampleData.epoch
        )
        #expect(outlooks.isEmpty)
    }
}

@testable import Starglass
import UserNotifications
@MainActor struct AuditRegressions {
    func model() -> AppModel {
        AppModel(start: false, store: LocationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }
    @Test func liveAndCachedTimeline() {
        let m = model()
        for offline in [false, true] {
            m.apply(forecast: SampleData.forecast(now: Date()), offline: offline)
            #expect(m.activeForecast != nil)
            #expect(!ContentView(model: m).tonightTimelineHours(m.outlooks.first!).isEmpty)
        }
    }
    @Test func sampleEpochAndExit() {
        let m = model(); m.loading = true; m.enterSample()
        #expect(!m.loading)
        #expect(m.outlooks.count == 8 && m.displayLocation?.name == "Sample Springs")
        #expect(m.lastUpdated == SampleData.epoch)
        m.exitSample()
        #expect(m.outlooks.isEmpty && m.tonightScore == nil && m.activeForecast == nil && m.lastUpdated == nil)
    }
    @Test func refreshAndExpiry() async {
        let m = model(); m.apply(forecast: SampleData.forecast(), offline: true)
        await m.refresh()
        #expect(m.tonightScore == nil && m.activeForecast == nil)
        m.apply(forecast: SampleData.forecast(now: Date(timeIntervalSince1970: 0)), offline: true)
        #expect(m.stale && m.outlooks.isEmpty && m.errorMessage != nil)
    }
    @Test func notifications() async {
        let m = model(); #expect(!m.notifyEnabled)
        var cancelled = false
        m.cancelNotifications = { cancelled = true }
        m.authorizeNotifications = { true }
        await m.setNotifications(true)
        #expect(m.store.defaults.bool(forKey: "notifyEnabled"))
        let night = NightOutlook(nightStart: Date().addingTimeInterval(10000), nightEnd: Date().addingTimeInterval(40000), score: 90, averageCloud: 0, averageVisibility: 20000, averageHumidity: 40, averageWind: 0, moonIllumination: 0, moonUpFraction: 0, darkHours: 8, hasAstronomicalDark: true, sampleHours: 8)
        m.scheduleNotification = { _ in throw StarglassError.network("test failure") }
        await m.maybeNotify([night]); #expect(m.notifiedNightStarts.isEmpty)
        m.scheduleNotification = { _ in }
        await m.maybeNotify([night]); #expect(m.notifiedNightStarts.contains(night.nightStart))
        await m.setNotifications(false)
        #expect(cancelled && m.notifiedNightStarts.isEmpty && !m.store.defaults.bool(forKey: "notifyEnabled"))
    }
    @Test func cityTimeAndPolarWindow() {
        let m = model(); m.location = SavedLocation(name: "Tokyo", latitude: 35, longitude: 139, timezone: "Asia/Tokyo")
        #expect(ContentView(model: m).hourLabel(SampleData.epoch) == "09")
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let date = c.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let w = NightScorer.nightWindow(for: date, latitude: 78, longitude: 15, calendar: c)
        #expect(c.component(.hour, from: w.start) == 21 && c.component(.hour, from: w.end) == 5)
    }
    @Test func bundledLinksWhenUnconfigured() {
        #expect(AppLinks.privacyURL?.isFileURL == true)
        #expect(AppLinks.supportURL?.isFileURL == true)
        #expect(AppLinks.resolvedURL("MASPrivacyPolicyURL", path: "/invalid") == nil)
    }
    @Test func clearLocalData() throws {
        let m = model()
        try FileManager.default.createDirectory(at: m.store.cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: m.store.cacheDirectory) }
        m.store.saveForecast(SampleData.forecast())
        #expect(m.store.loadForecast() != nil)
        m.store.location = SampleData.location; m.enterSample(); m.cancelNotifications = {}
        m.clearSavedData()
        #expect(m.store.location == nil && m.store.loadForecast() == nil && m.activeForecast == nil && !m.sampleMode)
    }
}
struct TimeRegressions {
    @Test func cityParsing() {
        #expect(ISO8601LocalOrPlain(timezone: "Europe/Warsaw").parse("2026-10-14T21:00") == ISO8601DateFormatter().date(from: "2026-10-14T19:00:00Z"))
    }
    @Test func hemispheresAndDST() {
        for (zone, lat, lon) in [("Asia/Tokyo",35.7,139.7),("America/Los_Angeles",34.0,-118.2),("Europe/Warsaw",50.0,20.0)] {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!
            for (month,day) in [(10,14),(10,25),(11,1),(3,8),(3,29)] {
                let date = c.date(from: DateComponents(year: 2026, month: month, day: day))!
                let w = NightScorer.nightWindow(for: date, latitude: lat, longitude: lon, calendar: c)
                #expect(w.end > w.start && c.isDate(w.start, inSameDayAs: date))
                #expect(w.end.timeIntervalSince(w.start) < 86400)
            }
        }
    }
}

struct PresentationRegressions {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path)) }
    @Test func refreshLifecycleWiring() throws {
        let s = try source("Sources/Starglass/AppModel.swift")
        #expect(s.contains("Timer.scheduledTimer") && s.contains("NSWorkspace.didWakeNotification") && s.contains(".NSCalendarDayChanged"))
        #expect(try source("Sources/Starglass/ContentView.swift").contains("Button(\"Refresh\")"))
    }
    @Test func fullSizeScreenshotAndAccurateClaims() throws {
        let s = try source("Sources/Starglass/ScreenshotRenderer.swift")
        #expect(s.contains("size: host.fittingSize"))
        #expect(!s.contains("Image(nsImage: capture).resizable()"))
        let listing = try source("store/listing.json")
        #expect(!listing.contains("Moon phase and illumination for every night") && !listing.contains("planets"))
        let notes = try source("store/review_notes.md")
        #expect(!notes.contains("Click any night") && notes.contains("Try Sample"))
    }
    @Test func policyDisclosesSearchAndRetention() throws {
        for path in ["store/privacy.md", "Sources/Starglass/Resources/privacy.html"] {
            let s = try source(path)
            #expect(s.contains("search sends") && s.contains("IP address") && s.contains("90 days") && s.contains("Clear saved city and forecast"))
        }
    }
}
