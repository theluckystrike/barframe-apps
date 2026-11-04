import Foundation
import CoreAudio
import HushKeyCore
import MASKit

@MainActor final class AppModel: ObservableObject {
    @Published var hideVolume: Bool
    @Published var intent: ReapplyLogic.Intent
    @Published var lastOutcome = ""
    @Published var sampleMode: Bool
    @Published var showBadge: Bool
    @Published var pushToTalk: Bool
    @Published var pttActive = false
    @Published var revision = 0
    private var liveMemory: DeviceMemory
    private var sampleMemory = DeviceMemory()
    private let store: MemoryStore
    let defaults: UserDefaults
    let live: DeviceBackend
    let sample: SampleDevices
    var backend: DeviceBackend { sampleMode ? sample : live }
    private var memory: DeviceMemory {
        get { sampleMode ? sampleMemory : liveMemory }
        set { if sampleMode { sampleMemory = newValue } else { liveMemory = newValue; store.save(liveMemory) } }
    }
    var badgePanel: MicBadgePanel?
    private var heldDevice: InputDevice?
    private var lastDevice: InputDevice?
    var registerShortcut: (HotKeyConfig, @escaping () -> Void) -> Bool = { HotKeyCenter.shared.register(config: $0, action: $1) }

    init(storeDirectory: URL? = nil, live: DeviceBackend? = nil, defaults: UserDefaults = .standard) {
        let dir = storeDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("HushKey")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = MemoryStore(directory: dir); liveMemory = store.load()
        self.defaults = defaults; self.live = live ?? LiveDevices(); sample = SampleDevices()
        hideVolume = defaults.bool(forKey: "hideVolume")
        intent = ReapplyLogic.Intent(rawValue: defaults.string(forKey: "intent") ?? "") ?? .alwaysMute
        sampleMode = defaults.bool(forKey: "sampleMode")
        showBadge = defaults.bool(forKey: "showBadge")
        pushToTalk = defaults.bool(forKey: "pushToTalk")
    }
    func start() { lastDevice = currentDefault(); refresh() }
    func stop() { endPushToTalk() }
    func refresh() {
        revision += 1
        if showBadge { badgePanel?.show(state: isDefaultMuted(), pushToTalkActive: pttActive) }
        else { badgePanel?.hide() }
    }
    func setHideVolume(_ value: Bool) { hideVolume = value; defaults.set(value, forKey: "hideVolume"); refresh() }
    func setIntent(_ value: ReapplyLogic.Intent) { intent = value; defaults.set(value.rawValue, forKey: "intent") }
    func setSampleMode(_ value: Bool) {
        endPushToTalk()
        sampleMode = value; defaults.set(value, forKey: "sampleMode")
        lastDevice = currentDefault()
        lastOutcome = value ? "Sample mode: simulated devices" : "Sample mode off: real devices"
        refresh()
    }
    func setShowBadge(_ value: Bool) { showBadge = value; defaults.set(value, forKey: "showBadge"); refresh() }
    func setPushToTalk(_ value: Bool) {
        if !value { endPushToTalk() }
        pushToTalk = value; defaults.set(value, forKey: "pushToTalk"); refresh()
    }
    func applyHotKey(_ config: HotKeyConfig) {
        endPushToTalk()
        let ok = registerShortcut(config) { [weak self] in
            guard let self else { return }
            if self.pushToTalk { self.beginPushToTalk() } else { self.toggleDefaultMute() }
        }
        lastOutcome = ok ? "Shortcut ready: \(config.label)" : "Shortcut unavailable. Choose a different key in Settings."
    }
    func registerPushToTalkRelease() { HotKeyCenter.shared.onRelease = { [weak self] in self?.endPushToTalk() } }
    func beginPushToTalk() {
        guard pushToTalk, !pttActive, let d = currentDefault() else { return }
        if apply(target: .unmuted, device: d) { heldDevice = d; pttActive = true }; refresh()
    }
    func endPushToTalk() {
        guard pttActive, let d = heldDevice else { return }
        _ = apply(target: .muted, device: d)
        pttActive = false; heldDevice = nil; refresh()
    }
    func devices() -> [InputDevice] { backend.devices() }
    func currentDefault() -> InputDevice? { devices().first(where: { $0.isDefault }) }
    func isDefaultMuted() -> Bool { currentDefault().flatMap { DeviceState.muted($0, backend: backend) } ?? false }
    func currentVolume() -> Float? { currentDefault().flatMap { backend.volume($0) } }
    func toggleDefaultMute() {
        guard let d = currentDefault() else { lastOutcome = "No input device found"; return }
        _ = apply(target: isDefaultMuted() ? .unmuted : .muted, device: d)
    }
    func muteDefault() {
        guard let d = currentDefault() else { lastOutcome = "No input device found"; return }
        _ = apply(target: .muted, device: d)
    }
    @discardableResult func apply(target: MicTarget, device d: InputDevice) -> Bool {
        let before = backend.volume(d)
        var ok = false
        if d.supportsMute { ok = backend.setMute(d, target == .muted) }
        else if d.supportsVolume {
            let volume = target == .muted ? 0 : MutePolicy.restoreVolume(remembered: memory.rememberedVolume(d.uid))
            ok = backend.setVolume(d, volume)
        }
        ok = ok && DeviceState.muted(d, backend: backend) == (target == .muted)
        if ok {
            if target == .muted { memory.markMuted(d.uid, volumeBefore: d.supportsMute ? nil : before) }
            else { memory.markUnmuted(d.uid) }
            lastOutcome = target == .muted ? "Muted" : "Open"
        } else {
            lastOutcome = d.supportsMute || d.supportsVolume ? "Microphone control failed. Check the device in Sound settings." : "Device does not support mute or input volume. Choose another microphone."
        }
        refresh(); return ok
    }
    func setVolume(_ value: Float) {
        guard let d = currentDefault() else { return }
        lastOutcome = backend.setVolume(d, value) ? "Input volume updated" : "Cannot change input volume on this device"
        refresh()
    }
    func selectDefaultDevice(_ id: String) {
        if backend.select(id) { defaultDeviceChanged() }
        else { lastOutcome = "Cannot select that input device" }; refresh()
    }
    func defaultDeviceChanged() {
        guard let d = currentDefault(), d.id != lastDevice?.id else { refresh(); return }
        let wasHeld = pttActive
        endPushToTalk()
        let previousMuted = lastDevice.map { memory.wasMutedByApp($0.uid) } ?? false
        if wasHeld || ReapplyLogic.shouldMute(intent: intent, newDevice: d, previousDeviceWasMutedByApp: previousMuted, manuallyUnmutedRecently: false) {
            _ = apply(target: .muted, device: d)
        }
        lastDevice = d; refresh()
    }
    func runSelfTestChecks() -> [String] {
        guard let d = currentDefault() else { lastOutcome = "Self test: no default input device"; return [lastOutcome] }
        let result = DeviceState.selfTest(d, backend: backend)
        lastOutcome = "\(sampleMode ? "Sample " : "")Self test \(result.0 ? "passed" : "failed"): \(result.1)"
        refresh(); return [lastOutcome]
    }
    func resetStoredData() {
        endPushToTalk(); liveMemory = DeviceMemory(); sampleMemory = DeviceMemory(); store.save(liveMemory)
        for key in ["hotKey", "hideVolume", "intent", "sampleMode", "showBadge", "pushToTalk"] { defaults.removeObject(forKey: key) }
        hideVolume = false; intent = .alwaysMute; sampleMode = false; showBadge = false; pushToTalk = false
        applyHotKey(.default); lastDevice = currentDefault(); lastOutcome = "Local preferences and device memory reset"; refresh()
    }
}
