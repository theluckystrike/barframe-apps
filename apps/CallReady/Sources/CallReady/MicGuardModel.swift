import SwiftUI
import CallCore

@MainActor final class GuardModel: ObservableObject {
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
    private var writing = false
    private var enforceAfterRead = false
    /// Completions wait until the current read, any requested enforcement and any input write are finished.
    private var completions: [() -> Void] = []
    private var listenerError: String?
    /// True while push-to-talk holds the current input. The guard reads devices but does not switch.
    private(set) var inputHeld = false

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
            if !settings.enabled { return "Bluetooth guard is off. Turn it on to put your preferred mic back when Bluetooth takes over." }
            if loopPaused { return "Bluetooth guard is paused until \(settings.pausedUntil!.formatted(date: .omitted, time: .shortened)). It resumes then." }
            if error != nil { return "Bluetooth guard is waiting for audio devices. It tries again by itself." }
            if preferred == nil { return "Bluetooth guard needs an available built-in or wired microphone." }
            return "When a Bluetooth mic takes over the input, or the input disappears, CallReady puts this microphone back. Other inputs you choose stay selected."
        }
        let expiry = settings.bluetoothAllowedUntil!.formatted(date: .omitted, time: .shortened)
        if !settings.enabled || loopPaused {
            var note = "Bluetooth mic allowed until \(expiry). Select Resume to end the allowance."
            if !settings.enabled { note += " Turn the Bluetooth guard on." }
            if loopPaused {
                note += " The input-change pause ends at \(settings.pausedUntil!.formatted(date: .omitted, time: .shortened))."
            }
            return note
        }
        return "Bluetooth guard is paused until \(expiry). Select Resume to turn it back on."
    }
    var glyph: String { recentIntervention ? "checkmark.shield.fill" : settings.enabled && !bluetoothAllowed && !loopPaused ? "shield.fill" : "shield.slash" }
    var status: String {
        if !settings.enabled { return "Bluetooth guard is off" }
        if loopPaused { return "Bluetooth guard paused for 5 minutes" }
        if error != nil { return "Audio devices changed — retrying" }
        if bluetoothAllowed { return "Bluetooth mic allowed" }
        if preferred == nil { return "Connect a wired microphone" }
        return recentIntervention ? "Input restored" : "Bluetooth guard is on"
    }
    var availabilityNote: String? {
        if loopPaused { return "Input changes did not settle, or another app keeps selecting the microphone. The Bluetooth guard resumes at \(settings.pausedUntil!.formatted(date: .omitted, time: .shortened))." }
        if lidClosed == true { return "Lid closed: built-in mic is off. Use a wired microphone." }
        if devices.contains(where: { $0.transport == .builtIn && $0.inputChannels > 0 && !$0.isSafeInput }) {
            return "Built-in mic unavailable. CallReady uses the next wired microphone."
        }
        if lidClosed == nil { return "Lid state unavailable. CallReady uses the microphone availability that macOS reports." }
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
        cancelWork()
        finishIfSettled()
        availabilityTimer?.invalidate(); availabilityTimer = nil
        retryWork?.cancel(); deadlineWork?.cancel()
        hardware.stopListening()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        wakeObserver = nil; screenObserver = nil; started = false
    }

    func refresh(enforce requested: Bool, attempt: Int = 0, completion: (() -> Void)? = nil) {
        let enforce = requested && !inputHeld
        retryWork?.cancel()
        if let completion { completions.append(completion) }
        if scheduleEvents {
            guard !reading else {
                if enforce { enforceAfterRead = true }
                return
            }
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
                    self.devices = Self.visible(value.0); self.inputID = value.1; self.outputID = value.2; self.lidClosed = value.3
                    self.feed(.devicesChanged(GuardSnapshot(devices: value.0, input: value.1, lidClosed: value.3 == true, unreadableIDs: value.4), enforce: enforce))
                    if !value.4.isEmpty { self.scheduleRetry(enforce: enforce, attempt: attempt) }
                case .failure(let error):
                    self.feed(.inventoryFailed(error.localizedDescription))
                    self.feed(.timerFired)
                    self.scheduleRetry(enforce: enforce, attempt: attempt)
                }
                if self.enforceAfterRead {
                    self.enforceAfterRead = false
                    self.refresh(enforce: true)
                } else {
                    self.finishIfSettled()
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
        finishIfSettled()
    }

    /// The devices the UI shows. Release builds show every device.
    private static func visible(_ devices: [AudioDevice]) -> [AudioDevice] {
        #if DEBUG
        if hideContinuityForDemo { return devices.filter { $0.transport != .continuity } }
        #endif
        return devices
    }

    /// Cancels queued hardware work. A later refresh delivers the waiting completions.
    private func cancelWork() {
        worker.cancel(); reading = false; writing = false; enforceAfterRead = false
    }

    private func finishIfSettled() {
        guard !reading, !writing, !enforceAfterRead, !completions.isEmpty else { return }
        let waiting = completions; completions = []
        waiting.forEach { $0() }
    }

    private func readHardware(enforce: Bool) throws {
        let readDevices = try hardware.devices()
        let readInput = try hardware.defaultInput(), readOutput = try hardware.defaultOutput()
        devices = Self.visible(readDevices); inputID = readInput; outputID = readOutput; lidClosed = hardware.lidClosed()
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
                    writing = true
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
                        self.writing = false
                        self.finishIfSettled()
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
        if let outcome = machine.takeManualOutcome() {
            switch outcome {
            case .confirmed(let name): manualNote = "Default input set to \(name)."
            case .failed: manualNote = "Could not set \(pendingManualName) as the default input. Try again."
            case .notConfirmed:
                manualNote = "CallReady could not confirm that \(pendingManualName) is the default input. Check the input and try again."
            case .targetLost: manualNote = "\(pendingManualName) is no longer available."
            }
        }
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

    // A user or test request to change the input. It uses the same machine and setter as automatic protection.
    func requestSwitch(to id: UInt32, original: UInt32, recordHistory: Bool = true) throws {
        try readHardware(enforce: false)
        if let failure = feed(.requestSwitch(target: id, original: original, recordHistory: recordHistory)) { throw failure }
    }

    /// All inputs the user can select by hand, Bluetooth included.
    var selectableInputs: [AudioDevice] {
        devices.filter { $0.isAvailableInput(lidClosed: lidClosed == true) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    @Published private(set) var manualNote: String?
    /// The name shown in the manual selection notes, captured when the click starts.
    private var pendingManualName = "Selected microphone"

    /// "Set as default input": the user picks the default input by hand. The guard then acts on it as usual,
    /// so a Bluetooth mic moves back to the preferred mic unless Bluetooth is allowed.
    /// A click is not charged to the automatic write budget, and the note follows the read-back.
    func useInputNow(_ id: UInt32) {
        guard id != inputID else { manualNote = "This microphone is already the default input."; return }
        do {
            try readHardware(enforce: false)
        } catch {
            manualNote = "Could not read the audio devices. Try again."
            return
        }
        let name = devices.first { $0.id == id }?.name ?? "Selected microphone"
        // One write at a time. The pending write keeps its own name and outcome note.
        guard !machine.state.hasPendingWrite else {
            manualNote = "CallReady is still changing the input. Try again in a moment."
            return
        }
        pendingManualName = name
        let setting = "Setting \(name) as the default input…"
        manualNote = setting
        // A rejection leaves no outcome note, so the failure text fills the gap. A write error keeps its outcome text.
        // A failed read-back leaves this click pending: the deadline gives it an outcome note.
        if feed(.userSelectInput(target: id, original: inputID)) != nil, manualNote == setting, !manualPending {
            manualNote = "\(name) is not available. Select another microphone."
        }
    }
    private var manualPending: Bool {
        if case .switching(let request, _, _) = machine.state { return request.manual }
        return false
    }

    /// Push-to-talk pins the input it started on. Release enforces the preferred input again.
    func setInputHeld(_ held: Bool) {
        guard held != inputHeld else { return }
        inputHeld = held
        if !held { refresh(enforce: true) }
    }

    func allowBluetoothForOneHour() {
        cancelWork()
        refresh(enforce: false)
        feed(.userAllowance(now().addingTimeInterval(3600)))
    }
    func resumeGuard() {
        refresh(enforce: false)
        feed(.userAllowance(nil))
    }
    func dismissIntroduction() { needsIntroduction = false; defaults.set(true, forKey: "introductionSeen") }
    func setEnabled(_ value: Bool) {
        cancelWork()
        refresh(enforce: false)
        feed(.userToggle(value))
    }
    func clearHistory() { feed(.clearHistory) }
    func setPriorities(_ uids: [String]) { cancelWork(); refresh(enforce: false); feed(.userPriorities(uids)) }
    func movePriority(_ uid: String) {
        var list = settings.priorityUIDs
        if let index = list.firstIndex(of: uid), index > 0 { list.swapAt(index, index - 1); setPriorities(list) }
    }
    func setPreferred(_ uid: String) {
        cancelWork()
        refresh(enforce: false)
        feed(.userPreferred(uid.isEmpty ? nil : uid))
    }
}

#if DEBUG
/// Debug builds only: hide the first-run note for screenshots. It does not save the choice.
extension GuardModel {
    static var skipIntroArgument: String { "-skip-intro" }
    static var hideContinuityArgument: String { "-demo-hide-continuity" }
    /// Hides iPhone (Continuity) inputs from the lists, so no personal device name shows in screenshots.
    static var hideContinuityForDemo = false
    func hideIntroductionForDemo() { needsIntroduction = false }
}
#endif
