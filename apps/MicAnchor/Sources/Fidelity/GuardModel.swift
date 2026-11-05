import SwiftUI
import FidelityCore

@MainActor final class GuardModel: ObservableObject {
    static let shared = GuardModel()
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var inputID: UInt32 = 0
    @Published private(set) var outputID: UInt32 = 0
    @Published private(set) var settings: GuardSettings
    @Published private(set) var error: String?
    @Published private(set) var recentIntervention = false
    @Published private(set) var lidClosed: Bool?
    @Published private(set) var lastMovedName: String?
    @Published private(set) var needsIntroduction: Bool
    private let hardware: any AudioHardwareAccess
    private let now: () -> Date
    private let scheduleEvents: Bool
    private let store: SettingsStore
    private let defaults: UserDefaults
    private var machine: GuardMachine
    private var availabilityTimer: Timer?
    private var retryWork: DispatchWorkItem?
    private var deadlineWork: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var started = false
    private let worker = AudioWorker()
    private var reading = false
    private var listenerError: String?

    init(hardware: any AudioHardwareAccess = AudioHardware(), defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init, scheduleEvents: Bool = true) {
        self.now = now; self.scheduleEvents = scheduleEvents
        self.hardware = hardware; self.defaults = defaults
        store = SettingsStore(defaults: defaults)
        let loaded = store.load()
        settings = loaded
        machine = GuardMachine(settings: loaded)
        needsIntroduction = !defaults.bool(forKey: "introductionSeen")
    }

    var preferred: AudioDevice? { GuardDecision.preferredDevice(in: devices, priorities: settings.priorityUIDs.isEmpty ? settings.preferredUID.map { [$0] } ?? [] : settings.priorityUIDs, lidClosed: lidClosed == true) }
    var safeInputs: [AudioDevice] {
        devices.filter(\.isSafeInput).sorted {
            let a = $0.transport.automaticRank ?? 3, b = $1.transport.automaticRank ?? 3
            return a == b ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : a < b
        }
    }
    var currentInput: AudioDevice? { devices.first { $0.id == inputID } }
    var currentOutput: AudioDevice? { devices.first { $0.id == outputID } }
    var bluetoothAllowed: Bool { settings.bluetoothAllowedUntil.map { $0 > now() } ?? false }
    var loopPaused: Bool { settings.pausedUntil.map { $0 > now() } ?? false }
    var microphoneProtectionNote: String {
        guard bluetoothAllowed else {
            if !settings.enabled { return "Guard is off. Turn Guard on to restore microphone protection." }
            if loopPaused { return "Guard is paused until \(settings.pausedUntil!.formatted(date: .omitted, time: .shortened)). Microphone protection resumes then." }
            if error != nil { return "Microphone protection is waiting for audio devices. Use Retry / Refresh." }
            if preferred == nil { return "Microphone protection needs an available built-in or wired microphone." }
            return "Bluetooth input switches back to this microphone."
        }
        let expiry = settings.bluetoothAllowedUntil!.formatted(date: .omitted, time: .shortened)
        if !settings.enabled || loopPaused {
            var note = "Bluetooth mic allowed until \(expiry). Select Resume Guard to end the allowance."
            if !settings.enabled { note += " Turn Guard on." }
            if loopPaused {
                note += " The input-change pause ends at \(settings.pausedUntil!.formatted(date: .omitted, time: .shortened))."
            }
            return note
        }
        return "Guard is paused until \(expiry). Select Resume Guard to restore protection."
    }
    var glyph: String { recentIntervention ? "checkmark.shield.fill" : settings.enabled && !bluetoothAllowed && !loopPaused ? "shield.fill" : "shield.slash" }
    var status: String {
        if !settings.enabled { return "Guard is off" }
        if loopPaused { return "Guard paused for 5 minutes" }
        if error != nil { return "Audio devices changed — retrying" }
        if bluetoothAllowed { return "Bluetooth mic allowed" }
        if preferred == nil { return "Connect a wired microphone" }
        return recentIntervention ? "Input restored" : "Guard is on"
    }
    var availabilityNote: String? {
        if loopPaused { return "Input changes did not settle, or another app keeps selecting the microphone. Guard resumes at \(settings.pausedUntil!.formatted(date: .omitted, time: .shortened))." }
        if lidClosed == true { return "Lid closed: built-in mic is off. Use a wired microphone." }
        if devices.contains(where: { $0.transport == .builtIn && $0.inputChannels > 0 && !$0.isSafeInput }) {
            return "Built-in mic unavailable. Guard uses the next wired microphone."
        }
        if lidClosed == nil { return "Lid state unavailable. Guard checks microphone availability reported by the system." }
        return nil
    }

    func start() {
        guard !started else { return }
        started = true
        do { try hardware.startListening { [weak self] in self?.refresh(enforce: true) } }
        catch { listenerError = error.localizedDescription }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(enforce: true) }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(enforce: true) }
        }
        if scheduleEvents {
            availabilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh(enforce: true) }
            }
        }
        refresh(enforce: true)
        scheduleDeadline()
    }

    func stop() {
        worker.cancel(); reading = false
        availabilityTimer?.invalidate(); availabilityTimer = nil
        retryWork?.cancel(); deadlineWork?.cancel()
        hardware.stopListening()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        wakeObserver = nil; screenObserver = nil; started = false
    }

    func refresh(enforce: Bool, attempt: Int = 0) {
        retryWork?.cancel()
        if scheduleEvents {
            guard !reading else { return }
            reading = true
            let hardware = hardware
            worker.submit({
                let inventory = try hardware.devices()
                return (inventory, try hardware.defaultInput(), try hardware.defaultOutput(), hardware.lidClosed(), hardware.skippedIDs)
            }) { [weak self] result in
                guard let self else { return }
                self.reading = false
                switch result {
                case .success(let value):
                    self.devices = value.0; self.inputID = value.1; self.outputID = value.2; self.lidClosed = value.3
                    self.feed(.devicesChanged(GuardSnapshot(devices: value.0, input: value.1, lidClosed: value.3 == true, unreadableIDs: value.4), enforce: enforce))
                    if !value.4.isEmpty { self.scheduleRetry(enforce: enforce, attempt: attempt) }
                case .failure(let error):
                    self.feed(.inventoryFailed(error.localizedDescription))
                    self.feed(.timerFired)
                    self.scheduleRetry(enforce: enforce, attempt: attempt)
                }
            }
            return
        }
        do {
            try readHardware(enforce: enforce)
            if !hardware.skippedIDs.isEmpty { scheduleRetry(enforce: enforce, attempt: attempt) }
        } catch {
            feed(.inventoryFailed(error.localizedDescription))
            scheduleRetry(enforce: enforce, attempt: attempt)
        }
    }

    private func readHardware(enforce: Bool) throws {
        let readDevices = try hardware.devices()
        let readInput = try hardware.defaultInput(), readOutput = try hardware.defaultOutput()
        devices = readDevices; inputID = readInput; outputID = readOutput; lidClosed = hardware.lidClosed()
        feed(.devicesChanged(GuardSnapshot(devices: readDevices, input: readInput, lidClosed: lidClosed == true,
                                          unreadableIDs: hardware.skippedIDs), enforce: enforce))
    }

    private func scheduleRetry(enforce: Bool, attempt: Int) {
        guard scheduleEvents, attempt < 3 else { return }
        let work = DispatchWorkItem { [weak self] in self?.refresh(enforce: enforce, attempt: attempt + 1) }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @discardableResult private func feed(_ event: GuardEvent) -> Error? {
        let effects = machine.send(event, at: now())
        publishMachine()
        let failure = execute(effects)
        scheduleDeadline()
        return failure
    }

    private func execute(_ effects: [GuardEffect]) -> Error? {
        var failure: Error?
        for effect in effects {
            switch effect {
            case .requestRejected:
                failure = HardwareError(operation: "Input change already pending or target unavailable", status: -1)
            case .setInput(let target):
                if scheduleEvents {
                    let hardware = hardware
                    worker.submit({
                        let inventory = try hardware.devices()
                        guard inventory.contains(where: { $0.id == target.id && $0.uid == target.uid && $0.isAvailableInput(lidClosed: hardware.lidClosed() == true) }) else {
                            throw HardwareError(operation: "Target disconnected", status: -1)
                        }
                        try hardware.setInput(target.id)
                        return try hardware.defaultInput()
                    }) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success(let id): self.inputID = id; self.feed(.inputChanged(id, enforce: false))
                        case .failure(let error): self.feed(.writeFailed(error.localizedDescription))
                        }
                    }
                    continue
                }
                do {
                    try hardware.setInput(target.id)
                } catch {
                    failure = error
                    feed(.writeFailed(error.localizedDescription))
                    continue
                }
                // Read-back is an observation, including no-op writes with no callback.
                do {
                    inputID = try hardware.defaultInput()
                    feed(.inputChanged(inputID, enforce: false))
                } catch {
                    failure = error
                    feed(.inventoryFailed(error.localizedDescription))
                }
            }
        }
        return failure
    }

    private func publishMachine() {
        if settings != machine.settings { settings = machine.settings; store.save(settings) }
        error = machine.error ?? listenerError
        recentIntervention = machine.recentIntervention
        lastMovedName = machine.lastMovedName
    }

    private func scheduleDeadline() {
        deadlineWork?.cancel()
        guard scheduleEvents, let deadline = machine.nextDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.processDeadline()
        }
        deadlineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, deadline.timeIntervalSince(now())), execute: work)
    }

    func processDeadline() {
        // Read hardware first. If reads fail, the timer still retires pending state.
        refresh(enforce: true)
        if !scheduleEvents { feed(.timerFired) }
    }

    // Exercise the same machine and setter with isolated SELFTEST history.
    func requestSwitch(to id: UInt32, original: UInt32, recordHistory: Bool = true) throws {
        try readHardware(enforce: false)
        if let failure = feed(.requestSwitch(target: id, original: original, recordHistory: recordHistory)) { throw failure }
    }

    func allowBluetoothForOneHour() {
        worker.cancel(); reading = false
        refresh(enforce: false)
        feed(.userAllowance(now().addingTimeInterval(3600)))
    }
    func resumeGuard() {
        refresh(enforce: false)
        feed(.userAllowance(nil))
    }
    func dismissIntroduction() { needsIntroduction = false; defaults.set(true, forKey: "introductionSeen") }
    func setEnabled(_ value: Bool) {
        worker.cancel(); reading = false
        refresh(enforce: false)
        feed(.userToggle(value))
    }
    func clearHistory() { feed(.clearHistory) }
    func setPriorities(_ uids: [String]) { worker.cancel(); reading = false; refresh(enforce: false); feed(.userPriorities(uids)) }
    func movePriority(_ uid: String) {
        var list = settings.priorityUIDs
        if let index = list.firstIndex(of: uid), index > 0 { list.swapAt(index, index - 1); setPriorities(list) }
    }
    func setPreferred(_ uid: String) {
        worker.cancel(); reading = false
        refresh(enforce: false)
        feed(.userPreferred(uid.isEmpty ? nil : uid))
    }
}
