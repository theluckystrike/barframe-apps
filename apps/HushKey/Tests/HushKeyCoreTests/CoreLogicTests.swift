import Testing
import Foundation
@testable import HushKeyCore

@Suite struct MicPolicyTests {
    @Test func mutePropertyWhenSupported() {
        let d = InputDevice(id: "1", name: "Mic", supportsMute: true, supportsVolume: true)
        #expect(MutePolicy.apply(.muted, to: d, rememberedVolume: 0.5) == .mutedByProperty)
    }
    @Test func muteFallsBackToVolumeZero() {
        let d = InputDevice(id: "1", name: "Mic", supportsMute: false, supportsVolume: true)
        #expect(MutePolicy.apply(.muted, to: d, rememberedVolume: 0.5) == .mutedByVolumeZero)
    }
    @Test func unsupportedDeviceReportsIt() {
        let d = InputDevice(id: "1", name: "Mic", supportsMute: false, supportsVolume: false)
        #expect(MutePolicy.apply(.muted, to: d, rememberedVolume: nil) == .unsupported)
        #expect(MutePolicy.apply(.unmuted, to: d, rememberedVolume: nil) == .unsupported)
    }
    @Test func restoreVolumePrefersRemembered() {
        #expect(MutePolicy.restoreVolume(remembered: 0.37) == 0.37)
    }
    @Test func restoreVolumeFallsBackToHalf() {
        #expect(MutePolicy.restoreVolume(remembered: nil) == 0.5)
        #expect(MutePolicy.restoreVolume(remembered: 0.0) == 0.5)
    }
    @Test func restoreVolumeClamps() {
        #expect(MutePolicy.restoreVolume(remembered: 1.7) == 1.0)
        // Near-zero values are treated as "no memory" and fall back to the default.
        #expect(MutePolicy.restoreVolume(remembered: 0.2) == 0.2)
    }
}

@Suite struct ReapplyLogicTests {
    let mutedMic = InputDevice(id: "a", name: "A", supportsMute: true)
    @Test func alwaysMuteSilencesNewDefault() {
        #expect(ReapplyLogic.shouldMute(intent: .alwaysMute, newDevice: mutedMic, previousDeviceWasMutedByApp: false, manuallyUnmutedRecently: false))
    }
    @Test func offNeverMutes() {
        #expect(!ReapplyLogic.shouldMute(intent: .off, newDevice: mutedMic, previousDeviceWasMutedByApp: true, manuallyUnmutedRecently: false))
    }
    @Test func stayMutedRequiresPriorAppMute() {
        #expect(ReapplyLogic.shouldMute(intent: .stayMutedOnly, newDevice: mutedMic, previousDeviceWasMutedByApp: true, manuallyUnmutedRecently: false))
        #expect(!ReapplyLogic.shouldMute(intent: .stayMutedOnly, newDevice: mutedMic, previousDeviceWasMutedByApp: false, manuallyUnmutedRecently: false))
    }
    @Test func manualUnmuteWinsOverStayMuted() {
        #expect(!ReapplyLogic.shouldMute(intent: .stayMutedOnly, newDevice: mutedMic, previousDeviceWasMutedByApp: true, manuallyUnmutedRecently: true))
    }
    @Test func uncontrollableDeviceNeverMuted() {
        let d = InputDevice(id: "b", name: "B", supportsMute: false, supportsVolume: false)
        #expect(!ReapplyLogic.shouldMute(intent: .alwaysMute, newDevice: d, previousDeviceWasMutedByApp: true, manuallyUnmutedRecently: false))
    }
}

@Suite struct MenuLineTests {
    @Test func mutedShowsLock() {
        #expect(MenuLine.label(muted: true, volumePercent: 75, hideVolume: false) == "🔒 75%")
    }
    @Test func openShowsMic() {
        #expect(MenuLine.label(muted: false, volumePercent: 30, hideVolume: false) == "🎙 30%")
    }
    @Test func hideVolumeShowsIconOnly() {
        #expect(MenuLine.label(muted: true, volumePercent: 75, hideVolume: true) == "🔒")
    }
    @Test func noVolumeShowsDash() {
        #expect(MenuLine.label(muted: false, volumePercent: nil, hideVolume: false) == "🎙")
    }
    @Test func volumeClampedToRange() {
        #expect(MenuLine.label(muted: false, volumePercent: 150, hideVolume: false).contains("100%"))
        #expect(MenuLine.label(muted: false, volumePercent: -5, hideVolume: false).contains("0%"))
    }
    @Test func noDeviceMarker() {
        #expect(MenuLine.noDevice.contains("✕"))
    }
    @Test func statusLineMuted() {
        #expect(MenuLine.statusLine(deviceName: "Mic", muted: true, volumePercent: nil) == "Mic — Muted")
    }
    @Test func statusLineOpen() {
        #expect(MenuLine.statusLine(deviceName: "Mic", muted: false, volumePercent: 64) == "Mic — Open at 64%")
    }
    @Test func statusLineMissingDevice() {
        #expect(MenuLine.statusLine(deviceName: nil, muted: true, volumePercent: nil) == "No input device — Muted")
    }
}

@Suite struct DeviceMemoryTests {
    @Test func markAndRecall() {
        var m = DeviceMemory()
        m.markMuted("d1", volumeBefore: 0.6)
        #expect(m.wasMutedByApp("d1"))
        #expect(m.rememberedVolume("d1") == 0.6)
    }
    @Test func unmuteClearsFlag() {
        var m = DeviceMemory()
        m.markMuted("d1", volumeBefore: nil)
        m.markUnmuted("d1")
        #expect(!m.wasMutedByApp("d1"))
    }
    @Test func forgetRemovesEverything() {
        var m = DeviceMemory()
        m.markMuted("d1", volumeBefore: 0.4)
        m.forget("d1")
        #expect(!m.wasMutedByApp("d1"))
        #expect(m.rememberedVolume("d1") == nil)
    }
    @Test func storeRoundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hk-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = MemoryStore(directory: dir)
        var m = DeviceMemory()
        m.markMuted("d9", volumeBefore: 0.8)
        store.save(m)
        let loaded = store.load()
        #expect(loaded == m)
    }
    @Test func storeMissingFileYieldsEmpty() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hk-tests-\(UUID().uuidString)", isDirectory: true)
        let store = MemoryStore(directory: dir)
        #expect(store.load() == DeviceMemory())
    }
}

@Suite struct HotKeyConfigTests {
    @Test func defaultIsShiftOptionM() {
        #expect(HotKeyConfig.default.keyCode == 46)
        #expect(HotKeyConfig.default.useShift && HotKeyConfig.default.useOption)
        #expect(HotKeyConfig.default.label == "⇧⌥M")
    }
    @Test func encodeDecodeRoundTrip() {
        let c = HotKeyConfig(keyCode: 49, useShift: false, useOption: true)
        #expect(HotKeyConfig.decode(HotKeyConfig.encode(c)) == c)
    }
    @Test func decodeRejectsGarbage() {
        #expect(HotKeyConfig.decode("nonsense") == nil)
        #expect(HotKeyConfig.decode("") == nil)
    }
    @Test func keyNamesCoverPicker() {
        #expect(HotKeyConfig.keyName(49) == "Space")
        #expect(HotKeyConfig.keyName(999) == "Key 999")
        #expect(HotKeyConfig.selectableKeyCodes.contains(46))
    }
    @Test func carbonModifiersMap() {
        let both = HotKeyConfig(keyCode: 50, useShift: true, useOption: true)
        #expect(both.carbonModifiers == ((1 << 9) | (1 << 11)))
        let none = HotKeyConfig(keyCode: 50, useShift: false, useOption: false)
        #expect(none.carbonModifiers == 0)
    }
}

@Suite struct PushToTalkTests {
    @Test func keyDownUnmutesMutedMic() {
        #expect(PushToTalk.onKeyDown(isMuted: true, phase: .idle) == .unmuted)
    }
    @Test func keyDownIgnoredWhenAlreadyOpen() {
        #expect(PushToTalk.onKeyDown(isMuted: false, phase: .idle) == nil)
    }
    @Test func repeatDownIgnored() {
        #expect(PushToTalk.onKeyDown(isMuted: true, phase: .talking) == nil)
    }
    @Test func keyUpReMutesWhileTalking() {
        #expect(PushToTalk.onKeyUp(phase: .talking) == .muted)
    }
    @Test func keyUpIgnoredWhenIdle() {
        #expect(PushToTalk.onKeyUp(phase: .idle) == nil)
    }
}

@Suite struct SampleDataTests {
    @Test func sampleDevicesExistWithDefault() {
        #expect(!SampleData.devices.isEmpty)
        #expect(SampleData.devices.contains(where: { $0.isDefault }))
        #expect(SampleData.defaultDevice.isDefault)
    }
    @Test func everySampleDeviceNamedWithSample() {
        #expect(SampleData.devices.allSatisfy { $0.name.contains("Sample") })
    }
    @Test func sampleLabelCarriesSampleWord() {
        #expect(SampleData.label(muted: true, hideVolume: false).contains("Sample"))
        #expect(SampleData.label(muted: true, hideVolume: false).contains("🔒"))
    }
    @Test func sampleFixturesAreImmutableCopies() {
        var switched = SampleData.devices
        for i in switched.indices { switched[i].isDefault = false }
        switched[2].isDefault = true
        #expect(SampleData.defaultDevice.isDefault)
        #expect(SampleData.devices[0].isDefault)
    }
}
