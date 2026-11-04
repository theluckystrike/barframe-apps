import Foundation

/// Pure logic for the re-apply loop: when the system default input device changes,
/// HushKey decides whether to silence the new default based on user intent.
public enum ReapplyLogic {
    /// Intent the user picked in Settings.
    public enum Intent: String, CaseIterable, Codable, Sendable {
        case alwaysMute = "always"
        case stayMutedOnly = "stayMuted"
        case off = "off"
    }

    /// Should we mute the newly-selected default device?
    /// - alwaysMute: every new default gets muted.
    /// - stayMutedOnly: only mute if HushKey muted the previous device (user wants silence to persist).
    /// - off: never.
    public static func shouldMute(
        intent: Intent,
        newDevice: InputDevice,
        previousDeviceWasMutedByApp: Bool,
        manuallyUnmutedRecently: Bool
    ) -> Bool {
        switch intent {
        case .off: return false
        case .alwaysMute:
            return newDevice.supportsMute || newDevice.supportsVolume
        case .stayMutedOnly:
            if manuallyUnmutedRecently { return false }
            return previousDeviceWasMutedByApp && (newDevice.supportsMute || newDevice.supportsVolume)
        }
    }
}
