import Foundation

/// Simulated devices for Sample mode (App Review can exercise every control
/// without touching real hardware). Pure data so tests build on it directly.
public enum SampleData {
    public static let devices: [InputDevice] = [
        InputDevice(id: "sample-1", name: "Studio Microphone (Sample)", supportsMute: true, supportsVolume: true, isDefault: true),
        InputDevice(id: "sample-2", name: "Built-in Microphone (Sample)", supportsMute: true, supportsVolume: true, isDefault: false),
        InputDevice(id: "sample-3", name: "USB Headset (Sample)", supportsMute: false, supportsVolume: true, isDefault: false),
    ]

    public static let defaultDevice: InputDevice = devices[0]

    /// Menu line for the simulated default device.
    public static func label(muted: Bool, hideVolume: Bool) -> String {
        MenuLine.label(muted: muted, volumePercent: muted ? 0 : 64, hideVolume: hideVolume)
            + "  Sample"
    }

}
