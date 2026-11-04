import Testing
import Foundation
import AppKit
import Carbon.HIToolbox
import Combine
import HushKeyCore
@testable import HushKey

@MainActor final class TrackedBackend: DeviceBackend {
    let fixture = SampleDevices()
    var calls = 0
    var failWrites = false
    func devices() -> [InputDevice] { calls += 1; return fixture.devices() }
    func mute(_ d: InputDevice) -> Bool? { calls += 1; return fixture.mute(d) }
    func volume(_ d: InputDevice) -> Float? { calls += 1; return fixture.volume(d) }
    func setMute(_ d: InputDevice, _ value: Bool) -> Bool { calls += 1; return !failWrites && fixture.setMute(d, value) }
    func setVolume(_ d: InputDevice, _ value: Float) -> Bool { calls += 1; return !failWrites && fixture.setVolume(d, value) }
    func select(_ id: String) -> Bool { calls += 1; return fixture.select(id) }
}

@Suite(.serialized) @MainActor struct AuditRegressionTests {
    func model(live: DeviceBackend? = nil, sample: Bool = true) -> AppModel {
        let defaults = UserDefaults(suiteName: "audit-\(UUID().uuidString)")!
        defaults.set(sample, forKey: "sampleMode")
        let model = AppModel(storeDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString), live: live ?? SampleDevices(), defaults: defaults)
        model.start(); return model
    }
    @Test func shortcutUsesCarbonConstants() {
        #expect(HotKeyConfig.default.keyCode == UInt32(kVK_ANSI_M))
        #expect(HotKeyConfig.keyName(UInt32(kVK_ANSI_N)) == "N")
        #expect(HotKeyConfig.default.carbonModifiers == UInt32(shiftKey | optionKey))
    }
    @Test func repeatedPressReleaseCycles() {
        let center = HotKeyCenter.shared
        center.unregister()
        var downs = 0, ups = 0
        center.onFire = { downs += 1 }; center.onRelease = { ups += 1 }
        #expect(HotKeyCenter.eventKinds == [UInt32(kEventHotKeyPressed), UInt32(kEventHotKeyReleased)])
        for _ in 0..<3 {
            center.handle(kind: UInt32(kEventHotKeyPressed)); center.handle(kind: UInt32(kEventHotKeyPressed))
            center.handle(kind: UInt32(kEventHotKeyReleased))
        }
        #expect(downs == 3 && ups == 3)
        center.onFire = nil; center.onRelease = nil
    }
    @Test func sampleActionsNeverAccessLiveBackend() {
        let spy = TrackedBackend(), m = model(live: TrackedBackend())
        let isolated = model(live: spy)
        isolated.toggleDefaultMute(); isolated.muteDefault(); isolated.setVolume(0.42)
        isolated.selectDefaultDevice("sample-3")
        isolated.setPushToTalk(true); isolated.beginPushToTalk(); isolated.endPushToTalk()
        _ = isolated.runSelfTestChecks(); isolated.defaultDeviceChanged()
        #expect(spy.calls == 0)
        #expect(m.sampleMode)
    }
    @Test func volumeOnlyRepeatedMuteRestoresNonzeroVolume() {
        let m = model(); m.setIntent(.off); m.selectDefaultDevice("sample-3"); m.setVolume(0.73)
        m.muteDefault(); m.muteDefault()
        #expect(m.isDefaultMuted())
        m.toggleDefaultMute()
        #expect(m.currentVolume() == 0.73)
        #expect(!m.isDefaultMuted())
    }
    @Test func selfTestRestoresVolumeOnlyAndHardwareMute() {
        let b = SampleDevices()
        for d in b.devices() {
            _ = b.setVolume(d, 0.37)
            let before = b.mute(d)
            let result = DeviceState.selfTest(d, backend: b)
            #expect(result.0)
            #expect(b.volume(d) == 0.37)
            #expect(b.mute(d) == before)
        }
    }
    @Test func selfTestRestoresInitiallyZeroVolume() {
        let b = SampleDevices(), d = SampleData.devices[2]
        _ = b.setVolume(d, 0)
        #expect(DeviceState.selfTest(d, backend: b).0)
        #expect(b.volume(d) == 0)
    }
    @Test func disablePTTCleansUpBeforeFlagChanges() {
        let m = model(); m.setPushToTalk(true); m.beginPushToTalk()
        #expect(m.pttActive && !m.isDefaultMuted())
        m.setPushToTalk(false)
        #expect(!m.pttActive && m.isDefaultMuted())
    }
    @Test func deviceSwitchWhileHeldMutesBoth() {
        let m = model(); m.setIntent(.off); m.setPushToTalk(true)
        let old = m.currentDefault()!
        m.beginPushToTalk(); m.selectDefaultDevice("sample-2")
        #expect(!m.pttActive && m.isDefaultMuted())
        #expect(m.sample.mute(old) == true)
    }
    @Test func firstStayMutedTransferUsesInitialDevice() {
        let m = model(); m.setIntent(.stayMutedOnly)
        m.muteDefault(); m.selectDefaultDevice("sample-3")
        #expect(m.isDefaultMuted())
    }
    @Test func memoryUsesStableUIDAcrossObjectIDs() {
        let b = TrackedBackend()
        b.fixture.list = [InputDevice(id: "12", name: "Volume mic", supportsMute: false, supportsVolume: true, isDefault: true, uid: "stable-uid")]
        b.fixture.volumes["12"] = 0.81
        let m = model(live: b, sample: false)
        m.muteDefault()
        b.fixture.list = [InputDevice(id: "87", name: "Volume mic", supportsMute: false, supportsVolume: true, isDefault: true, uid: "stable-uid")]
        b.fixture.volumes["87"] = 0
        m.toggleDefaultMute()
        #expect(b.fixture.volumes["87"] == 0.81)
    }
    @Test func failedRestorePreservesMemory() {
        let b = TrackedBackend(); _ = b.select("sample-3")
        let m = model(live: b, sample: false)
        m.setVolume(0.69); m.muteDefault(); b.failWrites = true; m.toggleDefaultMute()
        #expect(m.lastOutcome.contains("failed"))
        b.failWrites = false; m.toggleDefaultMute(); #expect(m.currentVolume() == 0.69)
    }
    @Test func registrationAndUnsupportedErrorsAreVisible() {
        let m = model(); m.registerShortcut = { _, _ in false }; m.applyHotKey(.default)
        #expect(m.lastOutcome.contains("Choose a different key"))
        m.sample.list = [InputDevice(id: "unsupported", name: "Unsupported", supportsMute: false, supportsVolume: false, isDefault: true)]
        m.toggleDefaultMute(); #expect(m.lastOutcome.contains("does not support"))
    }
    @Test func settingsChangesNotifyPresentationAndBadgeRespectsPreference() {
        let m = model(); m.badgePanel = MicBadgePanel()
        var updates = 0
        let observation = m.objectWillChange.sink { updates += 1 }
        m.setHideVolume(true); m.setSampleMode(true); m.toggleDefaultMute()
        #expect(updates > 0)
        #expect(m.badgePanel?.isVisible == false)
        m.setShowBadge(true); #expect(m.badgePanel?.isVisible == true)
        m.setShowBadge(false); #expect(m.badgePanel?.isVisible == false)
        withExtendedLifetime(observation) {}
    }
    @Test func verifiedExternalStateRefreshChangesIndicator() {
        let m = model(); let d = m.currentDefault()!
        _ = m.sample.setMute(d, false); m.refresh(); #expect(!m.isDefaultMuted())
        _ = m.sample.setMute(d, true); m.refresh(); #expect(m.isDefaultMuted())
    }
    @Test func settingsMenuRouteCreatesReusableWindow() {
        _ = NSApplication.shared
        let delegate = AppDelegate(); delegate.model = model()
        delegate.openSettings()
        #expect(delegate.settingsWindow?.isVisible == true)
        let window = delegate.settingsWindow
        delegate.openSettings(); #expect(delegate.settingsWindow === window)
        delegate.settingsWindow?.orderOut(nil)
    }
    @Test func sampleFixturesAreIndependent() {
        let first = SampleDevices(), second = SampleDevices()
        _ = first.select("sample-3")
        #expect(second.devices().first(where: { $0.isDefault })?.id == "sample-1")
    }
    @Test func resetDeletesRememberedPreferences() {
        let m = model(); m.registerShortcut = { _, _ in true }
        m.setHideVolume(true); m.setPushToTalk(true); m.resetStoredData()
        #expect(!m.hideVolume && !m.pushToTalk && !m.sampleMode)
        #expect(m.defaults.object(forKey: "hideVolume") == nil)
    }
}
