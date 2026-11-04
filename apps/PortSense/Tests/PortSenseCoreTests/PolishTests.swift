import Foundation
import AppKit
import Testing
import MASKit
@testable import PortSenseCore
@testable import PortSenseApp

private let appRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private func metadata(_ relative: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: appRoot.appendingPathComponent(relative))) as? [String: Any])
}

@Test func P01PrivacyLinksExistInBothRequiredSurfaces() throws {
    let settings = try String(contentsOf: appRoot.appendingPathComponent("Sources/PortSenseApp/SettingsView.swift"))
    let popover = try String(contentsOf: appRoot.appendingPathComponent("Sources/PortSenseApp/PopoverView.swift"))
    #expect(settings.contains("PortLinksView(model: model)"))
    #expect(popover.contains("PortLinksView(model: model)"))
    let manifest = try metadata("mas.json")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PortSense-links-\(UUID().uuidString).bundle")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect((manifest["privacy_url"] as? String)?.hasPrefix("https://barframe.com/apps/portsense/") == true)
    let plist: [String: Any] = ["CFBundleIdentifier": "test.portsense.links", "MASPrivacyPolicyURL": "https://example.invalid/portsense/privacy/", "MASSupportURL": "https://example.invalid/portsense/support/"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: folder.appendingPathComponent("Info.plist"))
    let bundle = try #require(Bundle(url: folder))
    #expect(MASLinks.privacyPolicy(bundle)?.absoluteString == plist["MASPrivacyPolicyURL"] as? String)
    #expect(MASLinks.support(bundle)?.absoluteString == plist["MASSupportURL"] as? String)
}

@Test func P02SubmissionURLsAgreeWithManifest() throws {
    let manifest = try metadata("mas.json"), listing = try metadata("store/listing.json")
    let base = "https://barframe.com/apps/portsense/"
    #expect(manifest["privacy_url"] as? String == base + "privacy/")
    #expect(listing["privacy_policy"] as? String == manifest["privacy_url"] as? String)
    #expect(manifest["support_url"] as? String == base + "support/")
    #expect(listing["support"] as? String == manifest["support_url"] as? String)
    let notes = try #require(listing["review_notes"] as? String)
    #expect(notes.contains("Try Sample"))
    #expect(!notes.contains("Tests/"))
}

@Test func P03StatusAccessibilityNamesAppAndPowerState() {
    for supply in [PowerSupply.external, .battery, .ups, .unknown] {
        let snapshot = PowerSnapshot(supply: supply, adapter: nil, battery: nil, sourceCount: 0)
        let label = ReadingFormat.statusAccessibilityLabel(snapshot)
        #expect(label.contains("PortSense"))
        #expect(label.contains(supply.label))
    }
    #expect(ReadingFormat.statusAccessibilityLabel(nil).contains("checking power source"))
    #expect(ReadingFormat.statusAccessibilityLabel(nil, error: "failed").contains("power reading unavailable"))
    #expect(ReadingFormat.statusAccessibilityLabel(SampleReadings.power(), sample: true).contains("Sample"))
}

private actor ReadCounter {
    var count = 0
    func read() -> SystemReadings {
        count += 1
        return SystemReadings(power: .success(SampleReadings.power()), connections: .success(SampleReadings.connections))
    }
}

@Test @MainActor func P04InitializationDoesNotReadHardware() async {
    let counter = ReadCounter()
    let model = AppState(reader: { await counter.read() })
    #expect(await counter.count == 0)
    #expect(model.power == nil)
    #expect(model.connections.usb.isEmpty)
    #expect(!model.refreshing)
    await model.refresh()?.value
    #expect(await counter.count == 1)
    #expect(model.power?.adapter?.watts == 65)
    model.stop()
}

@Test @MainActor func P04BothHardwareReadersRunOffMainThread() async throws {
    let readings = await SystemReadings.load(powerReader: {
        #expect(!Thread.isMainThread)
        return SampleReadings.power()
    }, connectionReader: {
        #expect(!Thread.isMainThread)
        return SampleReadings.connections
    })
    #expect(try readings.power.get().adapter?.watts == 65)
    #expect(try readings.connections.get().usb.count == 11)
}

private struct FailedPowerRead: LocalizedError {
    var errorDescription: String? { "Fixture power read failed." }
}

@Test @MainActor func P05TimedFailureRecordsGapAndVisibleFailure() async {
    let model = AppState(reader: {
        SystemReadings(power: .failure(FailedPowerRead()), connections: .success(SampleReadings.connections), date: Date(timeIntervalSince1970: 15))
    })
    model.power = SampleReadings.power(date: Date(timeIntervalSince1970: 0))
    model.history.append(WattageSample(snapshot: model.power!))
    await model.refresh(periodic: true)?.value
    #expect(model.power == nil)
    #expect(model.powerError == "Fixture power read failed.")
    #expect(model.history.samples.count == 2)
    #expect(model.history.samples.last?.watts == nil)
    #expect(model.history.failedReadCount == 1)
    #expect(model.history.latestFailure?.date == Date(timeIntervalSince1970: 15))
    model.history.record(.success(SampleReadings.power(date: Date(timeIntervalSince1970: 30))), date: Date(timeIntervalSince1970: 30), periodic: true)
    #expect(model.history.plotPoints[0].segment != model.history.plotPoints[1].segment)
    model.stop()
}

@Test func P05FailureSurvivesHistoryRoundTrip() throws {
    var history = WattageHistory()
    history.record(.failure(FailedPowerRead()), date: Date(timeIntervalSince1970: 15), periodic: true)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("PortSense-failure-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try history.write(to: url)
    #expect(try WattageHistory.read(from: url).latestFailure?.failure == "Fixture power read failed.")
}

@Test @MainActor func SampleModeHasEveryFeatureAndDoesNotReadHardware() async {
    let counter = ReadCounter()
    let model = AppState(reader: { await counter.read() })
    model.setSample(true)
    #expect(model.isSample)
    #expect(model.power?.battery?.maximumCapacityPercent == 79)
    #expect(model.visibleUSB.count == (model.showBuiltIn ? 11 : 10))
    #expect(model.connections.thunderbolt.count == 1)
    #expect(model.history.samples.count == 20)
    #expect(model.history.failedReadCount == 1)
    #expect(Set(model.history.plotPoints.map(\.segment)).count == 2)
    model.start()
    await model.refresh()?.value
    #expect(await counter.count == 0)
    model.setSample(false)
    #expect(!model.isSample)
    await model.refresh()?.value
    #expect(model.history.samples.count == 1)
    #expect(model.history.failedReadCount == 0)
    model.stop()
}

@Test func RawBatteryCapacityIsExplicitAndUsesRegistryRatio() {
    #expect(ReadingFormat.rawCapacityLabel == "Full charge capacity vs design (raw)")
    let battery = BatteryReading(source: ["Current Capacity": 84, "Max Capacity": 100], registry: ["NominalChargeCapacity": 3950, "DesignCapacity": 5000])
    #expect(battery.maximumCapacityPercent == 79)
    #expect(battery.chargePercent == 84)
}

@Test func RawBatteryCapacityDoesNotClampAboveDesignToOneHundred() {
    let battery = BatteryReading(source: [:], registry: ["NominalChargeCapacity": 5250, "DesignCapacity": 5000])
    #expect(battery.maximumCapacityPercent == 105)
    #expect(BatteryReading(source: [:], registry: ["NominalChargeCapacity": 9999, "DesignCapacity": 5000]).maximumCapacityPercent == nil)
}

@Test func StoreFirstSentenceStatesFunctionAndHasNoReviewFileDependency() throws {
    let listing = try metadata("store/listing.json")
    let description = try #require(listing["description"] as? String)
    #expect(description.hasPrefix("PortSense reports charger capacity, battery details, and USB connections in your menu bar."))
    #expect(description.count <= 4000)
    #expect(description.contains("vs design (raw)"))
}

@Test @MainActor func SampleChargerRatingIsIndependentAndZeroDisablesWarning() {
    let model = AppState(usePreferences: false)
    let liveRating = model.ratedWatts
    model.setSample(true)
    #expect(model.effectiveRating == 100)
    #expect(model.verdict == .belowRating(actual: 65, rating: 100))
    model.setChargerRating(65)
    #expect(model.verdict == .sufficient)
    model.setChargerRating(0)
    #expect(model.verdict == .notConfigured)
    #expect(model.ratedWatts == liveRating)
    model.setChargerRating(.nan)
    #expect(model.effectiveRating == 0)
    model.setChargerRating(999)
    #expect(model.effectiveRating == 500)
    model.stop()
}

@Test @MainActor func EscapeIsHandledBySettingsWindowWithoutSwiftUIFocus() throws {
    _ = NSApplication.shared
    let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.orderFront(nil)
    #expect(window.isVisible)
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    #expect(window.performKeyEquivalent(with: escape))
    #expect(!window.isVisible)
    window.orderFront(nil)
    window.cancelOperation(nil)
    #expect(!window.isVisible)
}
