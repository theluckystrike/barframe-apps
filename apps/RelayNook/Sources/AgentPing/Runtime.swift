import SwiftUI
import AgentPingCore
import UserNotifications
import ServiceManagement
import ImageIO
import UniformTypeIdentifiers

private final class SettingsResult: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int?
    func put(_ value: Int) { lock.lock(); status = value; lock.unlock() }
    func get() -> Int? { lock.lock(); defer { lock.unlock() }; return status }
}

@MainActor enum Runtime {
    static func selftest() -> Never {
        var checks: [[String: Any]] = []
        func check(_ name: String, _ pass: Bool, _ detail: String) {
            checks.append(["name": name, "pass": pass, "detail": detail])
        }
        let token = "0123456789abcdef0123456789abcdef" // Fixture credential for parser checks.
        func parse(_ raw: String) -> AgentEvent? { EventParser.parse(raw, token: token) }
        let base = "agentping://event?agent=test&kind=waiting&title=probe&project=Sample&session=s1&token=0123456789abcdef0123456789abcdef"
        let valid = [base, base.replacingOccurrences(of: "waiting", with: "done"), base.replacingOccurrences(of: "waiting", with: "error"), base.replacingOccurrences(of: "waiting", with: "info"), base.replacingOccurrences(of: "probe", with: "encoded%20%26%20%E2%9C%93")]
        let invalid = ["https://event?agent=test", base.replacingOccurrences(of: "waiting", with: "bad"), base + "&agent=duplicate", base.replacingOccurrences(of: "probe", with: "%ZZ"), base.replacingOccurrences(of: "session=s1", with: "session=")]
        check("URL parser", valid.allSatisfy { parse($0) != nil } && invalid.allSatisfy { parse($0) == nil }, "URLComponents: 5 valid accepted; 5 invalid rejected")
        let clamped = parse(base.replacingOccurrences(of: "probe", with: String(repeating: "x", count: 400)))
        check("Field limits", clamped?.title.count == 240, "Title limit: 240 characters")
        var history = History()
        var counts: [Int] = []
        for (session, kind) in [("a", EventKind.waiting), ("a", .waiting), ("b", .waiting), ("a", .done), ("b", .info), ("a", .waiting), ("a", .error)] {
            history.receive(AgentEvent(agent: "selftest", kind: kind, title: "Selftest event", project: "", session: session))
            counts.append(history.waitingCount)
        }
        check("Session badge", counts == [1, 1, 2, 1, 0, 1, 0], "Received sequence produces \(counts)")
        let url = AppModel.supportDirectory.appendingPathComponent("selftest-\(UUID().uuidString).json")
        do {
            try history.save(to: url)
            let reloaded = try History.load(from: url)
            check("Container history", reloaded == history && url.path.contains("/Library/Containers/"), "JSON write/read: \(url.path); \(reloaded.events.count) events")
            try FileManager.default.removeItem(at: url)
        } catch { check("Container history", false, error.localizedDescription) }
        let result = SettingsResult()
        UNUserNotificationCenter.current().getNotificationSettings { result.put($0.authorizationStatus.rawValue) }
        let deadline = Date().addingTimeInterval(10)
        while result.get() == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        check("Notification settings", result.get() != nil, "UNUserNotificationCenter status: \(result.get().map(String.init) ?? "unknown; getNotificationSettings timed out"); no permission prompt")
        check("Launch at login status", true, "SMAppService.mainApp.status raw value: \(SMAppService.mainApp.status.rawValue)")
        do {
            let credential = try InstallationToken.load()
            let randomProbe = try InstallationToken.randomValue()
            check("Installation credential", credential.count == 32 && randomProbe.count == 32 && randomProbe != credential && UserDefaults.standard.string(forKey: InstallationToken.key) == credential, "SecRandomCopyBytes and container UserDefaults; 128-bit credential persisted; value withheld")
        } catch { check("Installation credential", false, "Credential creation failed") }
        let sandboxed = NSHomeDirectory().contains("/Library/Containers/")
        var output: [String: Any] = ["app": "RelayNook", "version": "1.0.0", "sandboxed": sandboxed, "checks": checks]
        output["home"] = NSHomeDirectory()
        output["pass"] = sandboxed && checks.allSatisfy { $0["pass"] as? Bool == true }
        let data = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        if CommandLine.arguments.contains("--smoke") {
            try! data.write(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("smoke.json"), options: .atomic)
        }
        print(String(decoding: data, as: UTF8.self))
        exit(sandboxed && checks.allSatisfy { $0["pass"] as? Bool == true } ? 0 : 1)
    }

    static func render(to directory: URL) -> Never {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
            let model = AppModel(token: SampleContent.token, historyURL: directory.appendingPathComponent("unused.json"), notificationAuthorization: { .denied })
            model.setSampleMode(true)
            model.notificationStatus = "Sample: permission not requested"
            for index in 0..<3 {
                let view = ScreenshotView(model: model, variant: index)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.orderFront(nil)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                window.orderOut(nil)
                guard let cgImage = bitmap.cgImage,
                      let context = CGContext(data: nil, width: 2880, height: 1800,
                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
                context.setFillColor(CGColor(red: 0.078, green: 0.063, blue: 0.063, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
                let name = ["history", "setup", "security"][index]
                guard let opaqueImage = context.makeImage(),
                      let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
                CGImageDestinationAddImage(destination, opaqueImage, nil)
                guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Screenshot error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

struct ScreenshotView: View {
    @ObservedObject var model: AppModel
    let variant: Int
    var body: some View {
        HStack(spacing: 60) {
            VStack(alignment: .leading, spacing: 24) {
                Text("RelayNook · Sample").font(.title2)
                Text(SampleContent.headlines[variant]).font(.system(size: 42, weight: .semibold))
                Text(["Session counts and local history.", "Optional hooks and a no-install test.", "Notification choices and event security."][variant]).font(.title3).foregroundStyle(.secondary)
            }.frame(width: 400, alignment: .leading)
            Group {
                if variant == 0 { PopoverView(model: model) }
                else { SettingsView(selectedTab: variant == 1 ? 1 : 0, model: model) }
            }.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }.frame(width: 1440, height: 900)
            .background(Color(red: 0.055, green: 0.10, blue: 0.12))
            .environment(\.colorScheme, .dark)
    }
}
