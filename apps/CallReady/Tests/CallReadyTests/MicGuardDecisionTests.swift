import Foundation
import Testing
@testable import CallCore

struct GuardDecisionTests {
    // Use fixture data. Do not present these devices as system measurements.
    let builtIn = AudioDevice(id: 1, uid: "builtin", name: "Internal microphone", transport: .builtIn, inputChannels: 1, outputChannels: 0)
    let headset = AudioDevice(id: 2, uid: "headset", name: "Wireless headset", transport: .bluetooth, inputChannels: 1, outputChannels: 2)
    let usb = AudioDevice(id: 3, uid: "usb", name: "USB microphone", transport: .usb, inputChannels: 2, outputChannels: 0)
    let speaker = AudioDevice(id: 4, uid: "speaker", name: "Internal speakers", transport: .builtIn, inputChannels: 0, outputChannels: 2)

    @Test func enabledGuardsBluetooth() {
        #expect(GuardDecision.action(devices: [builtIn, headset], currentInput: 2, preferredUID: nil, enabled: true) == .setInput(1))
    }
    @Test func disabledDoesNothing() {
        #expect(GuardDecision.action(devices: [builtIn, headset], currentInput: 2, preferredUID: nil, enabled: false) == .none)
    }
    @Test func safeInputIsUnchanged() {
        #expect(GuardDecision.action(devices: [builtIn, headset, usb], currentInput: 3, preferredUID: "builtin", enabled: true) == .none)
    }
    @Test func explicitPreferenceWins() {
        #expect(GuardDecision.action(devices: [builtIn, headset, usb], currentInput: 2, preferredUID: "usb", enabled: true) == .setInput(3))
    }
    @Test func disappearedPreferenceFallsBackToBuiltIn() {
        #expect(GuardDecision.preferredDevice(in: [builtIn, headset], uid: "usb") == builtIn)
    }
    @Test func noBuiltInFallsBackToSafeInput() {
        #expect(GuardDecision.preferredDevice(in: [speaker, headset, usb], uid: nil) == usb)
    }
    @Test func rejectsBluetoothPreference() {
        #expect(GuardDecision.preferredDevice(in: [builtIn, headset], uid: "headset") == builtIn)
    }
    @Test func noSafeInputReportsUnavailable() {
        #expect(GuardDecision.action(devices: [headset, speaker], currentInput: 2, preferredUID: nil, enabled: true) == .noSafeInput)
    }
    @Test func unknownCurrentInputDoesNothing() {
        #expect(GuardDecision.action(devices: [builtIn], currentInput: 999, preferredUID: nil, enabled: true) == .none)
    }
    @Test func bluetoothLEIsGuarded() {
        let le = AudioDevice(id: 5, uid: "le", name: "LE headset", transport: .bluetoothLE, inputChannels: 1, outputChannels: 2)
        #expect(GuardDecision.action(devices: [le, builtIn], currentInput: 5, preferredUID: nil, enabled: true) == .setInput(1))
    }
    @Test func classifiesTransportCodes() {
        #expect(Transport.classify(0x626c7565) == .bluetooth)
        #expect(Transport.classify(0x626c6561) == .bluetoothLE)
        #expect(Transport.classify(0x626c746e) == .builtIn)
        #expect(Transport.classify(0x75736220) == .usb)
        #expect(Transport.classify(0x76697274) == .virtual)
        #expect(Transport.classify(0x67727570) == .virtual)
        #expect(Transport.classify(0x66677270) == .virtual)
        #expect(Transport.classify(0) == .other)
    }
    @Test func deterministicFallback() {
        let other = AudioDevice(id: 6, uid: "aaa", name: "External microphone", transport: .usb, inputChannels: 1, outputChannels: 0)
        #expect(GuardDecision.preferredDevice(in: [usb, other], uid: nil) == other)
        #expect(GuardDecision.preferredDevice(in: [other, usb], uid: nil) == other)
    }
    @Test func recordsSuccessAndCapsCounter() {
        var settings = GuardSettings(interventions: Int.max)
        let date = Date(timeIntervalSince1970: 123)
        settings.recordIntervention(at: date)
        #expect(settings.interventions == Int.max)
        #expect(settings.lastIntervention == date)
    }
    @Test func persistsSettingsAndDefaultsToOn() throws {
        let suite = "CallReady.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == GuardSettings())
        var settings = GuardSettings(enabled: false, preferredUID: "usb")
        settings.recordIntervention(at: Date(timeIntervalSince1970: 456))
        store.save(settings)
        #expect(store.load() == settings)
        settings.preferredUID = nil
        settings.lastIntervention = nil
        store.save(settings)
        #expect(store.load() == settings)
    }
}

struct GuardSafetyTests {
    // Use fixture data. These devices and times do not describe this computer.
    private func device(_ id: UInt32, _ uid: String, _ type: Transport, alive: Bool = true, source: Bool = true, name: String = "Fixture mic") -> AudioDevice {
        AudioDevice(id: id, uid: uid, name: name, transport: type, inputChannels: 1, outputChannels: 0, isAlive: alive, dataSourceAvailable: source)
    }
    @Test func macMiniPicksUSBOverContinuity() {
        let phone = device(84, "000-phone", .continuity), usb = device(10, "zzz-usb", .usb)
        #expect(GuardDecision.preferredDevice(in: [phone, usb], uid: nil) == usb)
    }
    @Test func macMiniPicksUSBOverVirtual() {
        let loop = device(9, "000-loop", .virtual, name: "BlackHole"), usb = device(10, "zzz-usb", .usb)
        #expect(GuardDecision.preferredDevice(in: [loop, usb], uid: nil) == usb)
        #expect(GuardDecision.preferredDevice(in: [loop, usb], uid: loop.uid) == usb)
    }
    @Test func neverAutomaticallyUsesWirelessOrUnknownTransport() {
        for type in [Transport.continuity, .airPlay, .other, .virtual, .bluetooth, .bluetoothLE] {
            #expect(GuardDecision.preferredDevice(in: [device(1, "one", type)], uid: nil) == nil)
        }
    }
    @Test func wiredRankingIgnoresUIDOrder() {
        let builtin = device(1, "zzz", .builtIn), usb = device(2, "yyy", .usb), pci = device(3, "aaa", .pci)
        #expect(GuardDecision.preferredDevice(in: [pci, usb, builtin], uid: nil) == builtin)
        #expect(GuardDecision.preferredDevice(in: [pci, usb], uid: nil) == usb)
        #expect(GuardDecision.preferredDevice(in: [pci], uid: nil) == pci)
    }
    @Test func closedLidSkipsBuiltInIncludingExplicitChoice() {
        let builtin = device(1, "builtin", .builtIn), usb = device(2, "usb", .usb)
        #expect(GuardDecision.preferredDevice(in: [builtin, usb], uid: builtin.uid, lidClosed: true) == usb)
        #expect(GuardDecision.preferredDevice(in: [builtin], uid: nil, lidClosed: true) == nil)
    }
    @Test func inactiveAndDisconnectedDataSourcesFallBack() {
        let dead = device(1, "dead", .builtIn, alive: false), unavailable = device(2, "missing-source", .builtIn, source: false), usb = device(3, "usb", .usb)
        #expect(GuardDecision.preferredDevice(in: [dead, unavailable, usb], uid: nil) == usb)
    }
    @Test func loopbackNameCannotMasqueradeAsWiredInput() {
        let loop = device(1, "loop", .usb, name: "Loopback Audio")
        #expect(GuardDecision.preferredDevice(in: [loop], uid: loop.uid) == nil)
    }
    @Test func loopLimiterPausesAfterFourthWithinThirtySeconds() {
        var limiter = InterventionLimiter()
        let start = Date(timeIntervalSince1970: 1000)
        for offset in [0.0, 10, 20] { limiter.record(at: start.addingTimeInterval(offset)) }
        #expect(limiter.pausedUntil == nil)
        limiter.record(at: start.addingTimeInterval(30))
        #expect(limiter.pausedUntil == start.addingTimeInterval(330))
    }
    @Test func spacedInterventionsDoNotPause() {
        var limiter = InterventionLimiter()
        for offset in [0.0, 31, 62, 93] { limiter.record(at: Date(timeIntervalSince1970: offset)) }
        #expect(limiter.pausedUntil == nil)
        #expect(limiter.timestamps.count == 1)
    }
    @Test func snoozeAndLoopPauseExpireAtBoundary() {
        let now = Date(timeIntervalSince1970: 1000), bluetooth = device(1, "bt", .bluetooth), usb = device(2, "usb", .usb)
        #expect(GuardDecision.action(devices: [bluetooth, usb], currentInput: 1, preferredUID: nil, enabled: true, now: now, bluetoothAllowedUntil: now.addingTimeInterval(1)) == .none)
        #expect(GuardDecision.action(devices: [bluetooth, usb], currentInput: 1, preferredUID: nil, enabled: true, now: now, pausedUntil: now.addingTimeInterval(1)) == .none)
        #expect(GuardDecision.action(devices: [bluetooth, usb], currentInput: 1, preferredUID: nil, enabled: true, now: now, bluetoothAllowedUntil: now, pausedUntil: now) == .setInput(2))
    }
    @Test func persistsTemporaryUserOverrideAndLoopPause() throws {
        let suite = "CallReady.safety.tests.\(UUID().uuidString)", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let settings = GuardSettings(bluetoothAllowedUntil: Date(timeIntervalSince1970: 1000), pausedUntil: Date(timeIntervalSince1970: 2000))
        store.save(settings)
        #expect(store.load() == settings)
    }
    @Test func transportCodesMatchSDK() {
        let pairs: [(UInt32, Transport)] = [(0x63637764, .continuity), (0x6363776c, .continuity), (0x7468756e, .thunderbolt), (0x70636920, .pci), (0x68646d69, .hdmi), (0x64707274, .displayPort), (0x31333934, .firewire), (0x65617662, .avb), (0x61697270, .airPlay)]
        for (code, type) in pairs { #expect(Transport.classify(code) == type) }
    }
}
