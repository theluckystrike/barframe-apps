import Foundation
import Carbon.HIToolbox

/// Persisted user settings beyond DeviceMemory (defaults-backed, testable mapping).
public struct HotKeyConfig: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var useShift: Bool
    public var useOption: Bool

    public init(keyCode: UInt32 = UInt32(kVK_ANSI_M), useShift: Bool = true, useOption: Bool = true) {
        self.keyCode = keyCode
        self.useShift = useShift
        self.useOption = useOption
    }

    public static let `default` = HotKeyConfig()

    /// Human-readable summary, e.g. "⇧⌥M" for the default (ANSI M).
    public var label: String {
        var s = ""
        if useShift { s += "⇧" }
        if useOption { s += "⌥" }
        s += HotKeyConfig.keyName(keyCode)
        return s
    }

    /// Names for the keys a user can pick in Settings.
    public static func keyName(_ code: UInt32) -> String {
        switch code {
        case UInt32(kVK_ANSI_M): return "M"
        case 11: return "B"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 34: return "I"
        case 40: return "K"
        case 37: return "L"
        case UInt32(kVK_ANSI_N): return "N"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 9: return "V"
        case 13: return "W"
        case 16: return "Y"
        case 12: return "Q"
        case 6: return "Z"
        case 49: return "Space"
        default: return "Key \(code)"
        }
    }

    /// Key codes offered in the Settings picker.
    public static let selectableKeyCodes: [UInt32] = [UInt32(kVK_ANSI_M), 11, 2, 14, 3, 5, 34, 40, 37, UInt32(kVK_ANSI_N), 15, 1, 17, 9, 13, 16, 12, 6, 49]

    public static func encode(_ c: HotKeyConfig) -> String {
        "\(c.keyCode)|\(c.useShift ? 1 : 0)|\(c.useOption ? 1 : 0)"
    }

    public static func decode(_ s: String) -> HotKeyConfig? {
        let parts = s.split(separator: "|").compactMap { Int($0) }
        guard parts.count == 3, parts[0] >= 0 else { return nil }
        return HotKeyConfig(keyCode: UInt32(parts[0]), useShift: parts[1] == 1, useOption: parts[2] == 1)
    }
}

/// Carbon modifier flags for a config.
public extension HotKeyConfig {
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if useShift { m |= UInt32(shiftKey) } // shiftKey
        if useOption { m |= UInt32(optionKey) } // optionKey
        return m
    }
}

/// Push-to-talk state machine. Key down -> unmute (or mute if inverted);
/// key up -> restore the previous state. Pure logic, unit-tested.
public enum PushToTalk {
    public enum Phase: Equatable, Sendable {
        case idle
        case talking
    }

    /// What to do when the key goes down while the mic is `isMuted`.
    public static func onKeyDown(isMuted: Bool, phase: Phase) -> MicTarget? {
        guard phase == .idle else { return nil } // ignore repeat-downs
        return isMuted ? .unmuted : nil
    }

    /// What to do when the key goes back up.
    public static func onKeyUp(phase: Phase) -> MicTarget? {
        guard phase == .talking else { return nil }
        return .muted
    }
}
