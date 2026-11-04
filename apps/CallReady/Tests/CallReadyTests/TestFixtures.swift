import AppKit
import CoreAudio
import SwiftUI
import Testing
@testable import CallReady
import CallCore

// Test-only fixtures. The app target contains no simulated devices or sample events.

/// Simulated input devices for the mute part.
enum FixtureData {
    static let devices: [InputDevice] = [
        InputDevice(id: "fixture-1", name: "Studio Microphone (Fixture)", supportsMute: true, supportsVolume: true, isDefault: true),
        InputDevice(id: "fixture-2", name: "Built-in Microphone (Fixture)", supportsMute: true, supportsVolume: true, isDefault: false),
        InputDevice(id: "fixture-3", name: "USB Headset (Fixture)", supportsMute: false, supportsVolume: true, isDefault: false),
    ]
    static let defaultDevice: InputDevice = devices[0]
}

/// In-memory mute backend.
@MainActor final class FixtureDevices: DeviceBackend {
    var list = FixtureData.devices
    var mutes: [String: Bool] = [:]
    var volumes: [String: Float] = [:]
    func devices() -> [InputDevice] { list }
    func mute(_ d: InputDevice) -> Bool? { d.supportsMute ? (mutes[d.id] ?? true) : nil }
    func volume(_ d: InputDevice) -> Float? { d.supportsVolume ? (volumes[d.id] ?? 0.64) : nil }
    func setMute(_ d: InputDevice, _ muted: Bool) -> Bool {
        guard d.supportsMute else { return false }; mutes[d.id] = muted; return true
    }
    func setVolume(_ d: InputDevice, _ volume: Float) -> Bool {
        guard d.supportsVolume else { return false }; volumes[d.id] = volume; return true
    }
    func select(_ id: String) -> Bool {
        guard list.contains(where: { $0.id == id }) else { return false }
        for i in list.indices { list[i].isDefault = list[i].id == id }; return true
    }
}

/// Write-and-restore probe for one device. Restores mute and volume even when the test write fails.
@MainActor func restoreProbe(_ d: InputDevice, backend: DeviceBackend) -> (Bool, String) {
    let mute = backend.mute(d), volume = backend.volume(d)
    var restored = true
    var changed = false
    func exercise() {
        defer {
            if let volume { restored = backend.setVolume(d, volume) && restored }
            if let mute { restored = backend.setMute(d, mute) && restored }
        }
        if let mute { changed = backend.setMute(d, !mute) }
        else if let volume { changed = backend.setVolume(d, volume == 0 ? 0.5 : 0) }
    }
    exercise()
    let verified = backend.mute(d) == mute && backend.volume(d) == volume
    return (changed && restored && verified, "write: \(changed ? "passed" : "failed"); restore: \(restored && verified ? "verified" : "FAILED")")
}

/// Twelve simulated inputs for the microphone part: one built-in, ten USB, one Bluetooth headset.
final class TwelveDeviceHardware: AudioHardwareAccess {
    var input: UInt32 = 12
    var skippedIDs: [UInt32] { [] }
    var inventory: [AudioDevice] = (1...12).map { index in
        let transport: Transport = index == 12 ? .bluetooth : (index == 1 ? .builtIn : .usb)
        let name = index == 12 ? "Fixture Bluetooth headset" : "Fixture Microphone \(index)"
        return AudioDevice(id: UInt32(index), uid: "fixture-\(index)", name: name, transport: transport, inputChannels: 1, outputChannels: index == 12 ? 2 : 0)
    }
    /// Seconds each inventory read waits. Simulates a slow audio system on the async path.
    var readDelay: TimeInterval = 0
    func devices() throws -> [AudioDevice] {
        if readDelay > 0 { Thread.sleep(forTimeInterval: readDelay) }
        return inventory
    }
    func defaultInput() throws -> UInt32 { input }
    func defaultOutput() throws -> UInt32 { 12 }
    func lidClosed() -> Bool? { false }
    var writes: [UInt32] = []
    /// Called after each write, so a test can mirror the default input in the mute fixture.
    var onSet: ((UInt32) -> Void)?
    func setInput(_ id: UInt32) throws { input = id; writes.append(id); onSet?(id) }
    func startListening(_ changed: @escaping () -> Void) throws {}
    func stopListening() -> [OSStatus] { [] }
}

/// A guard model on isolated preferences and simulated hardware.
@MainActor final class FixtureSession {
    let hardware = TwelveDeviceHardware()
    let defaults: UserDefaults
    let suite: String
    let model: GuardModel
    init() {
        suite = "CallReady.fixture." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        model = GuardModel(hardware: hardware, defaults: defaults, scheduleEvents: false)
        model.dismissIntroduction()
        model.refresh(enforce: true)
    }
    func simulateTakeover() { hardware.input = 12; model.refresh(enforce: true) }
    func close() { model.stop(); defaults.removePersistentDomain(forName: suite) }
}

/// Fixture calendar events placed relative to `now`.
enum FixtureCalendar {
    static func events(now: Date, calendar: Calendar = .current) -> [MeetEvent] {
        let midnight = calendar.startOfDay(for: now)
        let anchor = max(midnight.addingTimeInterval(9 * 3600), now)
        func ev(_ offsetMinutes: Double, _ minutes: Int, _ title: String, _ text: String) -> MeetEvent {
            let start = anchor.addingTimeInterval(offsetMinutes * 60)
            return MeetEvent(id: "fixture-\(Int(offsetMinutes))", title: title, start: start,
                             end: start.addingTimeInterval(TimeInterval(minutes * 60)), searchText: text,
                             calendarID: offsetMinutes < 100 ? "fixture-work" : "fixture-personal")
        }
        return [
            ev(-150, 45, "Fixture Standup", "Daily sync\nhttps://zoom.us/j/111222333"),
            ev(-75, 60, "Fixture Design Review", "Design walkthrough, no link"),
            ev(5, 45, "Fixture Client Call", "Meet: https://meet.google.com/abc-defg-hij"),
            ev(120, 90, "Fixture Workshop", "Room 5 · https://teams.microsoft.com/l/meetup-join/tk1"),
            ev(260, 30, "Fixture One to One", "https://subdomain.webex.com/meet/wx123"),
            ev(330, 60, "Fixture Wrap-up", "Notes in the shared doc"),
        ]
    }
}

/// Switches to another safe input through the guard model, then restores the original input.
@MainActor func switchAndRestore(_ hardware: any AudioHardwareAccess, callbackCount: () -> Int) throws -> (Bool, String) {
    let devices = try hardware.devices(), original = try hardware.defaultInput()
    guard let before = devices.first(where: { $0.id == original && $0.inputChannels > 0 }) else { return (false, "Original input unavailable") }
    let inputs = devices.filter { $0.isSafeInput && !(hardware.lidClosed() == true && $0.transport == .builtIn) }
    let target = inputs.first { $0.id != original } ?? before
    let suite = "CallReady.probe.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { return (false, "Isolated preferences unavailable") }
    defer { defaults.removePersistentDomain(forName: suite) }
    SettingsStore(defaults: defaults).save(GuardSettings(enabled: false))
    let model = GuardModel(hardware: hardware, defaults: defaults, scheduleEvents: false)
    model.start()
    defer { model.stop() }
    let callbacksBefore = callbackCount()
    let distinct = target.id != original
    var switched = false, restored = false, after: UInt32 = 0, restoreID: UInt32 = 0
    var switchStatus = "not attempted", restoreStatus = "not attempted"
    var history = false, allowance = false, resumed = false
    func waitFor(_ id: UInt32) throws -> UInt32 {
        for _ in 0..<10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            model.refresh(enforce: false)
            let actual = try hardware.defaultInput()
            if actual == id { return actual }
        }
        return try hardware.defaultInput()
    }
    defer {
        try? hardware.setInput(original)
        _ = try? waitFor(original)
    }
    do {
        try model.requestSwitch(to: target.id, original: original)
        after = try waitFor(target.id); switched = after == target.id; switchStatus = "noErr (0)"
        model.refresh(enforce: false)
        history = model.settings.interventions == 1 && model.recentIntervention
            && SettingsStore(defaults: defaults).load().interventions == 1
        try model.requestSwitch(to: original, original: target.id, recordHistory: false)
        restoreID = try waitFor(original); restored = restoreID == original
        model.allowBluetoothForOneHour()
        allowance = model.bluetoothAllowed && SettingsStore(defaults: defaults).load().bluetoothAllowedUntil != nil
        restoreStatus = restored ? "noErr (0)" : "Original input did not restore"
        model.resumeGuard()
        resumed = !model.bluetoothAllowed && model.settings.bluetoothAllowedUntil == nil
    } catch { switchStatus = (error as? HardwareError)?.diagnosticDescription ?? error.localizedDescription }
    let callbacks = callbackCount() - callbacksBefore
    let inputCount = devices.filter { $0.inputChannels > 0 }.count
    let noTransitionReason = inputCount == 1 ? "single input" : "no alternate available"
    let transition = distinct ? "confirmed" : "unknown (\(noTransitionReason); no distinct input transition)"
    return (switched && restored && history && allowance && resumed && (!distinct || callbacks > 0),
        "inputCount=\(inputCount); before=\(original) (\(before.name)); target=\(target.id); after=\(after); set=\(switchStatus); restored=\(restoreID); restore=\(restoreStatus); history=\(history); transition=\(transition); allowance=\(allowance); resume=\(resumed)")
}

/// Renders a SwiftUI view to a bitmap through a real window.
@MainActor func captureNativeView<V: View>(_ content: V, size: CGSize) throws -> NSImage {
    _ = NSApplication.shared
    let view = NSHostingView(rootView: content)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.setContentSize(size)
    view.frame = CGRect(origin: .zero, size: size)
    window.orderFront(nil)
    defer { window.orderOut(nil); window.close() }
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "CallReadyTests", code: 1) }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let image = NSImage(size: size)
    image.addRepresentation(bitmap)
    return image
}

/// A coordinator on isolated preferences, fixture hardware and a fixture clock.
@MainActor final class FixtureApp {
    let suite = "CallReady.app.fixture." + UUID().uuidString
    let defaults: UserDefaults
    let micHardware = TwelveDeviceHardware()
    let muteBackend = FixtureDevices()
    let calendar: CalendarModel
    let microphone: GuardModel
    let mute: MuteModel
    let app: CallCoordinator
    var clock: Date
    var notifications: [(String, String, String)] = []
    /// `asyncHardware` uses the shipping path: hardware work runs on the audio worker queue.
    init(now: Date = Date(timeIntervalSince1970: 1_800_000_000), asyncHardware: Bool = false) {
        clock = now
        defaults = UserDefaults(suiteName: suite)!
        calendar = CalendarModel(defaults: defaults, startTimer: false, now: now)
        microphone = GuardModel(hardware: micHardware, defaults: defaults, now: { [unowned calendar] in calendar.now }, scheduleEvents: asyncHardware)
        mute = MuteModel(storeDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite), backend: muteBackend, defaults: defaults)
        mute.registerShortcut = { _, _ in true }
        app = CallCoordinator(calendar: calendar, microphone: microphone, mute: mute, defaults: defaults)
        app.notify = { [unowned self] in self.notifications.append(($0, $1, $2)) }
    }
    /// Grants calendar access with the given events.
    func grant(_ events: [MeetEvent]) {
        calendar.authorized = true; calendar.accessDenied = false
        calendar.events = events
    }
    func close() {
        microphone.stop()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suite))
    }
}

/// Suspends until `done` is true or `timeout` passes. Suspension frees the main queue for the audio worker results.
@MainActor func spin(until done: () -> Bool, timeout: TimeInterval = 3) async {
    let end = Date().addingTimeInterval(timeout)
    while !done() && Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
}
