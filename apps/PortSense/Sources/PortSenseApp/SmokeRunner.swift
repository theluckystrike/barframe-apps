import Foundation
import Darwin
import IOKit
import IOKit.ps
import MASKit
import PortSenseCore

/// Smoke checks exercise real system APIs and the packaged, sandboxed resources.
enum SmokeRunner {
    static func run() -> Never {
        var checks: [SmokeCheck] = []
        func check(_ name: String, _ operation: () throws -> (Bool, String)) {
            do {
                let (passed, detail) = try operation()
                checks.append(SmokeCheck(name: name, pass: passed, detail: detail))
            } catch { checks.append(SmokeCheck(name: name, pass: false, detail: error.localizedDescription)) }
        }
        check("IOPowerSources snapshot") {
            let snapshot = try PowerReader.read()
            return (snapshot.supply != .unknown, "source=\(snapshot.supply.rawValue), count=\(snapshot.sourceCount), charge=\(String(describing: snapshot.battery?.chargePercent))")
        }
        check("External adapter or battery verdict") {
            let snapshot = try PowerReader.read()
            if snapshot.supply == .battery {
                return (snapshot.battery != nil, "On battery; adapter is optional")
            }
            // A desktop or UPS may have no external adapter details. Prove AC/UPS using IOPS itself.
            guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return (false, "No source verdict") }
            return (type == kIOPMACPowerKey || type == kIOPMUPSPowerKey, "source=\(type), adapter=\(ReadingFormat.watts(snapshot.adapter?.watts))")
        }
        check("USB enumeration KERN_SUCCESS") {
            let devices = try ConnectionReader.readUSB()
            return (Set(devices.map(\.id)).count == devices.count, "KERN_SUCCESS; devices=\(devices.count)")
        }
        check("USB speed decoding with live enumeration") {
            let devices = try ConnectionReader.readUSB()
            let expected = [1: "12 Mb/s", 2: "1.5 Mb/s", 3: "480 Mb/s", 4: "5 Gb/s", 5: "10 Gb/s", 6: "20 Gb/s"]
            let correct = expected.allSatisfy { USBSpeed.label(code: $0.key) == $0.value }
            return (correct && devices.allSatisfy { !$0.speedLabel.isEmpty }, "KERN_SUCCESS; live speeds=\(devices.map(\.speedLabel)); verified XHCI IDs 1...6")
        }
        check("Battery registry properties") {
            let entries = try RegistryReader.entries(className: "AppleSmartBattery")
            return (entries.allSatisfy { !$0.properties.isEmpty }, "KERN_SUCCESS; battery registry entries=\(entries.count)")
        }
        check("Power battery and USB notification registration") {
            let observer = SystemNotifications { _ in }
            observer.start()
            defer { observer.stop() }
            return (observer.errors.isEmpty, observer.errors.isEmpty ? "IOPS source, battery interest when present, USB add/remove installed; callbacks schedule worker reads" : observer.errors.joined(separator: "; "))
        }
        check("Optional live input and battery telemetry") {
            let snapshot = try PowerReader.read()
            let valid = snapshot.inputWatts.map { $0.isFinite && $0 >= 0 } ?? true
            return (valid, "input=\(DetailFormat.watts(snapshot.inputWatts)); signed battery=\(DetailFormat.watts(snapshot.battery?.signedWatts)); temperature=\(DetailFormat.temperature(snapshot.battery?.temperatureCelsius)); USB/Thunderbolt attached-device breadth remains unverified")
        }
        check("Live wattage history container roundtrip") {
            var history = WattageHistory()
            for _ in 0..<65 {
                history.append(WattageSample(snapshot: try PowerReader.read()))
            }
            let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("portsense-smoke-history.json")
            defer { try? FileManager.default.removeItem(at: url) }
            try history.write(to: url)
            let decoded = try WattageHistory.read(from: url)
            return (history.samples.count == 60 && decoded.samples.count == history.samples.count && decoded.samples.map(\.watts) == history.samples.map(\.watts) && decoded.samples.map(\.supply) == history.samples.map(\.supply), "Bounded ring and atomic write/read of \(decoded.samples.count) live samples in container")
        }
        check("Bundled privacy and support are readable in the sandbox") {
            let texts = PortPage.allCases.map { PortLinks.localText($0) }
            let valid = texts.allSatisfy { $0.count > 300 && $0.contains("Michael Lip") && !$0.contains("{") }
            return (valid, "Packaged Contents/Resources pages; characters=\(texts.map(\.count)); no unresolved identity")
        }
        check("Desktop sandbox denial") {
            guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return (false, "getpwuid failed") }
            let desktop = URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Desktop")
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: desktop.path)
                return (false, "Desktop readable: \(files.count) entries")
            } catch {
                let cocoa = error as NSError
                let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? NSError
                let denied = (cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileReadNoPermissionError) ||
                    (underlying?.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(underlying?.code ?? 0))
                return (denied, "\(desktop.path): \(cocoa.domain) \(cocoa.code), underlying=\(underlying?.code ?? 0)")
            }
        }
        let report = SmokeReport(app: "PortSense", bundleID: Bundle.main.bundleIdentifier ?? "com.unfinalized.portsense", version: "1.0.0", checks: checks)
        do { try report.write() }
        catch { fputs("Smoke report write failed: \(error.localizedDescription)\n", stderr); exit(1) }
        exit(report.pass ? 0 : 1)
    }
}
