import CoreAudio
import Foundation
import Testing
@testable import Fidelity
import FidelityCore

// Fixture hardware and a fixture clock exercise the production model. No hardware measurements.
private final class FixtureHardware: AudioHardwareAccess {
    let builtin = AudioDevice(id: 1, uid: "builtin", name: "Fixture built-in", transport: .builtIn, inputChannels: 1, outputChannels: 0)
    let usb = AudioDevice(id: 3, uid: "usb", name: "Fixture USB", transport: .usb, inputChannels: 1, outputChannels: 0)
    let bluetooth = AudioDevice(id: 2, uid: "bt", name: "Fixture Bluetooth", transport: .bluetooth, inputChannels: 1, outputChannels: 2)
    var inventory: [AudioDevice] = []
    var input: UInt32 = 2
    var closed = false
    var settles = true
    var rejects = false
    var readsFail = false
    var onInputRead: (() -> Void)?
    var writes: [UInt32] = []
    var changed: (() -> Void)?
    var skippedIDs: [AudioObjectID] { [] }
    init() { inventory = [builtin, usb, bluetooth] }
    func devices() throws -> [AudioDevice] {
        if readsFail { throw HardwareError(operation: "Fixture unreadable inventory", status: -1) }
        return inventory
    }
    func defaultInput() throws -> AudioObjectID { onInputRead?(); return input }
    func defaultOutput() throws -> AudioObjectID { 2 }
    func lidClosed() -> Bool? { closed }
    func setInput(_ id: AudioObjectID) throws {
        writes.append(id)
        if rejects { throw HardwareError(operation: "Fixture rejected write", status: -1) }
        if settles { input = id }
    }
    func startListening(_ changed: @escaping () -> Void) throws { self.changed = changed }
    func stopListening() -> [OSStatus] { changed = nil; return [0, 0, 0] }
}
private final class FixtureClock {
    var date = Date(timeIntervalSince1970: 1000)
    func advance(_ seconds: Double) { date = date.addingTimeInterval(seconds) }
}

@MainActor struct GuardModelTests {
    @Test(arguments: ["setter", "unavailable"])
    func selftestRejectedSetterDoesNotReportNoErr(reason: String) throws {
        let hardware = FixtureHardware()
        if reason == "setter" { hardware.rejects = true }
        else {
            hardware.input = 1; hardware.closed = true
            hardware.inventory = [hardware.builtin, AudioDevice(id: 2, uid: "output", name: "Fixture output",
                transport: .builtIn, inputChannels: 0, outputChannels: 2)]
        }
        let (pass, detail) = try switchAndRestore(hardware, callbackCount: { 0 })
        #expect(!pass)
        #expect(!detail.contains("set=noErr (0)"))
        #expect(detail.contains("status -1"))
    }
    @Test func removedPendingTargetRetiresRequestAndUsesFreshFallback() throws {
        try withModel { model, hardware, _, _ in
            model.setPreferred("usb")
            hardware.input = 2; hardware.settles = false
            model.refresh(enforce: true)
            #expect(hardware.writes == [3, 3])
            hardware.inventory.removeAll { $0.uid == "usb" }
            hardware.settles = true
            hardware.changed?()
            model.refresh(enforce: true)
            #expect(hardware.writes == [3, 3, 1])
            #expect(model.inputID == 1)
            #expect(!model.loopPaused)
        }
    }
    @Test func forwardTimeoutPauseExpiryClearsRequest() throws {
        try withModel { model, hardware, clock, _ in
            model.start()
            hardware.input = 2; hardware.settles = false
            hardware.changed?()
            clock.advance(7)
            model.refresh(enforce: true)
            #expect(model.loopPaused)
            let expiry = try #require(model.settings.pausedUntil)
            clock.date = expiry
            hardware.settles = true
            model.refresh(enforce: true)
            #expect(hardware.writes == [1, 1, 1])
            #expect(model.inputID == 1)
            #expect(!model.loopPaused)
            #expect(!model.bluetoothAllowed)
        }
    }
    @Test func toggleRetiresUnconfirmedForwardRequest() throws {
        try withModel { model, hardware, clock, _ in
            hardware.settles = false
            model.start()
            model.setEnabled(false)
            hardware.inventory.removeAll { $0.uid == "builtin" }
            hardware.settles = true
            model.setEnabled(true)
            #expect(hardware.writes == [1])
            clock.advance(300)
            model.refresh(enforce: true)
            #expect(hardware.writes == [1, 3])
            #expect(model.inputID == 3)
        }
    }
    @Test func recycledPendingDeviceIDDoesNotConfirmDifferentUID() throws {
        try withModel { model, hardware, _, _ in
            hardware.settles = false
            model.start()
            hardware.inventory[0] = AudioDevice(id: 1, uid: "replacement", name: "Fixture replacement",
                transport: .usb, inputChannels: 1, outputChannels: 0)
            hardware.input = 1
            model.refresh(enforce: false)
            #expect(model.settings.interventions == 0)
            #expect(!model.recentIntervention)
        }
    }
    private func withModel(_ body: (GuardModel, FixtureHardware, FixtureClock, UserDefaults) throws -> Void) throws {
        let suite = "Fidelity.model.fixture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = FixtureHardware(), clock = FixtureClock()
        let model = GuardModel(hardware: hardware, defaults: defaults, now: { clock.date }, scheduleEvents: false)
        defer { model.stop() }
        try body(model, hardware, clock, defaults)
    }
    @Test func closedLidMovesEstablishedBuiltInCall() throws {
        try withModel { model, hardware, _, _ in
            hardware.input = 1
            model.start()
            #expect(hardware.writes.isEmpty)
            hardware.closed = true
            hardware.changed?()
            #expect(hardware.writes == [3])
            #expect(model.inputID == 3)
            #expect(model.settings.interventions == 1)
        }
    }
    @Test func unavailableDataSourceMovesEstablishedCall() throws {
        try withModel { model, hardware, _, _ in
            hardware.input = 1
            hardware.inventory[0] = AudioDevice(id: 1, uid: "builtin", name: "Fixture built-in", transport: .builtIn,
                inputChannels: 1, outputChannels: 0, dataSourceAvailable: false)
            model.refresh(enforce: true)
            #expect(hardware.writes == [3])
        }
    }
    @Test func nonsettlingSuccessStopsAcrossCallbacksAndTimers() throws {
        try withModel { model, hardware, clock, defaults in
            hardware.settles = false
            model.start()
            for _ in 0..<10 {
                clock.advance(2.1)
                hardware.changed?()
                model.refresh(enforce: true, attempt: 3)
            }
            #expect(hardware.writes.count <= 3)
            #expect(model.loopPaused)
            #expect(model.settings.interventions == 0)
            #expect(SettingsStore(defaults: defaults).load().pausedUntil == model.settings.pausedUntil)
        }
    }
    @Test func competingSelectorStopsAtAttemptBudget() throws {
        try withModel { model, hardware, _, _ in
            model.start()
            for _ in 0..<10 { hardware.input = 2; hardware.changed?() }
            #expect(hardware.writes.count <= 3)
            #expect(model.loopPaused)
            #expect(model.settings.interventions == 3)
        }
    }
    @Test func rejectedWritesStopAcrossCallbacks() throws {
        try withModel { model, hardware, _, _ in
            hardware.rejects = true
            model.start()
            for _ in 0..<10 { hardware.changed?() }
            #expect(hardware.writes.count <= 3)
            #expect(model.loopPaused)
            #expect(model.settings.interventions == 0)
        }
    }
    @Test func delayedConfirmationRecordsOnceAndExplicitAllowanceExpires() throws {
        try withModel { model, hardware, clock, defaults in
            hardware.settles = false
            model.start()
            #expect(model.settings.interventions == 0)
            hardware.input = 1
            hardware.changed?(); hardware.changed?()
            #expect(model.settings.interventions == 1)
            #expect(model.recentIntervention)
            model.allowBluetoothForOneHour()
            hardware.input = 2
            hardware.changed?()
            #expect(hardware.input == 2)
            #expect(SettingsStore(defaults: defaults).load().bluetoothAllowedUntil == clock.date.addingTimeInterval(3600))
            hardware.settles = true
            clock.advance(3600)
            model.refresh(enforce: true)
            #expect(hardware.input == 1)
            #expect(model.settings.interventions == 2)
        }
    }
    @Test func failureBudgetSurvivesLongGapsAndPauseExpires() throws {
        try withModel { model, hardware, clock, _ in
            hardware.rejects = true
            model.start()
            for _ in 0..<2 { clock.advance(31); hardware.changed?() }
            #expect(hardware.writes.count == 3)
            #expect(model.loopPaused)
            hardware.rejects = false
            clock.advance(299)
            hardware.changed?()
            #expect(hardware.writes.count == 3)
            clock.advance(1)
            hardware.changed?()
            #expect(hardware.writes.count == 4)
            #expect(!model.loopPaused)
            #expect(model.settings.interventions == 1)
        }
    }
    @Test func establishedUnavailableCallRespectsOffAndAllowance() throws {
        try withModel { model, hardware, clock, _ in
            hardware.input = 1; hardware.closed = true
            model.setEnabled(false)
            #expect(hardware.writes.isEmpty)
            model.allowBluetoothForOneHour()
            model.setEnabled(true)
            #expect(hardware.writes.isEmpty)
            clock.advance(3600)
            model.refresh(enforce: true)
            #expect(hardware.writes == [3])
        }
    }
    @Test func establishedUnavailableCallWithoutFallbackDoesNotWrite() throws {
        try withModel { model, hardware, _, _ in
            hardware.input = 1; hardware.closed = true
            hardware.inventory = [hardware.builtin, hardware.bluetooth]
            model.refresh(enforce: true)
            #expect(hardware.writes.isEmpty)
            #expect(model.preferred == nil)
            #expect(model.status == "Connect a wired microphone")
        }
    }
    @Test func restoredModelHonorsPersistedPause() throws {
        try withModel { model, hardware, clock, defaults in
            hardware.rejects = true
            model.start()
            hardware.changed?(); hardware.changed?()
            #expect(model.loopPaused)
            model.stop()
            let restored = GuardModel(hardware: hardware, defaults: defaults, now: { clock.date }, scheduleEvents: false)
            defer { restored.stop() }
            hardware.rejects = false
            restored.start()
            #expect(hardware.writes.count == 3)
            #expect(restored.loopPaused)
        }
    }

    @Test func availabilityPollMovesWithoutDeviceCallback() async throws {
        let suite = "Fidelity.poll.fixture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = FixtureHardware()
        hardware.input = 1
        let model = GuardModel(hardware: hardware, defaults: defaults)
        defer { model.stop() }
        model.start()
        #expect(hardware.writes.isEmpty)
        hardware.closed = true
        func deliverTimer() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        for _ in 0..<30 where model.settings.interventions == 0 {
            deliverTimer()
            // Permit the production timer's MainActor task to execute.
            await Task.yield()
        }
        #expect(hardware.writes == [3])
        #expect(model.settings.interventions == 1)
    }

    @Test(arguments: ["off", "paused", "off-paused"])
    func allowanceHelperNamesRemainingProtectionRequirement(state: String) throws {
        try withModel { model, hardware, _, _ in
            if state.contains("paused") {
                hardware.rejects = true
                model.start()
                hardware.changed?(); hardware.changed?()
                #expect(model.loopPaused)
            }
            if state.contains("off") { model.setEnabled(false) }
            model.allowBluetoothForOneHour()
            let note = model.microphoneProtectionNote
            #expect(!note.contains("restore protection"))
            if state.contains("off") { #expect(note.contains("Turn Guard on")) }
            if state.contains("paused") {
                #expect(note.contains("input-change pause"))
                #expect(note.contains(model.settings.pausedUntil!.formatted(date: .omitted, time: .shortened)))
            }
        }
    }

    @Test func singleInputSelftestProvesWriteAndLabelsTransitionUnknown() throws {
        let hardware = FixtureHardware()
        hardware.input = 1
        hardware.inventory = [hardware.builtin,
            AudioDevice(id: 2, uid: "output", name: "Fixture output", transport: .builtIn,
                inputChannels: 0, outputChannels: 2)]
        let (pass, detail) = try switchAndRestore(hardware, callbackCount: { 0 })
        #expect(pass)
        #expect(detail.contains("inputCount=1"))
        #expect(detail.contains("set=noErr (0)"))
        #expect(detail.contains("after=1"))
        #expect(detail.contains("transition=unknown"))
        #expect(detail.contains("single input; no distinct input transition"))
        #expect(hardware.writes.allSatisfy { $0 == 1 })
        #expect(!hardware.writes.isEmpty)
    }

    @Test func deadlineReadsHardwareBeforeExpiringDelayedCallback() throws {
        try withModel { model, hardware, clock, defaults in
            hardware.settles = false
            model.start()
            hardware.input = 1 // Fixture HAL completes without a listener callback.
            clock.advance(2)
            var pausedDuringRead = false
            hardware.onInputRead = { pausedDuringRead = model.loopPaused }
            model.processDeadline()
            #expect(!pausedDuringRead)
            #expect(!model.loopPaused)
            #expect(model.settings.interventions == 1)
            #expect(SettingsStore(defaults: defaults).load().pausedUntil == nil)
            #expect(hardware.writes == [1])
        }
    }

    @Test(arguments: ["off", "paused", "off-paused"])
    func helperDoesNotPromiseSwitchWhileProtectionCannotAct(state: String) throws {
        try withModel { model, hardware, clock, _ in
            model.start()
            if state.contains("paused") {
                hardware.input = 2; hardware.changed?()
                hardware.input = 2; hardware.changed?()
                hardware.input = 2; hardware.changed?()
                #expect(model.loopPaused)
            }
            if state.contains("off") { model.setEnabled(false) }
            #expect(!model.bluetoothAllowed)
            #expect(!model.microphoneProtectionNote.contains("switches back"))
            if state.contains("off") { #expect(model.microphoneProtectionNote.contains("Guard is off")) }
            else {
                #expect(model.microphoneProtectionNote.contains("Guard is paused until"))
                clock.date = try #require(model.settings.pausedUntil)
                model.refresh(enforce: true)
                #expect(!model.loopPaused)
                #expect(model.microphoneProtectionNote.contains("switches back"))
            }
        }
    }

}
