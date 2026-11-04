import Foundation
import CoreAudio
import CallCore

@MainActor protocol DeviceBackend: AnyObject {
    func devices() -> [InputDevice]
    func mute(_ device: InputDevice) -> Bool?
    func volume(_ device: InputDevice) -> Float?
    func setMute(_ device: InputDevice, _ muted: Bool) -> Bool
    func setVolume(_ device: InputDevice, _ volume: Float) -> Bool
    func select(_ id: String) -> Bool
}

/// CoreAudio input devices. Reads run on demand. No audio is captured.
@MainActor final class LiveDevices: DeviceBackend {
    func devices() -> [InputDevice] { AudioDevices.inputDevices() }
    func mute(_ d: InputDevice) -> Bool? { AudioDevices.isMuted(AudioObjectID(idString: d.id)) }
    func volume(_ d: InputDevice) -> Float? { AudioDevices.inputVolume(AudioObjectID(idString: d.id)) }
    func setMute(_ d: InputDevice, _ muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(AudioObjectID(idString: d.id), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
    func setVolume(_ d: InputDevice, _ volume: Float) -> Bool { MicControl.setVolume(AudioObjectID(idString: d.id), volume: volume) }
    func select(_ id: String) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = AudioObjectID(idString: id)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }
}

@MainActor enum DeviceState {
    static func muted(_ d: InputDevice, backend: DeviceBackend) -> Bool? {
        if d.supportsMute, let value = backend.mute(d) { return value }
        return backend.volume(d).map { $0 == 0 }
    }
}

extension AudioObjectID {
    init(idString: String) { self = UInt32(idString) ?? 0 }
}

/// Mute part: global shortcut, push-to-talk, floating badge and the rule for a new default microphone.
@MainActor final class MuteModel: ObservableObject {
    @Published var intent: ReapplyLogic.Intent
    @Published var lastOutcome = ""
    @Published var showBadge: Bool
    @Published var pushToTalk: Bool
    @Published var pttActive = false
    @Published private(set) var hotKey: HotKeyConfig
    @Published var revision = 0
    /// False when macOS rejected the shortcut. Settings then says "Shortcut not available".
    @Published private(set) var shortcutAvailable = true
    private var memory: DeviceMemory { didSet { store.save(memory) } }
    private let store: MemoryStore
    let defaults: UserDefaults
    let backend: DeviceBackend
    var badgePanel: MicBadgePanel?
    private var heldDevice: InputDevice?
    private var lastDevice: InputDevice?
    /// Called after push-to-talk starts or ends, when the state is complete.
    var onPushToTalkChange: ((Bool) -> Void)?
    var registerShortcut: (HotKeyConfig, @escaping () -> Void) -> Bool = { HotKeyCenter.shared.register(config: $0, action: $1) }

    init(storeDirectory: URL? = nil, backend: DeviceBackend? = nil, defaults: UserDefaults = .standard) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = storeDirectory ?? base.appendingPathComponent("CallReady")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = MemoryStore(directory: dir); memory = store.load()
        self.defaults = defaults; self.backend = backend ?? LiveDevices()
        intent = ReapplyLogic.Intent(rawValue: defaults.string(forKey: "intent") ?? "") ?? .stayMutedOnly
        showBadge = defaults.bool(forKey: "showBadge")
        pushToTalk = defaults.bool(forKey: "pushToTalk")
        hotKey = HotKeyConfig.decode(defaults.string(forKey: "hotKey") ?? "") ?? .default
    }
    func start() { lastDevice = currentDefault(); refresh() }
    func stop() { endPushToTalk() }
    func refresh() {
        revision += 1
        if showBadge { badgePanel?.show(state: isDefaultMuted(), pushToTalkActive: pttActive) }
        else { badgePanel?.hide() }
    }
    func setIntent(_ value: ReapplyLogic.Intent) { intent = value; defaults.set(value.rawValue, forKey: "intent") }
    func setShowBadge(_ value: Bool) { showBadge = value; defaults.set(value, forKey: "showBadge"); refresh() }
    func setPushToTalk(_ value: Bool) {
        if !value { endPushToTalk() }
        pushToTalk = value; defaults.set(value, forKey: "pushToTalk"); refresh()
    }
    func setHotKey(_ config: HotKeyConfig) {
        hotKey = config
        defaults.set(HotKeyConfig.encode(config), forKey: "hotKey")
        applyHotKey(config)
    }
    func applyHotKey(_ config: HotKeyConfig) {
        endPushToTalk()
        let ok = registerShortcut(config) { [weak self] in
            guard let self else { return }
            if self.pushToTalk { self.beginPushToTalk() } else { self.toggleDefaultMute() }
        }
        shortcutAvailable = ok
        lastOutcome = ok ? "Shortcut ready: \(config.label)" : "Shortcut not available. Choose a different key in Settings."
    }
    func registerPushToTalkRelease() { HotKeyCenter.shared.onRelease = { [weak self] in self?.endPushToTalk() } }
    func beginPushToTalk() {
        guard pushToTalk, !pttActive, let d = currentDefault() else { return }
        if apply(target: .unmuted, device: d) { heldDevice = d; pttActive = true; onPushToTalkChange?(true) }; refresh()
    }
    func endPushToTalk() {
        guard pttActive, let d = heldDevice else { return }
        _ = apply(target: .muted, device: d)
        heldDevice = nil; pttActive = false; refresh()
        onPushToTalkChange?(false)
    }
    func devices() -> [InputDevice] { backend.devices() }
    func currentDefault() -> InputDevice? { devices().first(where: { $0.isDefault }) }
    func isDefaultMuted() -> Bool { currentDefault().flatMap { DeviceState.muted($0, backend: backend) } ?? false }
    /// Nil when there is no input device or the device has no mute or volume control.
    func muteState() -> Bool? { currentDefault().flatMap { DeviceState.muted($0, backend: backend) } }
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
            // The live state shows the result. A stored "Muted" text could go stale when another app
            // or device changes the mute state, so a success leaves no message.
            lastOutcome = ""
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
    /// Applies the "When the default microphone changes" rule. Repeated calls for the same device do nothing.
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
    func resetStoredData() {
        endPushToTalk(); memory = DeviceMemory()
        for key in ["hotKey", "intent", "showBadge", "pushToTalk"] { defaults.removeObject(forKey: key) }
        intent = .stayMutedOnly; showBadge = false; pushToTalk = false; hotKey = .default
        applyHotKey(.default); lastDevice = currentDefault(); lastOutcome = "Mute preferences and device memory reset"; refresh()
    }
}

/// Listens for mute and volume changes on the default input, made by other apps or by the keyboard.
@MainActor final class MuteStateListener {
    private var observed: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var changed: (() -> Void)?

    func watch(_ changed: @escaping () -> Void) { self.changed = changed; rewatch() }

    func rewatch() {
        stop()
        guard changed != nil, let id = AudioDevices.defaultInputID() else { return }
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.changed?() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr { observed.append((id, address, block)) }
        }
    }

    func stop() {
        for (id, var address, block) in observed { AudioObjectRemovePropertyListenerBlock(id, &address, .main, block) }
        observed.removeAll()
    }
}
