import Foundation

/// Presentation for the single menu bar line. Pure string logic, unit-tested.
public enum MenuLine {
    /// e.g. "🔒 75%" or "🎙 75%" or "🎙 —" when volume is unavailable.
    public static func label(muted: Bool, volumePercent: Int?, hideVolume: Bool) -> String {
        let icon = muted ? "🔒" : "🎙"
        guard !hideVolume, let volumePercent else { return icon }
        let clamped = min(max(volumePercent, 0), 100)
        return "\(icon) \(clamped)%"
    }

    /// Menu bar title when no input device exists.
    public static let noDevice = "🎙 ✕"

    /// Tooltip / first menu line.
    public static func statusLine(deviceName: String?, muted: Bool, volumePercent: Int?) -> String {
        let device = deviceName ?? "No input device"
        let state: String
        switch (muted, volumePercent) {
        case (true, _): state = "Muted"
        case (false, .some(let p)): state = "Open at \(p)%"
        case (false, .none): state = "Open"
        }
        return "\(device) — \(state)"
    }
}
