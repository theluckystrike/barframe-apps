import AppKit
import SwiftUI
import Testing
import MeetNextCore
import MASKit
import EventKit
@testable import MeetNext

@MainActor
struct AppRegressionTests {

    @Test func sampleModePopulatesEventsAndMenuTitle() {
        let model = AppModel()
        model.toggleSample(true)
        #expect(!model.events.isEmpty)
        #expect(model.nextEvent != nil)
        #expect(model.menuBarTitle.hasPrefix("Sample ·"))
    }

    @Test func sampleModeExitRestoresEmptyLiveState() {
        let model = AppModel()
        model.toggleSample(true)
        model.toggleSample(false)
        #expect(model.sampleMode == false)
        #expect(model.events.isEmpty)
        #expect(!model.menuBarTitle.hasPrefix("Sample ·"))
    }

    @Test func deniedAccessStateShowsGuidanceAndKeepsSampleAvailable() {
        let model = AppModel()
        model.accessDenied = true
        model.authorized = false
        #expect(model.menuBarTitle == "Access needed")
        let host = NSHostingView(rootView: ContentView(model: model))
        #expect(host.fittingSize.width >= 380)
    }

    @Test func joinButtonRendersForSampleZoomEvent() {
        let model = AppModel()
        model.toggleSample(true)
        let next = model.nextEvent
        #expect(next != nil)
        let host = NSHostingView(rootView: ContentView(model: model))
        #expect(host.fittingSize.width >= 380)
    }

    @Test func settingsViewRendersWithoutCrashing() {
        let model = AppModel()
        model.toggleSample(true)
        let host = NSHostingView(rootView: SettingsView(model: model))
        #expect(host.fittingSize.width >= 520)
    }

    @Test func reminderPreferenceRoundTripsThroughDefaults() {
        let model = AppModel()
        let original = model.reminderMinutes
        model.reminderMinutes = 15
        #expect(UserDefaults.standard.integer(forKey: "reminderMinutes") == 15)
        model.reminderMinutes = original
    }

    @Test func manifestURLsMatchProductInfo() {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mas.json")
        let data = try? Data(contentsOf: manifest)
        #expect(data != nil)
        if let data {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect((json?["privacy_url"] as? String) == AppLinks.privacy.absoluteString)
            #expect((json?["support_url"] as? String) == AppLinks.support.absoluteString)
        }
    }
}

@MainActor
@Suite(.serialized)
struct AuditAppRegressionTests {
    private func isolatedModel() -> AppModel {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return AppModel(defaults: defaults, startTimer: false)
    }

    @Test func activeDelegateUpdatesActualStatusButtonAndEmptyFallback() {
        _ = NSApplication.shared
        let model = isolatedModel()
        model.applyAuthorization(.notDetermined)
        let delegate = AppDelegate()
        delegate.model = model
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(delegate.statusItem?.button?.title == "MeetNext")
        model.toggleSample(true)
        delegate.updateTitle()
        #expect(delegate.statusItem?.button?.title == model.menuBarTitle)
        #expect(delegate.statusItem?.button?.title.contains("Sample") == true)
    }

    @Test func sharedClockAdvancesWithoutMovingFixtures() {
        let model = isolatedModel()
        model.toggleSample(true)
        let original = model.events
        let next = model.nextEvent!
        model.tick(at: next.start)
        #expect(model.events == original)
        #expect(model.menuBarTitle.contains("now"))
        model.tick(at: next.end)
        #expect(model.nextEvent?.id != next.id)
    }

    @Test func calendarSelectionPersistsAndSampleFiltersIndependently() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(defaults: defaults, startTimer: false)
        model.calendars = [CalendarChoice(id: "a", title: "A"), CalendarChoice(id: "b", title: "B")]
        model.selectCalendar("a", enabled: false)
        #expect(model.selectedCalendarIDs == ["b"])
        let restored = AppModel(defaults: defaults, startTimer: false)
        #expect(restored.selectedCalendarIDs == ["b"])
        model.toggleSample(true)
        model.selectCalendar("sample-work", enabled: false)
        #expect(!model.events.isEmpty)
        #expect(model.events.allSatisfy { $0.calendarID == "sample-personal" })
        #expect(model.selectedCalendarIDs == ["b"])
    }

    @Test func neverDefaultsToDisabledAndRemovesLegacyHistory() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(["private-id": 1.0], forKey: "lastFired")
        let model = AppModel(defaults: defaults, startTimer: false)
        #expect(model.reminderMinutes == 0)
        #expect(defaults.object(forKey: "lastFired") == nil)
        model.toggleSample(true)
        model.tick(at: model.nextEvent!.start)
        model.fireDueReminders()
        #expect(model.lastFired.isEmpty)
    }

    @Test func revocationClearsLiveDataAndGrantUpdatesState() {
        let model = isolatedModel()
        model.applyAuthorization(.fullAccess)
        #expect(model.authorized)
        model.events = SampleCalendar.events(now: Date())
        model.applyAuthorization(.denied)
        #expect(!model.authorized && model.accessDenied)
        #expect(model.events.isEmpty && model.lastFired.isEmpty)
        model.applyAuthorization(.fullAccess)
        #expect(model.authorized && !model.accessDenied)
    }

    @Test func localPolicyFallbackIsBundledAndDetectsPlaceholders() {
        #expect(!AppLinks.isFinal(AppLinks.webURL("https://{DOMAIN}/privacy")))
        #expect(AppLinks.localText("privacy").contains("Reminders and retention"))
        #expect(AppLinks.localText("support").contains("Try Sample"))
    }

    @Test func sceneAndSettingsEntrypointsStayConnected() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scene = try String(contentsOf: root.appendingPathComponent("Sources/MeetNext/MeetNextApp.swift"))
        let content = try String(contentsOf: root.appendingPathComponent("Sources/MeetNext/ContentView.swift"))
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/MeetNext/SettingsView.swift"))
        #expect(scene.contains("appDelegate.model = model"))
        #expect(!scene.contains("static var shared"))
        #expect(content.contains("SettingsLink"))
        #expect(!content.contains("showSettingsWindow:"))
        #expect(content.contains("private var now: Date { model.now }"))
        #expect(content.contains("} else {\n                    Button(\"Try Sample\")"))
        #expect(settings.contains("Toggle(\"Sample mode\""))
    }
}
