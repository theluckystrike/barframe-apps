import Foundation
import CoreAudio
import HushKeyCore

@MainActor protocol DeviceBackend: AnyObject {
    func devices() -> [InputDevice]
    func mute(_ device: InputDevice) -> Bool?
    func volume(_ device: InputDevice) -> Float?
    func setMute(_ device: InputDevice, _ muted: Bool) -> Bool
    func setVolume(_ device: InputDevice, _ volume: Float) -> Bool
    func select(_ id: String) -> Bool
}

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

@MainActor final class SampleDevices: DeviceBackend {
    var list = SampleData.devices
    var mutes: [String: Bool] = [:]
    var volumes: [String: Float] = [:]
    func devices() -> [InputDevice] { list }
    func mute(_ d: InputDevice) -> Bool? { d.supportsMute ? (mutes[d.id] ?? true) : nil }
    func volume(_ d: InputDevice) -> Float? { d.supportsVolume ? (volumes[d.id] ?? 0.64) : nil }
    func setMute(_ d: InputDevice, _ muted: Bool) -> Bool {
        guard d.supportsMute else { return false }; mutes[d.id] = muted; return true
    }
    func setVolume(_ d: InputDevice, _ volume: Float) -> Bool {
        guard d.supportsVolume else { return false }; volumes[d.id] = volume; return true
    }
    func select(_ id: String) -> Bool {
        guard list.contains(where: { $0.id == id }) else { return false }
        for i in list.indices { list[i].isDefault = list[i].id == id }; return true
    }
}

@MainActor enum DeviceState {
    static func muted(_ d: InputDevice, backend: DeviceBackend) -> Bool? {
        if d.supportsMute, let value = backend.mute(d) { return value }
        return backend.volume(d).map { $0 == 0 }
    }
    /// Restore both independently, including when the test write fails.
    static func selfTest(_ d: InputDevice, backend: DeviceBackend) -> (Bool, String) {
        let mute = backend.mute(d), volume = backend.volume(d)
        var restored = true
        var changed = false
        func exercise() {
            defer {
                if let volume { restored = backend.setVolume(d, volume) && restored }
                if let mute { restored = backend.setMute(d, mute) && restored }
            }
            if let mute { changed = backend.setMute(d, !mute) }
            else if let volume { changed = backend.setVolume(d, volume == 0 ? 0.5 : 0) }
        }
        exercise()
        let verified = backend.mute(d) == mute && backend.volume(d) == volume
        return (changed && restored && verified, "Test write: \(changed ? "passed" : "unsupported or failed"); restore: \(restored && verified ? "verified" : "FAILED — check microphone settings")")
    }
}
