import Foundation

/// Neutral, deterministic hardware examples available without attached devices or credentials.
public enum SampleReadings {
    public static func power(date: Date = Date()) -> PowerSnapshot {
        PowerSnapshot(date: date, supply: .external,
                      adapter: AdapterReading(properties: ["Watts": 65, "Name": "Sample USB-C adapter", "AdapterVoltage": 20000, "Current": 3250]),
                      battery: BatteryReading(source: ["Name": "Sample battery", "Current Capacity": 72,
                                                       "Max Capacity": 100, "Is Charging": true, "BatteryHealth": "Good", "Time to Full Charge": 42],
                                              registry: ["CycleCount": 243, "NominalChargeCapacity": 3950, "DesignCapacity": 5000, "Voltage": 12000, "InstantAmperage": 1500, "Temperature": 3032]),
                      sourceCount: 1, inputWatts: 40.8)
    }
    public static var connections: ConnectionSnapshot {
        let names = ["Sample USB-C storage", "Sample camera", "Sample audio interface", "Sample card reader", "Sample keyboard", "Sample pointing device", "Sample external hub", "Sample backup drive", "Sample display adapter", "Sample game controller"]
        var devices = names.enumerated().map { index, name in
            USBDevice(id: UInt64(index + 1), properties: ["USB Product Name": name,
                "USB Vendor Name": "Sample manufacturer", "USBSpeed": index == 0 ? 5 : (index == 1 ? 3 : (index % 3 + 3)),
                "USBPortType": 5, "bDeviceClass": index == 6 ? 9 : 0, "bcdUSB": 0x0300,
                "UsbPowerSinkAllocation": index == 0 ? 896 : 100, "kUSBWakePortCurrentLimit": 900])
        }
        devices.append(USBDevice(id: 11, properties: ["USB Product Name": "Sample internal hub",
            "USB Vendor Name": "Sample manufacturer", "USBSpeed": 3, "USBPortType": 2, "bDeviceClass": 9]))
        return ConnectionSnapshot(usb: devices,
            thunderbolt: [ThunderboltDevice(id: 12, properties: ["Device Name": "Sample dock", "Vendor Name": "Sample manufacturer"])])
    }

    public static func history(endingAt date: Date = Date()) -> WattageHistory {
        var history = WattageHistory()
        for index in 0..<20 {
            let time = date.addingTimeInterval(Double(index - 19) * 15)
            if index == 10 {
                history.append(WattageSample(date: time, watts: nil, supply: .unknown, failure: "Sample read unavailable."))
            } else {
                history.append(WattageSample(date: time, watts: index < 10 ? 100 : 65, supply: .external))
            }
        }
        return history
    }
}

public struct SystemReadings: Sendable {
    public let power: Result<PowerSnapshot, any Error>
    public let connections: Result<ConnectionSnapshot, any Error>
    public let date: Date
    public init(power: Result<PowerSnapshot, any Error>, connections: Result<ConnectionSnapshot, any Error>, date: Date = Date()) {
        self.power = power; self.connections = connections; self.date = date
    }
    public static func load(
        powerReader: @escaping @Sendable () throws -> PowerSnapshot = { try PowerReader.read() },
        connectionReader: @escaping @Sendable () throws -> ConnectionSnapshot = { try ConnectionReader.read() }
    ) async -> SystemReadings {
        await Task.detached(priority: .utility) {
            SystemReadings(power: Result { try powerReader() }, connections: Result { try connectionReader() })
        }.value
    }
}
