import Foundation

public enum Transport: String, Codable, Sendable, CaseIterable {
    case bluetooth = "Bluetooth", bluetoothLE = "Bluetooth LE", builtIn = "Built-in", usb = "USB"
    case thunderbolt = "Thunderbolt", pci = "PCI", firewire = "FireWire", avb = "AVB"
    case hdmi = "HDMI", displayPort = "DisplayPort", continuity = "Continuity", airPlay = "AirPlay"
    case virtual = "Virtual / aggregate", other = "Other"

    public var isBluetooth: Bool { self == .bluetooth || self == .bluetoothLE }
    public var automaticRank: Int? {
        switch self {
        case .builtIn: return 0
        case .usb: return 1
        case .thunderbolt, .pci, .firewire, .avb, .hdmi, .displayPort: return 2
        default: return nil
        }
    }
    public static func classify(_ code: UInt32) -> Transport {
        switch code {
        case 0x626c7565: return .bluetooth
        case 0x626c6561: return .bluetoothLE
        case 0x626c746e: return .builtIn
        case 0x75736220: return .usb
        case 0x7468756e: return .thunderbolt
        case 0x70636920: return .pci
        case 0x31333934: return .firewire
        case 0x65617662: return .avb
        case 0x68646d69: return .hdmi
        case 0x64707274: return .displayPort
        case 0x63637764, 0x6363776c: return .continuity
        case 0x61697270: return .airPlay
        case 0x76697274, 0x67727570, 0x66677270: return .virtual
        default: return .other
        }
    }
}

public struct AudioDevice: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let transport: Transport
    public let inputChannels: Int
    public let outputChannels: Int
    public let isAlive: Bool
    public let dataSourceAvailable: Bool
    public init(id: UInt32, uid: String, name: String, transport: Transport,
                inputChannels: Int, outputChannels: Int, isAlive: Bool = true, dataSourceAvailable: Bool = true) {
        self.id = id; self.uid = uid; self.name = name; self.transport = transport
        self.inputChannels = inputChannels; self.outputChannels = outputChannels
        self.isAlive = isAlive; self.dataSourceAvailable = dataSourceAvailable
    }
    public func isAvailableInput(lidClosed: Bool = false) -> Bool {
        inputChannels > 0 && isAlive && dataSourceAvailable && !(lidClosed && transport == .builtIn)
    }
    public var isSafeInput: Bool {
        let loopback = ["blackhole", "loopback", "soundflower", "vb-cable"].contains { name.lowercased().contains($0) }
        return isAvailableInput() && !transport.isBluetooth
            && transport != .virtual && !loopback
    }
}

public enum GuardAction: Equatable, Sendable { case none, setInput(UInt32), noSafeInput }

public enum GuardDecision {
    public static func preferredDevice(in devices: [AudioDevice], priorities: [String], lidClosed: Bool = false) -> AudioDevice? {
        for uid in priorities {
            if let device = devices.first(where: { $0.uid == uid && $0.isSafeInput && $0.isAvailableInput(lidClosed: lidClosed) }) { return device }
        }
        return preferredDevice(in: devices, uid: nil, lidClosed: lidClosed)
    }
    public static func preferredDevice(in devices: [AudioDevice], uid: String?, lidClosed: Bool = false) -> AudioDevice? {
        let safe = devices.filter { $0.isSafeInput && $0.isAvailableInput(lidClosed: lidClosed) }
        if let chosen = safe.first(where: { $0.uid == uid }) { return chosen }
        return safe.filter { $0.transport.automaticRank != nil }.sorted {
            let a = $0.transport.automaticRank!, b = $1.transport.automaticRank!
            return a == b ? $0.uid < $1.uid : a < b
        }.first
    }
    public static func action(devices: [AudioDevice], currentInput: UInt32, preferredUID: String?, enabled: Bool,
                              lidClosed: Bool = false, now: Date = Date(), bluetoothAllowedUntil: Date? = nil,
                              pausedUntil: Date? = nil) -> GuardAction {
        guard enabled, bluetoothAllowedUntil.map({ $0 > now }) != true, pausedUntil.map({ $0 > now }) != true,
              let current = devices.first(where: { $0.id == currentInput }) else { return .none }
        let unavailable = !current.isAvailableInput(lidClosed: lidClosed)
        guard current.transport.isBluetooth || unavailable else { return .none }
        guard let target = preferredDevice(in: devices, uid: preferredUID, lidClosed: lidClosed) else { return .noSafeInput }
        return .setInput(target.id)
    }
}

public struct InterventionLimiter {
    public private(set) var timestamps: [Date] = []
    public private(set) var pausedUntil: Date?
    public init() {}
    // Reserve before a setter call. Include rejected and unconfirmed calls in the budget.
    public mutating func reserveAttempt(at date: Date) -> Bool {
        guard pausedUntil.map({ $0 > date }) != true else { return false }
        timestamps = timestamps.filter { date.timeIntervalSince($0) <= 30 && $0 <= date }
        guard timestamps.count < 3 else {
            pausedUntil = date.addingTimeInterval(300)
            return false
        }
        timestamps.append(date)
        return true
    }
    public mutating func record(at date: Date) {
        timestamps = timestamps.filter { date.timeIntervalSince($0) <= 30 && $0 <= date }
        timestamps.append(date)
        if timestamps.count > 3 { pausedUntil = date.addingTimeInterval(300) }
    }
}

public struct SwitchHistory: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public let date: Date
    public let target: String
    public let reason: String
    public init(date: Date, target: String, reason: String) { self.date = date; self.target = target; self.reason = reason }
}

public struct GuardSettings: Equatable {
    public var enabled: Bool
    public var preferredUID: String?
    public var priorityUIDs: [String] = []
    public var history: [SwitchHistory] = []
    public var interventions: Int
    public var lastIntervention: Date?
    public var bluetoothAllowedUntil: Date?
    public var pausedUntil: Date?
    public init(enabled: Bool = true, preferredUID: String? = nil, interventions: Int = 0,
                lastIntervention: Date? = nil, bluetoothAllowedUntil: Date? = nil, pausedUntil: Date? = nil) {
        self.enabled = enabled; self.preferredUID = preferredUID; self.interventions = max(0, interventions)
        self.lastIntervention = lastIntervention; self.bluetoothAllowedUntil = bluetoothAllowedUntil; self.pausedUntil = pausedUntil
    }
    public mutating func recordIntervention(at date: Date) {
        if interventions < Int.max { interventions += 1 }
        lastIntervention = date
    }
}

public struct SettingsStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> GuardSettings {
        var settings = GuardSettings(enabled: defaults.object(forKey: "guardEnabled") as? Bool ?? true,
                      preferredUID: defaults.string(forKey: "preferredInputUID"),
                      interventions: defaults.integer(forKey: "interventions"),
                      lastIntervention: defaults.object(forKey: "lastIntervention") as? Date,
                      bluetoothAllowedUntil: defaults.object(forKey: "bluetoothAllowedUntil") as? Date,
                      pausedUntil: defaults.object(forKey: "pausedUntil") as? Date)
        settings.priorityUIDs = defaults.stringArray(forKey: "priorityUIDs") ?? settings.preferredUID.map { [$0] } ?? []
        if let data = defaults.data(forKey: "switchHistory"), let items = try? JSONDecoder().decode([SwitchHistory].self, from: data) { settings.history = Array(items.suffix(20)) }
        return settings
    }
    public func save(_ settings: GuardSettings) {
        defaults.set(settings.priorityUIDs, forKey: "priorityUIDs")
        defaults.set(try? JSONEncoder().encode(settings.history), forKey: "switchHistory")
        defaults.set(settings.enabled, forKey: "guardEnabled")
        defaults.set(settings.preferredUID, forKey: "preferredInputUID")
        defaults.set(settings.interventions, forKey: "interventions")
        defaults.set(settings.lastIntervention, forKey: "lastIntervention")
        defaults.set(settings.bluetoothAllowedUntil, forKey: "bluetoothAllowedUntil")
        defaults.set(settings.pausedUntil, forKey: "pausedUntil")
    }
}

public enum ScreenshotPrivacy {
    public static func deviceName(_ name: String) -> String {
        name.replacingOccurrences(of: "^.+[’']s\\s+", with: "Your ", options: .regularExpression)
    }
}
