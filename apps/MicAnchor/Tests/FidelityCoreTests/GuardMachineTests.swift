import Foundation
import Testing
import FidelityCore

// Fixture identities, clock, availability, and setter outcomes are logic data only.
struct GuardMachineTests {
    private let start = Date(timeIntervalSince1970: 1000)
    private let builtin = AudioDevice(id: 1, uid: "builtin", name: "Fixture built-in", transport: .builtIn, inputChannels: 1, outputChannels: 0)
    private let bluetooth = AudioDevice(id: 2, uid: "bt", name: "Fixture Bluetooth", transport: .bluetooth, inputChannels: 1, outputChannels: 2)
    private let usb = AudioDevice(id: 3, uid: "usb", name: "Fixture USB", transport: .usb, inputChannels: 1, outputChannels: 0)
    private var devices: [AudioDevice] { [builtin, bluetooth, usb] }
    private func snapshot(_ input: UInt32 = 2, devices: [AudioDevice]? = nil, closed: Bool = false) -> GuardSnapshot {
        GuardSnapshot(devices: devices ?? self.devices, input: input, lidClosed: closed)
    }
    private func name(_ state: GuardState) -> String {
        switch state {
        case .idle: return "idle"
        case .switching: return "switching"
        case .paused: return "paused"
        }
    }
    private func fixture(_ state: String) -> (GuardMachine, Date) {
        var machine = GuardMachine()
        machine.send(.devicesChanged(snapshot(), enforce: true), at: start)
        machine.send(.inputChanged(1, enforce: false), at: start)
        switch state {
        case "idle": machine.send(.userToggle(false), at: start)
        case "switching": machine.send(.inputChanged(2, enforce: true), at: start)
        case "paused":
            machine.send(.inputChanged(2, enforce: true), at: start)
            let date = start.addingTimeInterval(2)
            machine.send(.timerFired, at: date)
            return (machine, date)
        default: preconditionFailure("Unknown fixture state")
        }
        return (machine, start)
    }

    @Test func exhaustiveStateEventTransitionTable() {
        // Columns cover all nine event families and confirmation/nonconfirmation inputs.
        // Configuration changes quarantine a live forward write instead of overlapping it.
        let events: [GuardEvent] = [
            .inputChanged(1, enforce: true), .inputChanged(2, enforce: false), .timerFired,
            .userToggle(false), .userToggle(true),
            .devicesChanged(snapshot(), enforce: true), .userPreferred("usb"),
            .userAllowance(start.addingTimeInterval(3600)), .userAllowance(nil),
            .requestSwitch(target: 3, original: 1, recordHistory: true),
            .writeFailed("Fixture setter failure"), .inventoryFailed("Fixture read failure")
        ]
        let expected: [(String, [String])] = [
            ("idle", ["idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle", "idle", "switching", "idle", "idle"]),
            ("switching", ["idle", "switching", "switching", "paused", "paused", "switching", "paused", "switching", "switching", "switching", "idle", "switching"]),
            ("paused", ["paused", "paused", "paused", "paused", "paused", "paused", "paused", "paused", "paused", "paused", "paused", "paused"])
        ]
        var cells = 0
        for (state, row) in expected {
            #expect(row.count == events.count)
            for (index, event) in events.enumerated() {
                var (machine, date) = fixture(state)
                let effects = machine.send(event, at: date)
                #expect(name(machine.state) == row[index], "state=\(state), event=\(event)")
                assertInvariants(machine, effects: effects, at: date)
                cells += 1
                // Every event also runs at and past the active state's deadline.
                for offset in [0.0, 0.001, 301.0] {
                    var (expiring, _) = fixture(state)
                    let boundary = (expiring.state.deadline ?? date).addingTimeInterval(offset)
                    let result = expiring.send(event, at: boundary)
                    assertInvariants(expiring, effects: result, at: boundary)
                    cells += 1
                }
            }
        }
        #expect(cells == 144)
    }

    private func assertInvariants(_ machine: GuardMachine, effects: [GuardEffect], at date: Date) {
        #expect(machine.state.deadline.map { $0 > date } ?? true)
        #expect(machine.writeTimes.filter { date.timeIntervalSince($0) <= 30 }.count <= GuardMachine.maximumWrites)
        if case .paused(let until) = machine.state {
            #expect(machine.settings.pausedUntil == until)
            #expect(!machine.state.hasPendingWrite)
        }
        for case .setInput(let target) in effects {
            #expect(machine.snapshot.devices.contains {
                $0.id == target.id && $0.uid == target.uid && $0.isAvailableInput(lidClosed: machine.snapshot.lidClosed)
            })
        }
    }

    @Test func deadlinesClearAllPendingIntentEvenWithoutInventory() {
        for state in ["switching", "paused"] {
            var (machine, date) = fixture(state)
            let expiry = machine.state.deadline!
            machine.send(.inventoryFailed("Fixture unavailable inventory"), at: expiry)
            #expect(!machine.state.hasPendingWrite)
            if case .paused(let until) = machine.state {
                machine.send(.timerFired, at: until)
                #expect(machine.state == .idle)
                #expect(machine.settings.pausedUntil == nil)
            }
            date = expiry
            assertInvariants(machine, effects: [], at: date)
        }
    }

    @Test func unreadableLiveTargetRetainsSerializationButCannotConfirm() {
        var (machine, date) = fixture("switching")
        let unreadable = GuardSnapshot(devices: [bluetooth, usb], input: 2, lidClosed: false, unreadableIDs: [1])
        #expect(machine.send(.devicesChanged(unreadable, enforce: true), at: date).isEmpty)
        #expect(name(machine.state) == "switching")
        machine.send(.inputChanged(1, enforce: false), at: date)
        #expect(name(machine.state) == "switching")
        #expect(machine.settings.interventions == 1)
        machine.send(.timerFired, at: date.addingTimeInterval(2))
        #expect(name(machine.state) == "paused")
        #expect(!machine.state.hasPendingWrite)
        // A terminal timeout discards the request. Late observations cannot confirm it.
        machine.send(.devicesChanged(snapshot(1), enforce: false), at: date.addingTimeInterval(3))
        #expect(name(machine.state) == "paused")
        #expect(machine.settings.interventions == 1)
    }

    @Test func seededTenThousandEventSequencePreservesInvariants() {
        // Xorshift64 fixture generator; reproduce with this exact seed.
        var seed: UInt64 = 0xF1DE_1177_0000_0007
        func next(_ bound: Int) -> Int {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Int(seed % UInt64(bound))
        }
        var machine = GuardMachine(), date = start
        var inventory = devices, input: UInt32 = 2, closed = false
        var observedWrites: [Date] = []
        var counts = [Int](repeating: 0, count: 9)
        var states = Set<String>()
        for _ in 0..<10_000 {
            date = date.addingTimeInterval([0, 0.01, 0.2, 2, 31, 301][next(6)])
            let family = next(9)
            counts[family] += 1
            let event: GuardEvent
            switch family {
            case 0:
                input = [UInt32(1), 2, 3][next(3)]
                event = .inputChanged(input, enforce: next(2) == 0)
            case 1: event = .timerFired
            case 2: event = .userToggle(next(2) == 0)
            case 3:
                closed = next(3) == 0
                inventory = devices.filter { _ in next(4) != 0 }
                event = .devicesChanged(snapshot(input, devices: inventory, closed: closed), enforce: true)
            case 4: event = .userPreferred([nil, "usb", "builtin"][next(3)])
            case 5: event = .userAllowance(next(2) == 0 ? nil : date.addingTimeInterval(3600))
            case 6: event = .requestSwitch(target: [UInt32(1), 3][next(2)], original: input, recordHistory: true)
            case 7: event = .writeFailed("Fixture randomized rejection")
            default: event = .inventoryFailed("Fixture randomized enumeration failure")
            }
            let effects = machine.send(event, at: date)
            assertInvariants(machine, effects: effects, at: date)
            states.insert(name(machine.state))
            for case .setInput(let target) in effects {
                observedWrites.append(date)
                // Leave some writes unconfirmed. Deliver other writes immediately.
                if next(3) == 0 {
                    input = target.id
                    let confirmations = machine.send(.inputChanged(input, enforce: false), at: date)
                    assertInvariants(machine, effects: confirmations, at: date)
                    for case .setInput in confirmations { observedWrites.append(date) }
                }
            }
            observedWrites.removeAll { date.timeIntervalSince($0) > 30 }
            #expect(observedWrites.count <= GuardMachine.maximumWrites)
        }
        #expect(counts.allSatisfy { $0 > 0 })
        #expect(states == Set(["idle", "switching", "paused"]))
    }
    @Test func timeoutDiscardsTargetAndCannotConfirmLateObservation() {
        var machine = GuardMachine()
        machine.send(.devicesChanged(snapshot(), enforce: true), at: start)
        machine.send(.timerFired, at: start.addingTimeInterval(2))
        #expect(!machine.state.hasPendingWrite)
        #expect(!String(describing: machine.state).contains("SwitchRequest"))
        machine.send(.devicesChanged(snapshot(1), enforce: false), at: start.addingTimeInterval(3))
        #expect(machine.settings.interventions == 0)
        #expect(name(machine.state) == "paused")
    }

    @Test func deadlineEqualTargetObservationConfirmsOnce() {
        var machine = GuardMachine()
        machine.send(.devicesChanged(snapshot(), enforce: true), at: start)
        let deadline = start.addingTimeInterval(2)
        machine.send(.devicesChanged(snapshot(1), enforce: true), at: deadline)
        #expect(machine.state == .idle)
        #expect(machine.settings.pausedUntil == nil)
        #expect(machine.settings.interventions == 1)
        machine.send(.devicesChanged(snapshot(1), enforce: true), at: deadline)
        #expect(machine.settings.interventions == 1)
    }

}
