import Foundation
import IOKit
import IOKit.ps

public enum SystemReadError: LocalizedError {
    case powerSources, sourceDescription, registry(operation: String, code: kern_return_t)
    public var errorDescription: String? {
        switch self {
        case .powerSources: return "macOS could not provide power information."
        case .sourceDescription: return "macOS could not describe a power source."
        case .registry(let operation, let code): return "\(operation) failed (IOKit \(code))."
        }
    }
}

public enum RegistryReader {
    public struct Entry {
        public let id: UInt64
        public let properties: [String: Any]
        public let parent: [String: Any]
        public let interfaceClasses: Set<Int>?
    }

    /// Read-only registry queries do not open a USB user client or claim a device.
    public static func entries(className: String, readParent: Bool = false) throws -> [Entry] {
        guard let match = IOServiceMatching(className) else {
            throw SystemReadError.registry(operation: "Device matching", code: KERN_FAILURE)
        }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
        guard status == KERN_SUCCESS else { throw SystemReadError.registry(operation: "\(className) enumeration", code: status) }
        defer { IOObjectRelease(iterator) }
        var results: [Entry] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            var identifier: UInt64 = 0
            let idStatus = IORegistryEntryGetRegistryEntryID(entry, &identifier)
            guard idStatus == KERN_SUCCESS else { throw SystemReadError.registry(operation: "Device identifier", code: idStatus) }
            let properties = try copyProperties(entry)
            var parentProperties: [String: Any] = [:]
            if readParent {
                var parent: io_registry_entry_t = 0
                if IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS {
                    defer { IOObjectRelease(parent) }
                    parentProperties = try copyProperties(parent)
                }
            }
            results.append(Entry(id: identifier, properties: properties, parent: parentProperties, interfaceClasses: className == "IOUSBHostDevice" ? interfaceClasses(entry) : nil))
        }
        return results
    }

    /// Composite hub classes can live on child interfaces. Unknown enumeration disables the advisory.
    private static func interfaceClasses(_ entry: io_registry_entry_t) -> Set<Int>? {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(children) }
        var classes: Set<Int> = []
        while true {
            let child = IOIteratorNext(children)
            if child == 0 { break }
            defer { IOObjectRelease(child) }
            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0 {
                guard let properties = try? copyProperties(child),
                      let code = ReadValue.nonnegativeInt(properties["bInterfaceClass"]) else { return nil }
                classes.insert(code)
            }
        }
        return classes
    }

    private static func copyProperties(_ entry: io_registry_entry_t) throws -> [String: Any] {
        var properties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let properties else { throw SystemReadError.registry(operation: "Device properties", code: status) }
        return properties.takeRetainedValue() as NSDictionary as? [String: Any] ?? [:]
    }
}

public enum PowerReader {
    public static func read() throws -> PowerSnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            throw SystemReadError.powerSources
        }
        let supply = PowerSupply(systemValue: IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?)
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as NSDictionary? as? [String: Any]
        var registry: [String: Any] = [:]
        var registryError: String?
        do { registry = try RegistryReader.entries(className: "AppleSmartBattery").first?.properties ?? [:] }
        catch { registryError = error.localizedDescription }
        var battery: BatteryReading?
        for handle in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, handle)?.takeUnretainedValue() as NSDictionary? as? [String: Any] else {
                throw SystemReadError.sourceDescription
            }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                battery = BatteryReading(source: description, registry: registry)
                break
            }
        }
        return PowerSnapshot(supply: supply, adapter: adapter.map(AdapterReading.init), battery: battery, sourceCount: sources.count, batteryDetailError: registryError, inputWatts: PowerTelemetry.inputWatts(registry["PowerTelemetryData"] as? [String: Any] ?? [:]))
    }
}

public enum ConnectionReader {
    public static func readUSB() throws -> [USBDevice] {
        try RegistryReader.entries(className: "IOUSBHostDevice", readParent: true)
            .map { USBDevice(id: $0.id, properties: $0.properties, parent: $0.parent, interfaceClasses: $0.interfaceClasses) }
            .sorted { $0.product.localizedStandardCompare($1.product) == .orderedAscending }
    }
    public static func read() throws -> ConnectionSnapshot {
        let usb = try readUSB()
        var thunderbolt: [ThunderboltDevice] = []
        var warnings: [String] = []
        do {
            thunderbolt = try RegistryReader.entries(className: "IOThunderboltDevice")
                .filter { ReadValue.text($0.properties["Device Name"]) != nil || ReadValue.text($0.properties["device_name"]) != nil }
                .map { ThunderboltDevice(id: $0.id, properties: $0.properties) }
        } catch { warnings.append(error.localizedDescription) }
        return ConnectionSnapshot(usb: usb, thunderbolt: thunderbolt, warnings: warnings)
    }
}
