import Testing
import Foundation
import AppKit
@testable import HushKey
import HushKeyCore
import MASKit

/// Regression tests for the app layer: launch modes, links, product info,
/// smoke report contract, screenshot renderer output.
@MainActor
@Suite(.serialized) struct AppRegressionTests {
    @Test func appLinksResolveToBriefURLs() {
        #expect(AppLinks.privacyPath == "/mac-apps/hushkey/privacy/")
        #expect(AppLinks.supportPath == "/mac-apps/hushkey/support/")
    }

    @Test func appLinksRejectMalformedInfoPlistValues() {
        let result = AppLinks.resolvedURL("MASPrivacyPolicyURL", path: AppLinks.privacyPath, bundle: [:].asBundle())
        #expect(result?.isFileURL == true)
        #expect(result.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func productInfoBasics() {
        #expect(ProductInfo.name == "HushKey")
        #expect(!ProductInfo.version.isEmpty)
        #expect(ProductInfo.source.contains("hushkey"))
    }

    @Test func smokeReportAllPassContract() throws {
        let checks = [SmokeCheck(name: "one", pass: true, detail: "ok"), SmokeCheck(name: "two", pass: true, detail: "ok")]
        let report = SmokeReport(app: "HushKey", bundleID: "com.michaellip.hushkey", version: "1.0.0", checks: checks)
        #expect(report.pass)
        #expect(report.sandboxed == (ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil))
        #expect(report.bundleID == "com.michaellip.hushkey")
    }

    @Test func smokeReportFailsWhenAnyCheckFails() {
        let checks = [SmokeCheck(name: "one", pass: true, detail: "ok"), SmokeCheck(name: "bad", pass: false, detail: "no")]
        let report = SmokeReport(app: "HushKey", bundleID: "x", version: "1", checks: checks)
        #expect(!report.pass)
    }

    @Test func smokeReportEmptyChecksFails() {
        let report = SmokeReport(app: "HushKey", bundleID: "x", version: "1", checks: [])
        #expect(!report.pass)
    }

    @Test func smokeReportWriteRoundTrip() throws {
        let report = SmokeReport(app: "HushKey", bundleID: "com.michaellip.hushkey", version: "1", checks: [SmokeCheck(name: "w", pass: true, detail: "d")])
        let url = try report.write()
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(SmokeReport.self, from: data)
        #expect(decoded.pass && decoded.checks.first?.name == "w")
    }

    @Test func screenshotRendererProducesThreePngs() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hk-shots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ScreenshotRenderer.render(to: dir)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
        #expect(files.count == 3)
        for f in files {
            guard let data = try? Data(contentsOf: f),
                  let rep = NSBitmapImageRep(data: data) else {
                #expect(Bool(false), "not a bitmap: \(f)")
                continue
            }
            #expect(rep.pixelsWide == 2880 && rep.pixelsHigh == 1800)
        }
    }

    @Test func sampleModeTogglePersistsToDefaults() {
        let model = AppModel(storeDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hk-model-\(UUID().uuidString)", isDirectory: true))
        let before = model.sampleMode
        model.setSampleMode(!before)
        #expect(model.sampleMode == !before)
        #expect(UserDefaults.standard.bool(forKey: "sampleMode") == !before)
        model.setSampleMode(before)
    }

    @Test func modelOutcomeLabelledForSampleToggle() {
        let model = AppModel(storeDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hk-model-\(UUID().uuidString)", isDirectory: true))
        model.setSampleMode(true)
        #expect(model.lastOutcome.contains("Sample"))
        model.setSampleMode(false)
        #expect(model.lastOutcome.contains("off"))
    }
}

private extension Dictionary where Key == String, Value == Any {
    func asBundle() -> Bundle {
        let dict: [String: Any] = ["MASPrivacyPolicyURL": "https://example.com/PLACEHOLDER/{path}"]
        let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hk-bundle-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? data.write(to: url.appendingPathComponent("Info.plist"))
        return Bundle(url: url) ?? Bundle.main
    }
}
