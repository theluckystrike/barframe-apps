import AppKit
import SwiftUI
import Foundation
import Testing
@testable import Fidelity
import FidelityCore

@Suite @MainActor struct MergeTests {
    @Test func prioritiesPersistAndRespectSafety() {
        let session = SampleSession(); defer { session.close() }
        session.model.setPriorities(["sample-12", "missing", "sample-3", "sample-2"])
        #expect(session.model.preferred?.id == 3)
        #expect(SettingsStore(defaults: session.defaults).load().priorityUIDs == ["sample-12", "missing", "sample-3", "sample-2"])
        session.model.movePriority("sample-2")
        #expect(session.model.preferred?.id == 2)
        session.hardware.inventory.removeAll { $0.id == 2 }
        session.model.refresh(enforce: false)
        #expect(session.model.preferred?.id == 3)
    }
    @Test func priorityLidAndVirtualFilters() {
        let hardware = SampleHardware()
        let virtual = AudioDevice(id: 90, uid: "virtual", name: "Virtual", transport: .virtual, inputChannels: 1, outputChannels: 0)
        #expect(GuardDecision.preferredDevice(in: hardware.inventory + [virtual], priorities: ["virtual", "sample-1", "sample-3"], lidClosed: true)?.id == 3)
    }
    @Test func confirmedHistoryBoundedPersistedAndClearable() {
        var time = Date(timeIntervalSince1970: 10000)
        let session = SampleSession(); defer { session.close() }
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
        let hardware = SampleHardware()
        let effects = machine.send(.devicesChanged(GuardSnapshot(devices: hardware.inventory, input: 12, lidClosed: false), enforce: true), at: Date())
        #expect(!effects.isEmpty)
        #expect(machine.settings.history.isEmpty)
    }
    @Test func sampleIsIsolatedAndExercisesBluetooth() {
        let original = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        let session = SampleSession()
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
        worker.submit({ entered.signal(); release.wait(); return 1 }) { _ in Issue.record("Cancelled result delivered") }
        entered.wait()
        worker.submit({ Issue.record("Cancelled operation executed"); return 2 }) { _ in Issue.record("Cancelled result delivered") }
        worker.cancel(); release.signal()
        let background = await withCheckedContinuation { continuation in
            worker.submit({ !Thread.isMainThread }) { result in continuation.resume(returning: (try? result.get()) == true) }
        }
        #expect(background)
    }
    @Test func policyLinksUseBundledConfiguration() {
        // This remains valid after owner configuration switches to live websites.
        let value = Bundle.main.object(forInfoDictionaryKey: "MASPrivacyPolicyURL") as? String
        #expect(AppLinks.privacyDestination == AppLinks.destination(value))
        #expect(!AppLinks.copyright.contains("{"))
        #expect(AppLinks.credits().string.contains("Settings") || AppLinks.privacyURL != nil)
    }
    @Test(arguments: [nil, "https://{DOMAIN}/micanchor/privacy/", "https://%7BDOMAIN%7D/privacy", "bad URL", "", "http://example.com/support/", "file:///tmp/policy"] as [String?])
    func invalidWebsiteConfigurationUsesLocalText(value: String?) {
        #expect(AppLinks.destination(value) == .local)
        #expect(!AppLinks.privacyText.contains("{DOMAIN}"))
        #expect(!AppLinks.supportText.contains("{BRAND}"))
        #expect(AppLinks.supportText.contains("Sample mode"))
    }
    @Test func configuredWebsiteKeepsSameDestinationReady() throws {
        let url = try #require(URL(string: "https://example.com/micanchor/privacy/"))
        #expect(AppLinks.destination(url.absoluteString) == .web(url))
    }
    @Test func screenshotCaptureIncludesNativeSettingsAtShippingSize() throws {
        let session = SampleSession(); defer { session.close() }
        session.model.setPriorities(["sample-1", "sample-2", "sample-3"])
        let size = CGSize(width: GuardSettingsView.width, height: GuardSettingsView.height)
        let image = try captureNativeView(GuardSettingsView(model: session.model, sampleSession: true), size: size)
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
