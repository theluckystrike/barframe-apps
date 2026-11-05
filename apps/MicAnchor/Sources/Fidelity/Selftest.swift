import CoreAudio
import Foundation
import FidelityCore

private struct Check: Encodable { let name: String; let pass: Bool; let detail: String }
private struct SelftestResult: Encodable {
    let app = "MicAnchor", version = "1.0.0"
    let sandboxed: Bool
    let checks: [Check]
}

@MainActor func runSelftest() -> Int32 {
    let hardware = AudioHardware()
    var checks: [Check] = []
    func run(_ name: String, _ body: () throws -> (Bool, String)) {
        do { let result = try body(); checks.append(Check(name: name, pass: result.0, detail: result.1)) }
        catch { checks.append(Check(name: name, pass: false,
            detail: (error as? HardwareError)?.diagnosticDescription ?? error.localizedDescription)) }
    }
    run("device_enumeration") {
        let devices = try hardware.devices()
        return (!devices.isEmpty, "count=\(devices.count); skipped=\(hardware.skippedIDs); " + devices.map {
            "id=\($0.id),name=\($0.name),transport=\($0.transport.rawValue),in=\($0.inputChannels),out=\($0.outputChannels),alive=\($0.isAlive),sourceAvailable=\($0.dataSourceAvailable)"
        }.joined(separator: "; "))
    }
    run("unreadable_device_isolation") {
        let devices = try hardware.devices()
        let readable = hardware.readDevices(ids: devices.map(\.id) + [kAudioObjectUnknown])
        return (readable == devices && hardware.skippedIDs == [kAudioObjectUnknown],
            "readable=\(readable.count); deliberately invalid object=0; skipped=\(hardware.skippedIDs); valid devices retained=\(readable == devices)")
    }
    run("default_input_output") {
        let devices = try hardware.devices()
        let input = try hardware.defaultInput(), output = try hardware.defaultOutput()
        return (devices.contains { $0.id == input && $0.inputChannels > 0 } && devices.contains { $0.id == output && $0.outputChannels > 0 },
                "input=\(input); output=\(output)")
    }
    run("switch_input_restore") { try switchAndRestore(hardware, callbackCount: { hardware.callbackCount }) }
    run("listeners_add_remove") {
        try hardware.startListening {}
        let results = hardware.stopListening()
        return (results.count == 3 && results.allSatisfy { $0 == noErr }, "add input/devices/output=noErr (0); remove=\(results)")
    }
    run("transport_classification") {
        let devices = try hardware.devices()
        let values = try devices.map { device -> String in
            let code = try hardware.uint32(device.id, kAudioDevicePropertyTransportType)
            guard Transport.classify(code) == device.transport else { throw HardwareError(operation: "Transport mismatch", status: -1) }
            return "id=\(device.id),code=\(String(code, radix: 16)),transport=\(device.transport.rawValue)"
        }
        let target = GuardDecision.preferredDevice(in: devices, uid: nil, lidClosed: hardware.lidClosed() == true)
        return (!values.isEmpty && target.map { $0.isSafeInput && $0.transport.automaticRank != nil } != false,
            values.joined(separator: "; ") + "; automatic=\(target?.name ?? "No wired microphone")")
    }
    run("microphone_availability") {
        let devices = try hardware.devices().filter { $0.inputChannels > 0 }
        let lid = hardware.lidClosed().map(String.init) ?? "unknown"
        return (!devices.isEmpty, "AppleClamshellState=\(lid); " + devices.map {
            "id=\($0.id),alive=\($0.isAlive),sourceAvailable=\($0.dataSourceAvailable)"
        }.joined(separator: "; "))
    }
    let sandboxed = NSHomeDirectory().contains("/Library/Containers/")
    do {
        let data = try JSONEncoder().encode(SelftestResult(sandboxed: sandboxed, checks: checks))
        if CommandLine.arguments.contains("--smoke") {
            var report = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            report["pass"] = checks.allSatisfy(\.pass); report["home"] = NSHomeDirectory()
            try JSONSerialization.data(withJSONObject: report).write(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("smoke.json"))
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    } catch { return 1 }
    return sandboxed && checks.allSatisfy(\.pass) ? 0 : 1
}

@MainActor func switchAndRestore(_ hardware: any AudioHardwareAccess, callbackCount: () -> Int) throws -> (Bool, String) {
    let devices = try hardware.devices(), original = try hardware.defaultInput()
    guard let before = devices.first(where: { $0.id == original && $0.inputChannels > 0 }) else { return (false, "Original input unavailable") }
    let inputs = devices.filter { $0.isSafeInput && !(hardware.lidClosed() == true && $0.transport == .builtIn) }
    let target = inputs.first { $0.id != original } ?? before
    let suite = "Fidelity.selftest.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { return (false, "Isolated preferences unavailable") }
    defer { defaults.removePersistentDomain(forName: suite) }
    // Exercise real history, listeners, allowance and restoration with isolated product preferences.
    SettingsStore(defaults: defaults).save(GuardSettings(enabled: false))
    let model = GuardModel(hardware: hardware, defaults: defaults, scheduleEvents: false)
    model.start()
    defer { model.stop() }
    let callbacksBefore = callbackCount()
    let distinct = target.id != original
    var switched = false, restored = false, after: UInt32 = 0, restoreID: UInt32 = 0
    var switchStatus = "not attempted", restoreStatus = "not attempted"
    var history = false, allowance = false, resumed = false
    func waitFor(_ id: UInt32, modelConfirmed: () -> Bool = { true }) throws -> UInt32 {
        for _ in 0..<10 {
            // Deliver real CoreAudio listener callbacks and deferred model verification.
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            model.refresh(enforce: false)
            let actual = try hardware.defaultInput()
            if actual == id && modelConfirmed() { return actual }
        }
        return try hardware.defaultInput()
    }
    defer {
        // Restore even if model verification fails.
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
    let mode = distinct ? "different input" : "self-write; no alternate available; callback transition unknown"
    let inputCount = devices.filter { $0.inputChannels > 0 }.count
    let noTransitionReason = inputCount == 1 ? "single input" : "no alternate available"
    let transition = distinct ? "confirmed" : "unknown (\(noTransitionReason); no distinct input transition)"
    return (switched && restored && history && allowance && resumed && (!distinct || callbacks > 0),
        "mode=\(mode); inputCount=\(inputCount); before=\(original) (\(before.name)); target=\(target.id) (\(target.name)); after=\(after); switched=\(switched); set=\(switchStatus); restored=\(restoreID); restorePass=\(restored); restore=\(restoreStatus); history=\(history); transition=\(transition); allowance=\(allowance); resume=\(resumed); listenerCallbacks=\(callbacks); path=GuardModel.requestSwitch/refresh; automaticBluetooth=unknown unless physical Bluetooth is measured")
}
