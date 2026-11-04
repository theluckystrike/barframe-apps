import Foundation

/// One audio input device as seen by CoreAudio. Pure data so tests can build fixtures.
public struct InputDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let uid: String
    public let name: String
    public let supportsMute: Bool
    public let supportsVolume: Bool
    public var isDefault: Bool

    public init(id: String, name: String, supportsMute: Bool = true, supportsVolume: Bool = false, isDefault: Bool = false, uid: String? = nil) {
        self.id = id
        self.uid = uid ?? id
        self.name = name
        self.supportsMute = supportsMute
        self.supportsVolume = supportsVolume
        self.isDefault = isDefault
    }
}

/// What the app wants the microphone to be.
public enum MicTarget: Equatable, Sendable {
    case muted
    case unmuted
}

/// Result of applying a target to one device.
public enum ApplyOutcome: Equatable, Sendable {
    /// Mute property written successfully.
    case mutedByProperty
    /// Device lacks mute property; input volume set to 0 (or restored from memory).
    case mutedByVolumeZero
    /// Unmute applied.
    case unmuted
    /// Device can't be controlled the way the target needs (no mute and no volume support).
    case unsupported
    /// CoreAudio returned an error.
    case failed(String)
}

/// Decision engine: given a device and a target, which CoreAudio path do we take?
/// Mirrors the real AudioObjectSetPropertyData branches without touching CoreAudio.
public enum MutePolicy {
    public static func apply(_ target: MicTarget, to device: InputDevice, rememberedVolume: Float32?) -> ApplyOutcome {
        switch target {
        case .muted:
            if device.supportsMute { return .mutedByProperty }
            if device.supportsVolume { return .mutedByVolumeZero }
            return .unsupported
        case .unmuted:
            if !device.supportsMute && !device.supportsVolume { return .unsupported }
            return .unmuted
        }
    }

    /// Volume to write when un-muting a device that was muted by volume zero.
    /// Restores the remembered volume, else falls back to a sane 0.5.
    public static func restoreVolume(remembered: Float32?) -> Float32 {
        guard let remembered, remembered > 0.001 else { return 0.5 }
        return min(max(remembered, 0), 1)
    }
}
