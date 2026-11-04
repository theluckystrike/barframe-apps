import Foundation
import CoreAudio
import HushKeyCore

/// Thin wrapper over CoreAudio for input devices. All calls run on demand; no polling.
/// Kept in one place so the rest of the app stays CoreAudio-free.
enum AudioDevices {
    /// All input devices, marked with the current default.
    static func inputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        let defaultID = defaultInputID() ?? 0
        return ids.compactMap { id in
            guard isInput(id) else { return nil }
            return InputDevice(
                id: String(id),
                name: deviceName(id) ?? "Input \(id)",
                supportsMute: hasMute(id),
                supportsVolume: hasVolume(id),
                isDefault: id == defaultID, uid: deviceUID(id))
        }
    }

    static func defaultInputID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func isInput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    static func deviceName(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name as String?
    }

    static func deviceUID(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String
    }

    static func hasMute(_ id: AudioObjectID) -> Bool { writable(id, kAudioDevicePropertyMute) }
    static func hasVolume(_ id: AudioObjectID) -> Bool { writable(id, kAudioDevicePropertyVolumeScalar) }

    static func writable(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var writable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &writable) == noErr && writable.boolValue
    }

    /// Mute state of the device's first input element.
    static func isMuted(_ id: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &mute) == noErr else { return nil }
        return mute != 0
    }

    /// Input volume 0...1 of the first input element.
    static func inputVolume(_ id: AudioObjectID) -> Float32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &vol) == noErr else { return nil }
        return vol
    }
}

/// Applies mute/unmute to a device. Returns the outcome for logging + tests.
enum MicControl {
    static func setMuted(_ id: AudioObjectID, muted: Bool) -> ApplyOutcome {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        let err = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        if err == noErr { return muted ? .mutedByProperty : .unmuted }
        if muted {
            // No mute property: fall back to volume zero.
            var volAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var zero: Float32 = 0
            let volErr = AudioObjectSetPropertyData(id, &volAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &zero)
            return volErr == noErr ? .mutedByVolumeZero : .failed("mute err \(err), volume err \(volErr)")
        }
        return .failed("unmute err \(err)")
    }

    static func setVolume(_ id: AudioObjectID, volume: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var value = volume
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}
