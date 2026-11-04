import AppKit
import SwiftUI
import MASKit
import StarglassCore

enum SelfTest {
    @MainActor
    static func run(writeSmoke: Bool) -> Int32 {
        var checks: [SmokeCheck] = []
        func check(_ name: String, _ condition: Bool) {
            checks.append(SmokeCheck(name: name, pass: condition, detail: condition ? "" : "failed"))
        }
        // Location store roundtrip with an isolated defaults suite.
        let suite = UserDefaults(suiteName: "selftest.starglass")!
        suite.removePersistentDomain(forName: "selftest.starglass")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("starglass-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = LocationStore(defaults: suite, cacheDirectory: tempDir)
        check("no location initially", store.location == nil)
        var mutableStore = store
        let saved = SavedLocation(name: "Kraków, Lesser Poland, Poland", latitude: 50.06, longitude: 19.94, timezone: "Europe/Warsaw")
        mutableStore.location = saved
        check("location roundtrip", mutableStore.location == saved)
        let forecast = SampleData.forecast()
        mutableStore.saveForecast(forecast)
        check("forecast cache roundtrip", mutableStore.loadForecast() == forecast)
        mutableStore.clearCache()
        check("cache cleared", mutableStore.loadForecast() == nil)

        // Scoring runs on the sample forecast.
        let outlooks = NightScorer.score(forecast: forecast, latitude: 38.7, longitude: -109.6,
                                         now: SampleData.epoch, calendar: Calendar(identifier: .gregorian))
        check("eight outlooks", outlooks.count == 8)
        check("scores in range", outlooks.allSatisfy { (0...100).contains($0.score) })

        // Sample mode populates the model without network.
        let model = AppModel(start: false, store: store)
        model.enterSample()
        check("sample mode score present", model.tonightScore != nil)
        check("sample mode flag", model.sampleMode)
        model.exitSample()
        check("sample exit restores live path", !model.sampleMode)

        // URL routes resolve to the per-app overrides.
        check("privacy route", AppLinks.privacyPath == "/starglass/privacy/")
        check("support route", AppLinks.supportPath == "/starglass/support/")
        check("privacy html bundled", AppLinks.privacyURL != nil)
        check("support html bundled", AppLinks.supportURL != nil)

        // Sandbox facts measured at runtime.
        // Resolve the real ~/Desktop even when sandboxed (urls(for:) returns the container path).
        let desktop = FileManager.default.homeDirectoryForCurrentUser.path
            .components(separatedBy: "/Library/Containers/").first
            .map { URL(fileURLWithPath: $0).appendingPathComponent("Desktop") }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let desktopReadable = (try? FileManager.default.contentsOfDirectory(at: desktop, includingPropertiesForKeys: nil)) != nil
        // Only meaningful inside App Sandbox: unguarded home reads must be denied there.
        // Outside the sandbox (dev binary) the read succeeds by design — pass with detail.
        check("desktop denied in sandbox", SmokeReport.isSandboxed ? !desktopReadable : true)

        try? FileManager.default.removeItem(at: tempDir)
        let failed = checks.contains { !$0.pass }
        if writeSmoke {
            let report = SmokeReport(app: "Starglass",
                                     bundleID: Bundle.main.bundleIdentifier ?? "unknown",
                                     version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
                                     checks: checks)
            fputs("\(report.pass)\n", stderr)
            _ = try? report.write()
        }
        for line in checks { print("\(line.pass ? "PASS" : "FAIL") \(line.name)") }
        return failed ? 1 : 0
    }

    static func verifyGrants() -> Int32 {
        // Sandbox: only the network client entitlement is expected; no user grants to verify.
        print("Starglass requests no user-selected grants. Network client only.")
        return 0
    }
}
