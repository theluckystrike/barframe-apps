import Foundation
import AppKit
import SwiftUI
import Vision
import Testing
@testable import PortSenseCore
@testable import PortSenseApp

@Test func separateInputRatingAndNegotiatedValues() {
    let sample = SampleReadings.power()
    #expect(sample.inputWatts == 40.8)
    #expect(sample.adapter?.watts == 65)
    #expect(sample.adapter?.volts == 20)
    #expect(sample.adapter?.milliamps == 3250)
    #expect(ReadingFormat.menuValue(sample) == "65W")
    #expect(PowerTelemetry.inputWatts(["SystemPowerIn": 40800]) == 40.8)
    #expect(PowerTelemetry.inputWatts(["SystemVoltageIn": 20000, "SystemCurrentIn": 2000]) == 40)
}
@Test func zeroInputIsValidMissingInputIsUnavailable() {
    #expect(PowerTelemetry.inputWatts(["SystemPowerIn": 0]) == 0)
    #expect(PowerTelemetry.inputWatts([:]) == nil)
    #expect(DetailFormat.watts(0) == "0 W")
    for value in [Double.nan, .infinity, -1, 1_000_001] {
        #expect(PowerTelemetry.inputWatts(["SystemPowerIn": value]) == nil)
    }
    #expect(PowerTelemetry.inputWatts(["SystemPowerIn": true]) == nil)
}
@Test func signedBatteryPowerPreservesDischargeAndUnsignedEncoding() {
    #expect(BatteryReading(source: [:], registry: ["Voltage": 12000, "InstantAmperage": -1500]).signedWatts == -18)
    #expect(ReadValue.signedCurrent(NSNumber(value: UInt64(bitPattern: -1500))) == -1500)
    #expect(ReadValue.signedCurrent(true) == nil)
    #expect(ReadValue.signedCurrent(1.5) == nil)
    #expect(ReadValue.signedCurrent(Double.infinity) == nil)
    #expect(ReadValue.signedCurrent(100001) == nil)
    #expect(PowerTelemetry.watts(millivolts: 12000, milliamps: 0) == 0)
    #expect(PowerTelemetry.watts(millivolts: 0, milliamps: 1) == nil)
}
@Test func batteryTemperatureAndTimeAreOptionalAndBounded() {
    let sample = SampleReadings.power().battery!
    #expect(abs(sample.temperatureCelsius! - 30.05) < 0.001)
    #expect(sample.remainingMinutes == 42)
    #expect(sample.fullChargeCapacity == 3950)
    #expect(sample.designCapacity == 5000)
    #expect(BatteryReading(source: ["Time to Empty": 65535], registry: ["Temperature": true]).remainingMinutes == nil)
    #expect(BatteryReading(source: [:], registry: ["Temperature": Double.infinity]).temperatureCelsius == nil)
    #expect(BatteryReading(source: [:], registry: ["Temperature": 9999]).temperatureCelsius == nil)
    #expect(DetailFormat.minutes(0) == "Less than 1 min")
    #expect(DetailFormat.minutes(75) == "1 h 15 min")
    #expect(DetailFormat.minutes(nil) == "Unavailable")
}
@Test func loserRawRatioClampAndIntegerTruncationDoNotReturn() {
    #expect(BatteryReading(source: [:], registry: ["AppleRawMaxCapacity": 5250, "DesignCapacity": 5000]).maximumCapacityPercent == 105)
    #expect(ReadValue.nonnegativeInt(3.9) == nil)
    #expect(ReadValue.nonnegativeInt(true) == nil)
    #expect(AdapterReading(properties: ["Current": 3250.5]).milliamps == nil)
}
@Test func unknownSourceNeverBecomesBattery() {
    let unknown = PowerSnapshot(supply: .unknown, adapter: nil, battery: BatteryReading(source: ["Current Capacity": 50, "Max Capacity": 100]), sourceCount: 1)
    #expect(ReadingFormat.menuValue(unknown).isEmpty)
    #expect(ReadingFormat.statusAccessibilityLabel(unknown).contains("Power source unavailable"))
    #expect(!ReadingFormat.statusAccessibilityLabel(unknown).contains("On battery"))
}
@Test func advisoryNeedsPositiveUSB3EvidenceAndExcludesHubs() {
    func device(_ values: [String: Any]) -> USBDevice { USBDevice(id: 1, properties: values) }
    #expect(device(["USBSpeed": 3, "bcdUSB": 0x0300, "bDeviceClass": 0]).checkCable)
    for version in [0x0200, 0x0210] {
        #expect(!device(["USBSpeed": 3, "bcdUSB": version, "bDeviceClass": 8]).checkCable)
    }
    #expect(!device(["USBSpeed": 3, "bDeviceClass": 8]).checkCable)
    #expect(!device(["USBSpeed": 3, "bcdUSB": 0x0300, "bDeviceClass": 9]).checkCable)
    #expect(!device(["USBSpeed": 3, "bcdUSB": 0x0300]).checkCable)
    #expect(!USBDevice(id: 1, properties: ["USBSpeed": 3, "bcdUSB": 0x0300, "bDeviceClass": 0], interfaceClasses: [9]).checkCable)
    #expect(!USBDevice(id: 1, properties: ["USBSpeed": 3, "bcdUSB": 0x0300, "bDeviceClass": 0], interfaceClasses: nil).checkCable)
    #expect(!device(["USBSpeed": 5, "bcdUSB": 0x0300, "bDeviceClass": 8]).checkCable)
    for key in ["Built-In", "built-in", "non-removable"] {
        #expect(!device(["USBSpeed": 3, "bcdUSB": 0x0300, "bDeviceClass": 0, key: 1]).checkCable)
    }
}
@Test func populatedNeutralSampleListCoversAdvisoryAndUnknowns() {
    let devices = SampleReadings.connections.usb
    #expect(devices.count == 11)
    #expect(devices.filter { !$0.isBuiltIn }.count == 10)
    #expect(devices.allSatisfy { $0.product.hasPrefix("Sample") })
    #expect(devices.contains { $0.checkCable })
    #expect(!devices.first { $0.product == "Sample external hub" }!.checkCable)
}
private actor RefreshLatch {
    var reads = 0
    var continuation: CheckedContinuation<Void, Never>?
    func read() async -> SystemReadings {
        reads += 1
        if reads == 1 { await withCheckedContinuation { continuation = $0 } }
        return SystemReadings(power: .success(SampleReadings.power()), connections: .success(SampleReadings.connections))
    }
    func release() { continuation?.resume(); continuation = nil }
}
@Test @MainActor func eventDuringReadSchedulesFollowupAndSampleRejectsStaleResult() async {
    let latch = RefreshLatch()
    let state = AppState(usePreferences: false, reader: { await latch.read() })
    let first = state.refresh()
    while await latch.reads < 1 { await Task.yield() }
    state.hardwareChanged(.usb)
    state.hardwareChanged(.battery)
    await latch.release()
    await first?.value
    while await latch.reads < 2 { await Task.yield() }
    while state.refreshing { await Task.yield() }
    #expect(await latch.reads == 2)
    state.stop()
    let secondLatch = RefreshLatch()
    let sampleState = AppState(usePreferences: false, reader: { await secondLatch.read() })
    let stale = sampleState.refresh()
    while await secondLatch.reads < 1 { await Task.yield() }
    sampleState.setSample(true)
    sampleState.hardwareChanged(.power)
    await secondLatch.release()
    await stale?.value
    #expect(sampleState.isSample)
    #expect(sampleState.history.samples.count == 20)
    #expect(await secondLatch.reads == 1)
    sampleState.stop()
}
@Test func historyAxisIncludesLastTimeAndHasThreeTicks() {
    let history = SampleReadings.history(endingAt: Date(timeIntervalSince1970: 10000))
    let ticks = HistoryAxis.ticks(history)
    #expect(ticks.count == 3)
    #expect(ticks.first == history.samples.first?.date)
    #expect(ticks.last == history.samples.last?.date)
}

@Suite(.serialized) @MainActor struct PortPresentationTests {
    private func scroll(in view: NSView) -> NSScrollView? {
        if let view = view as? NSScrollView { return view }
        return view.subviews.lazy.compactMap { scroll(in: $0) }.first
    }
    @Test func allBodiesScrollAndFooterStaysWithinSmallScreen() throws {
        _ = NSApplication.shared
        for height in [600.0, 680.0, 720.0] {
            for tab in InspectorTab.allCases {
                let model = AppState(usePreferences: false)
                model.setSample(true); model.selectedTab = tab
                var frames: [String: CGRect] = [:]
                let host = NSHostingView(rootView: PopoverView(model: model, workspaceHeight: height, measureLayout: { frames = $0 }))
                let size = host.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
                defer { window.close(); model.stop() }
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                host.layoutSubtreeIfNeeded()
                #expect(host.bounds.height <= PopoverLayout.maximumHeight(visibleHeight: height))
                for name in ["header", "tabs", "detail", "links", "footer"] {
                    let frame = try #require(frames[name])
                    #expect(host.bounds.contains(frame), "\(height) \(tab) \(name): \(frame) / \(host.bounds)")
                }
                let body = try #require(scroll(in: host))
                let document = try #require(body.documentView)
                if tab != .history {
                    #expect(document.bounds.height > body.contentView.bounds.height)
                    let before = body.contentView.bounds.minY
                    body.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.maxY - body.contentView.bounds.height))
                    body.reflectScrolledClipView(body.contentView)
                    #expect(body.contentView.bounds.minY > before + 1)
                }
                let viewport = body.convert(body.bounds, to: host)
                for name in ["header", "tabs", "links", "footer"] {
                    #expect(!viewport.intersects(try #require(frames[name])))
                }
            }
        }
    }
    @Test func renderedHistoryIncludesCompleteFinalAxisLabel() throws {
        let model = AppState(usePreferences: false); model.setSample(true)
        let ending = Date(timeIntervalSince1970: 1_700_000_000)
        model.history = SampleReadings.history(endingAt: ending)
        model.selectedTab = .history
        let image = try PortScreenshotComposer.capturePanel { PopoverView(model: model) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let evidence = root.appendingPathComponent("build/history-axis-test.png")
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: evidence)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let expected = ending.formatted(HistoryAxis.format)
        let observations = request.results ?? []
        #expect(observations.contains { ($0.topCandidates(1).first?.string ?? "").contains(expected) }, "Expected final time \(expected); OCR: \(observations.compactMap { $0.topCandidates(1).first?.string })")
        #expect(observations.allSatisfy { $0.boundingBox.minX >= 0 && $0.boundingBox.maxX <= 1 })
        model.stop()
    }
    @Test func screenshotPanelsFitCanvasAndHeadlinesHaveFourToSevenWords() throws {
        for (width, height) in [(360.0, 650.0), (360.0, 720.0), (360.0, 500.0)] {
            let scale = PortScreenshotComposer.panelScale(width: width, height: height)
            #expect(scale == 1)
            #expect(width * scale <= 680)
            #expect(height * scale <= 740)
            #expect(520 + 60 + width * scale <= 1320)
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let entry = try String(contentsOf: root.appendingPathComponent("Sources/PortSenseApp/PortSenseApp.swift"))
        let expression = try NSRegularExpression(pattern: "\\bheadline: \"([^\"]+)\"")
        let matches = expression.matches(in: entry, range: NSRange(entry.startIndex..<entry.endIndex, in: entry))
        #expect(matches.count == 3)
        for match in matches {
            let range = try #require(Range(match.range(at: 1), in: entry))
            #expect((4...7).contains(entry[range].split(separator: " ").count))
        }
    }
    @Test func privacyRemainsReadableWithProvisionalHostedURLs() throws {
        #expect(PrivacyPolicyView.policy.count >= 300)
        #expect(PrivacyPolicyView.policy.contains("does not collect personal data"))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for page in ["privacy", "support"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("store/site/portsense/\(page)/index.html").path))
        }
        let model = AppState(usePreferences: false); model.openPrivacy()
        let window = try #require(NSApp.windows.first { $0.title == "PortSense Privacy Policy" })
        #expect(window.isVisible)
        #expect(window.contentView != nil)
        window.close(); model.stop()
    }
}
