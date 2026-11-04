import Foundation
import AppKit
import SwiftUI
import Testing
import Vision
@testable import PortSenseCore
@testable import PortSenseApp

private let auditRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func auditP1BothDestinationsFallBackAndActivateWhenConfigured() {
    for page in PortPage.allCases {
        for raw in [nil, "https://{DOMAIN}" + page.path, "https://%7BDOMAIN%7D" + page.path,
                    "http://example.invalid" + page.path, "https://example.invalid/wrong/"] {
            #expect(PortLinks.destination(page, raw: raw) == .local(page))
        }
        let url = URL(string: "https://example.invalid" + page.path)!
        #expect(PortLinks.destination(page, raw: url.absoluteString) == .web(url))
        let hosted = URL(string: "https://theluckystrike.github.io/mac-apps" + page.path)!
        #expect(PortLinks.destination(page, raw: hosted.absoluteString) == .web(hosted))
        let text = PortLinks.localText(page)
        #expect(text.count > 300)
        #expect(!text.contains("{BRAND}"))
        #expect(!text.contains("{DOMAIN}"))
        #expect(text.contains("Michael Lip"))
    }
    #expect(!PortLinks.copyright().contains("{"))
}

@Test func auditP1PackagedPagesResolveInsideAppResources() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PortSense-resource-test-\(UUID().uuidString).app")
    defer { try? FileManager.default.removeItem(at: folder) }
    let contents = folder.appendingPathComponent("Contents")
    let resources = contents.appendingPathComponent("Resources/PortSense_PortSenseApp.bundle/Content")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let info = ["CFBundleIdentifier": "test.portsense.resource", "CFBundlePackageType": "APPL", "CFBundleExecutable": "PortSense"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    for page in PortPage.allCases {
        let source = auditRoot.appendingPathComponent("Sources/PortSenseApp/Content/" + page.rawValue + ".md")
        try FileManager.default.copyItem(at: source, to: resources.appendingPathComponent(page.rawValue + ".md"))
    }
    let bundle = try #require(Bundle(url: folder))
    for page in PortPage.allCases {
        let text = PortLinks.localText(page, bundle: bundle)
        #expect(text.count > 300)
        #expect(text.contains("Michael Lip"))
        #expect(!text.contains("could not be loaded"))
    }
}

@Suite(.serialized) @MainActor struct AuditRuntimeRegressionTests {
    @Test func auditP1PrivacyAndSupportWindowsOpenWithoutWebsite() throws {
        _ = NSApplication.shared
        let model = AppState(usePreferences: false)
        for page in PortPage.allCases {
            model.openLocalPage(page)
            let window = try #require(NSApp.windows.first { $0.title == page.title && $0.isVisible })
            #expect(window.contentView != nil)
            window.close()
        }
        model.stop()
    }
    @Test func auditP2EveryScreenshotUsesNormalViewportAndWidth() throws {
        _ = NSApplication.shared
        for tab in InspectorTab.allCases {
            let model = AppState(usePreferences: false)
            model.setSample(true); model.selectedTab = tab
            let panel = PopoverView(model: model, workspaceHeight: 900)
            let image = try PortScreenshotComposer.capturePanel { panel }
            #expect(image.width == 720)
            #expect(Double(image.height) / 2 <= PopoverLayout.maximumHeight(visibleHeight: 900))
            #expect(PortScreenshotComposer.panelScale(width: Double(image.width) / 2, height: Double(image.height) / 2) == 1)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let expected = tab == .power ? "CHARGER CAPACITY" : tab == .connections ? "Sample USB-C storage" : "Charger capacity over time"
            #expect(text.contains(expected), "\(tab) body must be visible; OCR: \(text)")
            model.stop()
        }
        let viewSource = try String(contentsOf: auditRoot.appendingPathComponent("Sources/PortSenseApp/PopoverView.swift"))
        #expect(!viewSource.contains("displayTab"))
        #expect(!viewSource.contains("LazyVGrid"))
    }
}

@Test func auditP1IconUsesOnlyOriginalPaths() throws {
    let source = try String(contentsOf: auditRoot.appendingPathComponent("scripts/make_icon.swift"))
    #expect(!source.contains("systemSymbolName"))
    #expect(!source.contains("SymbolConfiguration"))
    #expect(source.contains("NSBezierPath"))
    #expect(source.contains("curve(to:"))
}

private struct AuditFailure: Error {}
@Test func auditP3CadenceAllowsManualAndFailedEntries() throws {
    var history = WattageHistory()
    let start = Date(timeIntervalSince1970: 1000)
    history.record(.success(SampleReadings.power(date: start)), date: start, periodic: true)
    history.record(.failure(AuditFailure()), date: start.addingTimeInterval(1), periodic: false)
    history.record(.success(SampleReadings.power(date: start.addingTimeInterval(15))), date: start.addingTimeInterval(15), periodic: false)
    #expect(history.samples.count == 3)
    #expect(history.samples[1].date.timeIntervalSince(history.samples[0].date) == 1)
    let listing = try JSONSerialization.jsonObject(with: Data(contentsOf: auditRoot.appendingPathComponent("store/listing.json"))) as! [String: Any]
    let description = try #require(listing["description"] as? String)
    #expect(description.contains("15-second cadence"))
    #expect(description.contains("manual reads and failed attempts can add entries"))
    #expect(!description.contains("collected every 15 seconds"))
    let view = try String(contentsOf: auditRoot.appendingPathComponent("Sources/PortSenseApp/PopoverView.swift"))
    #expect(view.contains("15-second polling cadence"))
    #expect(!view.contains("one every 15 seconds"))
    let selectedData = try Data(contentsOf: auditRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("store-drafts/SELECTED.json"))
    let all = try JSONSerialization.jsonObject(with: selectedData) as! [String: [String: Any]]
    let selected = all["charger-inspector"]!
    for field in ["subtitle", "keywords", "promotional_text"] {
        #expect(listing[field] as? String == (selected[field] as? String)?.replacingOccurrences(of: "{APP}", with: "PortSense"))
    }
}
