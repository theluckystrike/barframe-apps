import Foundation
import Testing
@testable import PortSenseCore

private func fixture() throws -> [String: Any] {
    let url = try #require(Bundle.module.url(forResource: "power-and-usb", withExtension: "json", subdirectory: "Fixtures"))
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}
private func object(_ key: String) throws -> [String: Any] { try #require(fixture()[key] as? [String: Any]) }

@Test func adapterReadsFixtureWattsAndName() throws {
    let adapter = AdapterReading(properties: try object("adapter"))
    #expect(adapter.watts == 65)
    #expect(adapter.name == "USB-C power adapter")
    #expect(adapter.milliamps == 3250)
}
@Test func absentAdapterValuesStayUnknown() {
    let adapter = AdapterReading(properties: [:])
    #expect(adapter.watts == nil)
    #expect(adapter.name == nil)
}
@Test func invalidNumericFieldsAreRejected() {
    #expect(ReadValue.number(true) == nil)
    #expect(ReadValue.number("65") == nil)
    #expect(ReadValue.positive(Double.infinity) == nil)
    #expect(ReadValue.positive(-5) == nil)
    #expect(ReadValue.nonnegativeInt(1.5) == nil)
    #expect(ReadValue.nonnegativeInt(Double(Int.max)) == nil)
}
@Test func batteryReadsChargeHealthAndCycles() throws {
    let battery = BatteryReading(source: try object("battery"), registry: try object("batteryRegistry"))
    #expect(battery.chargePercent == 72)
    #expect(battery.health == "Good")
    #expect(battery.cycleCount == 243)
    #expect(battery.maximumCapacityPercent == 96)
    #expect(battery.chargingState == "Charging")
}
@Test func batteryCapacityUnitsDoNotMix() {
    let battery = BatteryReading(source: ["Current Capacity": 50, "Max Capacity": 100, "DesignCapacity": 5000])
    #expect(battery.chargePercent == 50)
    #expect(battery.maximumCapacityPercent == nil)
}
@Test func invalidBatteryChargeIsUnknown() {
    #expect(BatteryReading(source: ["Current Capacity": 50, "Max Capacity": 0]).chargePercent == nil)
    #expect(BatteryReading(source: ["Current Capacity": 101, "Max Capacity": 100]).chargePercent == nil)
    #expect(BatteryReading(source: ["Current Capacity": -1, "Max Capacity": 100]).chargePercent == nil)
}
@Test func batteryChargingStatesAreDistinct() {
    #expect(BatteryReading(source: ["Is Charged": true]).chargingState == "Fully charged")
    #expect(BatteryReading(source: [:]).chargingState == "Not charging")
}
@Test func usbFixtureReportsSpeedAllocationAndPort() throws {
    let device = USBDevice(id: 42, properties: try object("usb"), parent: try object("port"))
    #expect(device.product == "USB-C storage")
    #expect(device.vendor == "Fixture manufacturer")
    #expect(device.speedLabel == "10 Gb/s")
    #expect(device.availableMilliamps == 900)
    #expect(device.allocatedMilliamps == 896)
    #expect(device.location == "0x02000000")
    #expect(device.portType == "USB-C")
    #expect(!device.isBuiltIn)
}
@Test func builtInUSBIsClassified() throws {
    #expect(USBDevice(id: 1, properties: try object("builtIn")).isBuiltIn)
    #expect(USBDevice(id: 2, properties: ["Built-In": true]).isBuiltIn)
    #expect(!USBDevice(id: 3, properties: [:]).isBuiltIn)
}
@Test func missingUSBPropertiesDoNotInventPowerOrSpeed() throws {
    let device = USBDevice(id: 1, properties: try object("missing"))
    #expect(device.speedLabel == "Unavailable")
    #expect(device.allocatedMilliamps == nil)
    #expect(device.availableMilliamps == nil)
    #expect(device.vendor == "Vendor unavailable")
}
@Test func vendorIDFallbackIsStable() {
    #expect(USBDevice(id: 1, properties: ["idVendor": 4660]).vendor == "Vendor 0x1234")
    #expect(USBDevice(id: 1, properties: ["idVendor": 100000]).vendor == "Vendor unavailable")
}
@Test func xhciSpeedIDsMatchSDKTable() {
    #expect(USBSpeed.label(code: 1) == "12 Mb/s")
    #expect(USBSpeed.label(code: 2) == "1.5 Mb/s")
    #expect(USBSpeed.label(code: 3) == "480 Mb/s")
    #expect(USBSpeed.label(code: 4) == "5 Gb/s")
    #expect(USBSpeed.label(code: 5) == "10 Gb/s")
    #expect(USBSpeed.label(code: 6) == "20 Gb/s")
    #expect(USBSpeed.label(code: 0) == "Not connected")
    #expect(USBSpeed.label(code: 7) == "Unavailable")
    #expect(USBSpeed.label(code: 99) == "Unavailable")
}
@Test func chargerWarningUsesUserRating() {
    #expect(ChargerVerdict.evaluate(supply: .external, watts: 60, rating: 65) == .belowRating(actual: 60, rating: 65))
    #expect(ChargerVerdict.evaluate(supply: .external, watts: 65, rating: 65) == .sufficient)
    #expect(ChargerVerdict.evaluate(supply: .external, watts: 100, rating: 65) == .sufficient)
}
@Test func chargerWarningDoesNotTreatMissingAsZero() {
    #expect(ChargerVerdict.evaluate(supply: .external, watts: nil, rating: 65) == .unavailable)
    #expect(ChargerVerdict.evaluate(supply: .battery, watts: 65, rating: 100) == .disconnected)
    #expect(ChargerVerdict.evaluate(supply: .external, watts: 60, rating: 0) == .notConfigured)
    #expect(ChargerVerdict.evaluate(supply: .external, watts: .nan, rating: 65) == .unavailable)
}
@Test func historyRetainsExactlyLastSixtySamples() {
    var history = WattageHistory()
    for index in 0..<80 {
        history.append(WattageSample(date: Date(timeIntervalSince1970: Double(index)), watts: Double(index + 1), supply: .external))
    }
    #expect(history.samples.count == 60)
    #expect(history.samples.first?.watts == 21)
    #expect(history.samples.last?.watts == 80)
    #expect(history.range == 21...80)
}
@Test func historyRejectsOutOfOrderAndDuplicateReadings() {
    var history = WattageHistory()
    history.append(WattageSample(date: Date(timeIntervalSince1970: 20), watts: 65, supply: .external))
    history.append(WattageSample(date: Date(timeIntervalSince1970: 19), watts: 60, supply: .external))
    history.append(WattageSample(date: Date(timeIntervalSince1970: 20), watts: 60, supply: .external))
    #expect(history.samples.count == 1)
}
@Test func batterySamplesAreGapsInHistory() {
    var history = WattageHistory()
    history.append(WattageSample(date: Date(), watts: nil, supply: .battery))
    #expect(history.samples.count == 1)
    #expect(history.range == nil)
    #expect(WattageSample(date: Date(), watts: -1, supply: .external).watts == nil)
}
@Test func historyContainerStyleRoundtrip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("portsense-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var history = WattageHistory()
    history.append(WattageSample(date: Date(timeIntervalSince1970: 1000), watts: 65, supply: .external))
    history.append(WattageSample(date: Date(timeIntervalSince1970: 1015), watts: nil, supply: .battery))
    try history.write(to: url)
    #expect(try WattageHistory.read(from: url).samples == history.samples)
}
@Test func malformedHistoryThrows() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("portsense-bad-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not JSON".utf8).write(to: url)
    #expect(throws: (any Error).self) { try WattageHistory.read(from: url) }
}
@Test func powerSupplyAndMenuFormattingAreTruthful() throws {
    #expect(PowerSupply(systemValue: "AC Power") == .external)
    #expect(PowerSupply(systemValue: "Battery Power") == .battery)
    #expect(PowerSupply(systemValue: nil) == .unknown)
    let snapshot = PowerSnapshot(supply: .external, adapter: AdapterReading(properties: try object("adapter")), battery: nil, sourceCount: 0)
    #expect(ReadingFormat.menuValue(snapshot) == "65W")
    #expect(ReadingFormat.watts(nil) == "Unavailable")
    #expect(ReadingFormat.menuValue(nil).isEmpty)
}

@Test func chartDoesNotBridgeUnavailableReadings() {
    var history = WattageHistory()
    history.append(WattageSample(date: Date(timeIntervalSince1970: 0), watts: 65, supply: .external))
    history.append(WattageSample(date: Date(timeIntervalSince1970: 15), watts: nil, supply: .battery))
    history.append(WattageSample(date: Date(timeIntervalSince1970: 30), watts: 60, supply: .external))
    #expect(history.plotPoints.count == 2)
    #expect(history.plotPoints[0].segment != history.plotPoints[1].segment)
}
@Test func historyPreservesFractionalTimestamps() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("portsense-fraction-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var history = WattageHistory()
    history.append(WattageSample(date: Date(timeIntervalSince1970: 1000.125), watts: 65, supply: .external))
    history.append(WattageSample(date: Date(timeIntervalSince1970: 1000.250), watts: 60, supply: .external))
    try history.write(to: url)
    #expect(try WattageHistory.read(from: url).samples == history.samples)
}
