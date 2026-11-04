import Foundation
import CoreFoundation

/// An absent reading is never converted into a zero reading.
public enum ReadValue {
    public static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    public static func nonnegativeInt(_ value: Any?) -> Int? {
        guard let number = number(value), number >= 0, number < Double(Int.max), number.rounded() == number else { return nil }
        return Int(number)
    }

    public static func positive(_ value: Any?) -> Double? {
        guard let number = number(value), number > 0 else { return nil }
        return number
    }

    /// Preserve signed battery current, including IOKit's UInt64 two's-complement encoding.
    public static func signedCurrent(_ value: Any?) -> Double? {
        guard let raw = value as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID() else { return nil }
        let kind = String(cString: raw.objCType)
        let current = kind == "Q" ? Double(Int64(bitPattern: raw.uint64Value)) : raw.doubleValue
        guard current.isFinite, current.rounded() == current, abs(current) <= 100_000 else { return nil }
        return current
    }

    public static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

public struct AdapterReading: Equatable, Sendable {
    public let watts: Double?
    public let name: String?
    public let milliamps: Int?
    public let volts: Double?

    public init(properties: [String: Any]) {
        watts = ReadValue.positive(properties["Watts"])
        name = ReadValue.text(properties["Name"]) ?? ReadValue.text(properties["Description"])
        milliamps = ReadValue.nonnegativeInt(properties["Current"])
        volts = ReadValue.positive(properties["AdapterVoltage"]).map { $0 / 1000 }
    }
}

public struct BatteryReading: Equatable, Sendable {
    public let name: String
    public let chargePercent: Int?
    public let isCharging: Bool
    public let isCharged: Bool
    public let health: String?
    public let cycleCount: Int?
    public let maximumCapacityPercent: Int?
    public let fullChargeCapacity: Double?
    public let designCapacity: Double?
    public let signedWatts: Double?
    public let temperatureCelsius: Double?
    public let remainingMinutes: Int?

    public init(source: [String: Any], registry: [String: Any] = [:]) {
        name = ReadValue.text(source["Name"]) ?? "Internal battery"
        if let current = ReadValue.number(source["Current Capacity"]), current >= 0,
           let maximum = ReadValue.positive(source["Max Capacity"]), current <= maximum {
            chargePercent = Int((current / maximum * 100).rounded())
        } else { chargePercent = nil }
        isCharging = source["Is Charging"] as? Bool ?? false
        isCharged = source["Is Charged"] as? Bool ?? false
        health = ReadValue.text(source["BatteryHealthCondition"]) ?? ReadValue.text(source["BatteryHealth"])
        cycleCount = ReadValue.nonnegativeInt(source["Cycle Count"]) ?? ReadValue.nonnegativeInt(source["CycleCount"]) ?? ReadValue.nonnegativeInt(registry["CycleCount"])
        fullChargeCapacity = ReadValue.positive(registry["AppleRawMaxCapacity"]) ?? ReadValue.positive(registry["NominalChargeCapacity"])
        designCapacity = ReadValue.positive(registry["DesignCapacity"])
        signedWatts = PowerTelemetry.watts(millivolts: ReadValue.positive(registry["Voltage"]),
            milliamps: ReadValue.signedCurrent(registry["InstantAmperage"]) ?? ReadValue.signedCurrent(registry["Amperage"]))
        temperatureCelsius = ReadValue.number(registry["Temperature"]).map { $0 / 10 - 273.15 }.flatMap { (-20...100).contains($0) ? $0 : nil }
        remainingMinutes = ReadValue.nonnegativeInt(source[isCharging ? "Time to Full Charge" : "Time to Empty"]).flatMap { $0 == 65535 ? nil : $0 }
        // Registry capacities must share units. IOPS Max Capacity can instead be a normalized percentage.
        if let full = fullChargeCapacity,
           let design = designCapacity, full / design <= 1.2 {
            maximumCapacityPercent = Int((full / design * 100).rounded())
        } else { maximumCapacityPercent = nil }
    }

    public var chargingState: String {
        isCharging ? "Charging" : (isCharged ? "Fully charged" : "Not charging")
    }
}

public enum PowerSupply: String, Codable, Sendable {
    case battery, external, ups, unknown
    public init(systemValue: String?) {
        switch systemValue {
        case "Battery Power": self = .battery
        case "AC Power": self = .external
        case "UPS Power": self = .ups
        default: self = .unknown
        }
    }
    public var label: String {
        switch self {
        case .battery: return "On battery"
        case .external: return "External power"
        case .ups: return "UPS power"
        case .unknown: return "Power source unavailable"
        }
    }
}

public struct PowerSnapshot: Sendable {
    public let date: Date
    public let supply: PowerSupply
    public let adapter: AdapterReading?
    public let battery: BatteryReading?
    public let sourceCount: Int
    public let batteryDetailError: String?
    public let inputWatts: Double?

    public init(date: Date = Date(), supply: PowerSupply, adapter: AdapterReading?, battery: BatteryReading?, sourceCount: Int, batteryDetailError: String? = nil, inputWatts: Double? = nil) {
        self.date = date; self.supply = supply; self.adapter = adapter
        self.battery = battery; self.sourceCount = sourceCount; self.batteryDetailError = batteryDetailError
        self.inputWatts = inputWatts.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

public enum USBSpeed {
    /// IOKit IOUSBHostFamilyDefinitions.h: XHCI speed IDs, not bcdUSB protocol versions.
    public static func label(code: Int?) -> String {
        switch code {
        case 0: return "Not connected"
        case 1: return "12 Mb/s"
        case 2: return "1.5 Mb/s"
        case 3: return "480 Mb/s"
        case 4: return "5 Gb/s"
        case 5: return "10 Gb/s"
        case 6: return "20 Gb/s"
        default: return "Unavailable"
        }
    }
}

public struct USBDevice: Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let product: String
    public let vendor: String
    public let speedCode: Int?
    public let availableMilliamps: Int?
    public let allocatedMilliamps: Int?
    public let isBuiltIn: Bool
    public let location: String?
    public let portType: String
    public let usbVersion: Int?
    public let deviceClass: Int?
    public let interfaceClasses: Set<Int>?

    public init(id: UInt64, properties: [String: Any], parent: [String: Any] = [:], interfaceClasses: Set<Int>? = []) {
        self.id = id
        usbVersion = ReadValue.nonnegativeInt(properties["bcdUSB"])
        deviceClass = ReadValue.nonnegativeInt(properties["bDeviceClass"])
        self.interfaceClasses = interfaceClasses
        product = ReadValue.text(properties["USB Product Name"]) ?? ReadValue.text(properties["kUSBProductString"]) ?? "USB device"
        if let label = ReadValue.text(properties["USB Vendor Name"]) ?? ReadValue.text(properties["kUSBVendorString"]) {
            vendor = label
        } else if let number = ReadValue.nonnegativeInt(properties["idVendor"]), number <= 65535 {
            vendor = String(format: "Vendor 0x%04X", number)
        } else { vendor = "Vendor unavailable" }
        speedCode = ReadValue.nonnegativeInt(properties["USBSpeed"])
        availableMilliamps = ReadValue.nonnegativeInt(properties["kUSBWakePortCurrentLimit"]) ?? ReadValue.nonnegativeInt(parent["kUSBWakePortCurrentLimit"]) ?? ReadValue.nonnegativeInt(properties["AAPL,current-available"])
        allocatedMilliamps = ReadValue.nonnegativeInt(properties["UsbPowerSinkAllocation"]) ?? ReadValue.nonnegativeInt(parent["kUSBBusCurrentAllocation"])
        let type = ReadValue.nonnegativeInt(properties["USBPortType"]) ?? ReadValue.nonnegativeInt(parent["USBPortType"])
        isBuiltIn = ["Built-In", "built-in", "non-removable"].contains { key in
            properties[key] as? Bool == true || (ReadValue.nonnegativeInt(properties[key]) ?? 0) > 0
        } || ReadValue.text(properties["non-removable"])?.lowercased() == "yes" || type == 2 || type == 1
        portType = type == 5 ? "USB-C" : "USB"
        if let raw = ReadValue.nonnegativeInt(properties["locationID"]), raw <= Int(UInt32.max) {
            location = String(format: "0x%08X", raw)
        } else { location = nil }
    }
    public var speedLabel: String { USBSpeed.label(code: speedCode) }
    /// Require positive USB 3 evidence; exclude hubs, built-in and unknown classes.
    public var checkCable: Bool {
        guard !isBuiltIn, let deviceClass, deviceClass != 9, let interfaceClasses, !interfaceClasses.contains(9),
              let speedCode, (1...3).contains(speedCode), let usbVersion else { return false }
        return usbVersion >= 0x0300 && usbVersion <= 0x0499
    }
}

public struct ThunderboltDevice: Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let name: String
    public let vendor: String?
    public init(id: UInt64, properties: [String: Any]) {
        self.id = id
        name = ReadValue.text(properties["Device Name"]) ?? ReadValue.text(properties["device_name"]) ?? "Thunderbolt device"
        vendor = ReadValue.text(properties["Vendor Name"]) ?? ReadValue.text(properties["vendor_name"])
    }
}

public struct ConnectionSnapshot: Sendable {
    public let usb: [USBDevice]
    public let thunderbolt: [ThunderboltDevice]
    public let warnings: [String]
    public init(usb: [USBDevice], thunderbolt: [ThunderboltDevice], warnings: [String] = []) {
        self.usb = usb; self.thunderbolt = thunderbolt; self.warnings = warnings
    }
}

public enum ChargerVerdict: Equatable, Sendable {
    case notConfigured, disconnected, unavailable, sufficient, belowRating(actual: Double, rating: Double)
    public static func evaluate(supply: PowerSupply, watts: Double?, rating: Double) -> ChargerVerdict {
        guard rating.isFinite, rating > 0 else { return .notConfigured }
        guard supply == .external else { return .disconnected }
        guard let watts, watts.isFinite, watts > 0 else { return .unavailable }
        return watts < rating ? .belowRating(actual: watts, rating: rating) : .sufficient
    }
    public var isWarning: Bool {
        if case .belowRating = self { return true }
        return false
    }
}
