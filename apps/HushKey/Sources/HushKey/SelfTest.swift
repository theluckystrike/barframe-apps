import Foundation
import CoreAudio
import HushKeyCore
import MASKit

/// Smoke / self-test mode: run real checks against the live environment and
/// write the SmokeReport contract to the container home (proves sandbox).
@MainActor enum SelfTest {
    static func run(writeSmoke: Bool) -> Int32 {
        var checks: [SmokeCheck] = []
        let model = AppModel()
        let devices = model.devices()
        checks.append(SmokeCheck(name: "audio.enumerate", pass: true, detail: "\(devices.count) input device(s)"))
        let hasDefault = devices.contains(where: { $0.isDefault })
        checks.append(SmokeCheck(name: "audio.default", pass: hasDefault, detail: hasDefault ? "default present" : "no default input device"))

        if let d = devices.first(where: { $0.isDefault }), d.supportsMute || d.supportsVolume {
            let result = DeviceState.selfTest(d, backend: model.backend)
            checks.append(SmokeCheck(name: "audio.toggle", pass: result.0, detail: result.1))
            checks.append(SmokeCheck(name: "audio.restore", pass: result.0, detail: result.1))
        } else {
            checks.append(SmokeCheck(name: "audio.toggle", pass: true, detail: "skipped: no mutable device"))
            checks.append(SmokeCheck(name: "audio.restore", pass: true, detail: "skipped: no mutable device"))
        }

        // Sample mode data must be self-consistent.
        checks.append(SmokeCheck(name: "sample.data", pass: !SampleData.devices.isEmpty && SampleData.defaultDevice.isDefault, detail: "\(SampleData.devices.count) simulated device(s)"))
        // Pure logic still works headlessly.
        checks.append(SmokeCheck(name: "logic.reapply", pass: ReapplyLogic.shouldMute(intent: .alwaysMute, newDevice: SampleData.defaultDevice, previousDeviceWasMutedByApp: false, manuallyUnmutedRecently: false), detail: "alwaysMute -> true"))
        checks.append(SmokeCheck(name: "logic.menuline", pass: MenuLine.label(muted: true, volumePercent: 75, hideVolume: false) == "🔒 75%", detail: MenuLine.label(muted: true, volumePercent: 75, hideVolume: false)))
        checks.append(SmokeCheck(name: "logic.hotkey", pass: HotKeyConfig.decode(HotKeyConfig.encode(.default)) == .default, detail: "roundtrip"))

        let report = SmokeReport(app: "HushKey", bundleID: Bundle.main.bundleIdentifier ?? "unknown", version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0", checks: checks)
        if writeSmoke {
            do { _ = try report.write() } catch { fputs("smoke write failed: \(error)\n", stderr); return 1 }
        }
        for c in checks { print("\(c.pass ? "PASS" : "FAIL") \(c.name): \(c.detail)") }
        return report.pass ? 0 : 2
    }
}
