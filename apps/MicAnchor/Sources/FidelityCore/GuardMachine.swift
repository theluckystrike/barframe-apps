import Foundation

/// Device IDs can be reused. Verify the UID before confirming a write.
public struct InputIdentity: Equatable, Sendable {
    public let id: UInt32
    public let uid: String
    public init(_ device: AudioDevice) { id = device.id; uid = device.uid }
}

public struct GuardSnapshot: Equatable, Sendable {
    public let devices: [AudioDevice]
    public let input: UInt32
    public let lidClosed: Bool
    public let unreadableIDs: [UInt32]
    public init(devices: [AudioDevice], input: UInt32, lidClosed: Bool, unreadableIDs: [UInt32] = []) {
        self.devices = devices; self.input = input; self.lidClosed = lidClosed
        self.unreadableIDs = unreadableIDs
    }
}

public struct SwitchRequest: Equatable, Sendable {
    public let target: InputIdentity
    public let recordHistory: Bool
}

public enum GuardState: Equatable, Sendable {
    case idle
    case switching(SwitchRequest, deadline: Date, attempt: Int)
    case paused(until: Date)

    public var deadline: Date? {
        switch self {
        case .idle: return nil
        case .switching(_, let deadline, _): return deadline
        case .paused(let until): return until
        }
    }
    public var hasPendingWrite: Bool {
        if case .switching = self { return true }
        return false
    }
}

public enum GuardEvent: Equatable, Sendable {
    case inputChanged(UInt32, enforce: Bool)
    case timerFired
    case userToggle(Bool)
    case devicesChanged(GuardSnapshot, enforce: Bool)
    case userPreferred(String?)
    case userPriorities([String])
    case clearHistory
    case userAllowance(Date?)
    case requestSwitch(target: UInt32, original: UInt32, recordHistory: Bool)
    case writeFailed(String)
    case inventoryFailed(String)
}

public enum GuardEffect: Equatable, Sendable {
    case setInput(InputIdentity)
    case requestRejected
}

/// The adapter supplies fresh hardware observations before deadline events.
/// A pause contains no target, outstanding request, or recovery intent.
public struct GuardMachine {
    public static let maximumWrites = 3
    public static let writeWindow: TimeInterval = 30
    public static let confirmationWindow: TimeInterval = 2
    public static let pauseDuration: TimeInterval = 300
    public private(set) var state: GuardState
    public private(set) var settings: GuardSettings
    public private(set) var snapshot = GuardSnapshot(devices: [], input: 0, lidClosed: false)
    public private(set) var error: String?
    public private(set) var recentIntervention = false
    public private(set) var lastMovedName: String?
    public private(set) var writeTimes: [Date] = []
    private var failures = 0
    private var pendingReason = "Requested input change"
    private var interventionExpires: Date?

    public init(settings: GuardSettings = GuardSettings()) {
        self.settings = settings
        state = settings.pausedUntil.map { .paused(until: $0) } ?? .idle
    }

    public var nextDeadline: Date? {
        [state.deadline, interventionExpires, settings.bluetoothAllowedUntil].compactMap { $0 }.min()
    }

    @discardableResult public mutating func send(_ event: GuardEvent, at date: Date) -> [GuardEffect] {
        let freshObservation: Bool
        switch event {
        case .devicesChanged(let value, _): snapshot = value; error = nil; freshObservation = true
        case .inputChanged(let input, _):
            snapshot = GuardSnapshot(devices: snapshot.devices, input: input, lidClosed: snapshot.lidClosed,
                                     unreadableIDs: snapshot.unreadableIDs)
            freshObservation = true
        default: freshObservation = false
        }
        if settings.bluetoothAllowedUntil.map({ $0 <= date }) == true { settings.bluetoothAllowedUntil = nil }
        if interventionExpires.map({ $0 <= date }) == true {
            recentIntervention = false; lastMovedName = nil; interventionExpires = nil
        }
        if case .switching(let request, _, _) = state,
           available(request.target) == nil, !snapshot.unreadableIDs.contains(request.target.id) {
            state = .idle; error = nil
        }
        // Confirm a fresh target observation first, including an observation at the deadline.
        if freshObservation, case .switching(let request, _, _) = state,
           snapshot.input == request.target.id, available(request.target) != nil {
            confirm(request, at: date)
        }
        expireState(at: date)

        switch event {
        case .devicesChanged(_, let enforce), .inputChanged(_, let enforce):
            return enforce ? protect(at: date) : []
        case .timerFired: return [] // Cached observations cannot confirm writes.
        case .userToggle(let enabled):
            settings.enabled = enabled
            cancelPending(at: date)
            return protect(at: date)
        case .clearHistory:
            settings.history = []; settings.interventions = 0; settings.lastIntervention = nil
            return []
        case .userPriorities(let uids):
            settings.priorityUIDs = Array(NSOrderedSet(array: uids)) as? [String] ?? []
            settings.preferredUID = settings.priorityUIDs.first
            cancelPending(at: date)
            return protect(at: date)
        case .userPreferred(let uid):
            settings.priorityUIDs = uid.map { [$0] } ?? []
            settings.preferredUID = uid
            cancelPending(at: date)
            return protect(at: date)
        case .userAllowance(let until):
            settings.bluetoothAllowedUntil = until
            return protect(at: date)
        case .requestSwitch(let target, let original, let recordHistory):
            guard case .idle = state, let destination = device(id: target), device(id: original) != nil,
                  destination.isAvailableInput(lidClosed: snapshot.lidClosed) else { return [.requestRejected] }
            return beginSwitch(SwitchRequest(target: InputIdentity(destination), recordHistory: recordHistory), at: date)
        case .writeFailed(let message):
            error = message
            if case .switching = state {
                state = .idle
                failures = min(Self.maximumWrites, failures + 1)
                if failures == Self.maximumWrites { pause(at: date) }
            }
            return []
        case .inventoryFailed(let message): error = message; return []
        }
    }

    private func device(id: UInt32) -> AudioDevice? { snapshot.devices.first { $0.id == id } }
    private func available(_ identity: InputIdentity) -> AudioDevice? {
        snapshot.devices.first {
            $0.id == identity.id && $0.uid == identity.uid && $0.isAvailableInput(lidClosed: snapshot.lidClosed)
        }
    }
    private mutating func expireState(at date: Date) {
        guard let deadline = state.deadline, deadline <= date else { return }
        switch state {
        case .switching:
            pause(at: date)
            error = "Input did not settle. Guard paused for 5 minutes."
        case .paused:
            state = .idle; settings.pausedUntil = nil; failures = 0; error = nil
        case .idle: break
        }
    }
    private mutating func cancelPending(at date: Date) {
        if case .switching = state { pause(at: date); error = nil }
    }
    private mutating func protect(at date: Date) -> [GuardEffect] {
        guard case .idle = state,
              case .setInput(let id) = GuardDecision.action(devices: snapshot.devices, currentInput: snapshot.input,
                  preferredUID: GuardDecision.preferredDevice(in: snapshot.devices, priorities: settings.priorityUIDs.isEmpty ? settings.preferredUID.map { [$0] } ?? [] : settings.priorityUIDs, lidClosed: snapshot.lidClosed)?.uid, enabled: settings.enabled, lidClosed: snapshot.lidClosed,
                  now: date, bluetoothAllowedUntil: settings.bluetoothAllowedUntil, pausedUntil: settings.pausedUntil),
              let target = device(id: id) else { return [] }
        return beginSwitch(SwitchRequest(target: InputIdentity(target), recordHistory: true), at: date)
    }
    private mutating func pause(at date: Date) {
        let until = date.addingTimeInterval(Self.pauseDuration)
        state = .paused(until: until); settings.pausedUntil = until
    }
    private mutating func beginSwitch(_ request: SwitchRequest, at date: Date) -> [GuardEffect] {
        writeTimes.removeAll { date.timeIntervalSince($0) > Self.writeWindow }
        guard writeTimes.count < Self.maximumWrites else { pause(at: date); return [] }
        pendingReason = device(id: snapshot.input)?.transport.isBluetooth == true ? "Bluetooth input replaced" :
            device(id: snapshot.input)?.isAvailableInput(lidClosed: snapshot.lidClosed) == false ? "Unavailable input replaced" : "Requested input change"
        writeTimes.append(date)
        state = .switching(request, deadline: date.addingTimeInterval(Self.confirmationWindow), attempt: writeTimes.count)
        // Confirm only the adapter's read after the setter, including a no-op selftest write.
        return [.setInput(request.target)]
    }
    private mutating func confirm(_ request: SwitchRequest, at date: Date) {
        state = .idle; failures = 0; error = nil
        if request.recordHistory {
            settings.recordIntervention(at: date)
            settings.history.append(SwitchHistory(date: date, target: available(request.target)?.name ?? "Available input", reason: pendingReason))
            settings.history = Array(settings.history.suffix(20))
            recentIntervention = true; lastMovedName = available(request.target)?.name
            interventionExpires = date.addingTimeInterval(10)
        }
    }
}
