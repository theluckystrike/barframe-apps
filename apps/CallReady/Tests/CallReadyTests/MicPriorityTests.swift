import AppKit
import SwiftUI
import Foundation
import Testing
@testable import CallReady
import CallCore

@Suite @MainActor struct MicPriorityTests {
    @Test func prioritiesPersistAndRespectSafety() {
        let session = FixtureSession(); defer { session.close() }
        session.model.setPriorities(["fixture-12", "missing", "fixture-3", "fixture-2"])
        #expect(session.model.preferred?.id == 3)
        #expect(SettingsStore(defaults: session.defaults).load().priorityUIDs == ["fixture-12", "missing", "fixture-3", "fixture-2"])
        session.model.movePriority("fixture-2")
        #expect(session.model.preferred?.id == 2)
        session.hardware.inventory.removeAll { $0.id == 2 }
        session.model.refresh(enforce: false)
        #expect(session.model.preferred?.id == 3)
    }
    @Test func priorityLidAndVirtualFilters() {
        let hardware = TwelveDeviceHardware()
        let virtual = AudioDevice(id: 90, uid: "virtual", name: "Virtual", transport: .virtual, inputChannels: 1, outputChannels: 0)
        #expect(GuardDecision.preferredDevice(in: hardware.inventory + [virtual], priorities: ["virtual", "fixture-1", "fixture-3"], lidClosed: true)?.id == 3)
    }
    @Test func confirmedHistoryBoundedPersistedAndClearable() {
        var time = Date(timeIntervalSince1970: 10000)
        let session = FixtureSession(); defer { session.close() }
        let model = GuardModel(hardware: session.hardware, defaults: session.defaults, now: { time }, scheduleEvents: false)
        model.clearHistory()
        for _ in 0..<25 { time = time.addingTimeInterval(60); session.hardware.input = 12; model.refresh(enforce: true) }
        #expect(model.settings.history.count == 20)
        #expect(model.settings.history.allSatisfy { $0.reason == "Bluetooth input replaced" })
        #expect(SettingsStore(defaults: session.defaults).load().history.count == 20)
        model.clearHistory()
        #expect(SettingsStore(defaults: session.defaults).load().history.isEmpty)
        #expect(model.settings.interventions == 0)
    }
    @Test func unconfirmedSwitchHasNoHistory() {
        var machine = GuardMachine()
        let hardware = TwelveDeviceHardware()
        let effects = machine.send(.devicesChanged(GuardSnapshot(devices: hardware.inventory, input: 12, lidClosed: false), enforce: true), at: Date())
        #expect(!effects.isEmpty)
        #expect(machine.settings.history.isEmpty)
    }
    @Test func fixtureIsIsolatedAndExercisesBluetooth() {
        let original = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        let session = FixtureSession()
        #expect(session.hardware.input == 1)
        #expect(session.model.settings.history.count == 1)
        session.model.allowBluetoothForOneHour(); session.simulateTakeover()
        #expect(session.hardware.input == 12)
        session.model.resumeGuard()
        #expect(session.hardware.input == 1)
        #expect(session.model.devices.count == 12)
        session.close()
        #expect(session.defaults.persistentDomain(forName: session.suite) == nil)
        #expect(original == UserDefaults.standard.dictionaryRepresentation() as NSDictionary)
    }
    @Test func workerUsesBackgroundThreadAndCancelsQueuedWork() async throws {
        let worker = AudioWorker()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        worker.submit({ entered.signal(); block(release); return 1 }) { _ in Issue.record("Cancelled result delivered") }
        block(entered)
        worker.submit({ Issue.record("Cancelled operation executed"); return 2 }) { _ in Issue.record("Cancelled result delivered") }
        worker.cancel(); release.signal()
        let background = await withCheckedContinuation { continuation in
            worker.submit({ !Thread.isMainThread }) { result in continuation.resume(returning: (try? result.get()) == true) }
        }
        #expect(background)
    }
    @Test func policyLinksAreFixedHTTPSPagesForThisApp() {
        for url in [AppLinks.privacy, AppLinks.support] {
            #expect(url.scheme == "https")
            #expect(url.host == "barframe.com")
            #expect(url.path.hasPrefix("/apps/callready/"))
        }
        #expect(AppLinks.privacy.absoluteString.hasSuffix("/privacy/"))
        #expect(AppLinks.support.absoluteString.hasSuffix("/support/"))
        #expect(AppLinks.credits().string.contains("Privacy Policy"))
        #expect(AppLinks.credits().string.contains("Support"))
    }
    @Test func infoPlistHasNoTemplateKeys() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["MASPrivacyPolicyURL"] == nil && plist["MASSupportURL"] == nil)
        #expect(plist["CFBundleIdentifier"] as? String == "com.michaellip.micanchor")
        #expect(plist["CFBundleExecutable"] as? String == "CallReady")
        #expect(plist["CFBundleShortVersionString"] as? String == "1.0.1")
        #expect(Int(plist["CFBundleVersion"] as? String ?? "") ?? 0 >= 3)
        let usage = try #require(plist["NSCalendarsFullAccessUsageDescription"] as? String)
        #expect(usage.contains("CallReady") && usage.contains("Mac"))
        #expect(plist["NSCalendarsUsageDescription"] as? String == usage)
        #expect(plist["NSMicrophoneUsageDescription"] == nil)
    }
    @Test func entitlementsAreSandboxAndCalendarsOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/CallReady.entitlements"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Bool])
        #expect(plist == ["com.apple.security.app-sandbox": true, "com.apple.security.personal-information.calendars": true])
    }
    @Test func settingsWindowRendersAllThreeSectionsAtShippingSize() throws {
        let fixture = FixtureApp(); defer { fixture.close() }
        fixture.microphone.setPriorities(["fixture-1", "fixture-2", "fixture-3"])
        let size = CGSize(width: CallSettingsView.width, height: CallSettingsView.height)
        let image = try captureNativeView(CallSettingsView(app: fixture.app, calendar: fixture.calendar, microphone: fixture.microphone, mute: fixture.mute), size: size)
        #expect(image.size == size)
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        // A blank or failed native-control render must not silently ship.
        let data = try #require(bitmap.tiffRepresentation)
        #expect(data.count > 10000)
        var colors = Set<String>()
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 16) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 16) {
                if let color = bitmap.colorAt(x: x, y: y) { colors.insert(color.description) }
            }
        }
        #expect(colors.count > 20)
    }
}

/// Waits outside the async context of a test.
private func block(_ semaphore: DispatchSemaphore) { semaphore.wait() }
