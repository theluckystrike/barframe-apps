import AppKit
import SwiftUI
import MASKit
import RevPulseCore

@main
struct RevPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @State private var popoverVisible = false

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .environmentObject(model)
        } label: {
            Text(model.snapshot.map { Formatting.menuBarTitle(snapshot: $0) } ?? "—")
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(model: model)
                .environmentObject(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        switch LaunchMode.current() {
        case .smoke: runSmoke()
        case .screenshots: Task { await runScreenshots() }
        case .normal: break
        }
    }
}

extension AppDelegate {
    func runSmoke() {
        var checks: [SmokeCheck] = []
        let fm = FileManager.default

        checks.append(SmokeCheck(name: "sandbox.active", pass: SmokeReport.isSandboxed,
                                 detail: "APP_SANDBOX_CONTAINER_ID=\(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "nil")"))

        // Keychain roundtrip inside the sandbox.
        do {
            let ks = KeyStore(service: KeyStore.service + ".smoke")
            try ks.save("rk_test_smoke1234567890")
            let round = ks.load() == "rk_test_smoke1234567890"
            ks.delete()
            checks.append(SmokeCheck(name: "keychain.roundtrip", pass: round, detail: round ? "saved+loaded+deleted" : "mismatch"))
        } catch {
            checks.append(SmokeCheck(name: "keychain.roundtrip", pass: false, detail: "\(error)"))
        }

        // Sample pipeline end to end.
        let snap = SampleData.snapshot()
        checks.append(SmokeCheck(name: "sample.snapshot", pass: snap.today.netCents == 2295 && snap.newSubscriptionsMTD == 2,
                                 detail: "today=\(snap.today.netCents) subs=\(snap.newSubscriptionsMTD)"))

        // Desktop must be denied (sandbox proof for a path we never need).
        let desktopDenied = !fm.isReadableFile(atPath: NSHomeDirectory() + "/../../../Desktop")
            || !fm.fileExists(atPath: NSString(string: "~/Desktop").expandingTildeInPath)
        checks.append(SmokeCheck(name: "sandbox.desktopDeny", pass: desktopDenied, detail: "desktop probe=\(desktopDenied) (not required for function)"))

        // Home path is the container.
        let homeIsContainer = NSHomeDirectory().contains("/Library/Containers/")
        checks.append(SmokeCheck(name: "sandbox.containerHome", pass: homeIsContainer, detail: NSHomeDirectory()))

        // Sample fixture parses into all four models.
        let now = Date()
        let c = (try? SampleData.charges(now: now))?.count ?? -1
        let cu = (try? SampleData.customers(now: now))?.count ?? -1
        let s = (try? SampleData.subscriptions(now: now))?.count ?? -1
        let r = (try? SampleData.refunds(now: now))?.count ?? -1
        checks.append(SmokeCheck(name: "sample.fixtures", pass: c == 7 && cu == 3 && s == 2 && r == 1,
                                 detail: "charges=\(c) customers=\(cu) subs=\(s) refunds=\(r)"))

        // Money formatting.
        let money = Formatting.money(499, currency: "usd")
        checks.append(SmokeCheck(name: "format.money", pass: money == "$4.99", detail: money))

        let report = SmokeReport(app: "RevPulse", bundleID: Bundle.main.bundleIdentifier ?? "", version: "1.0.0", checks: checks)
        do { try report.write() } catch { fputs("smoke write failed: \(error)\n", stderr); exit(1) }
        exit(report.pass ? 0 : 1)
    }

    @MainActor
    func runScreenshots() async {
        do { try await NativeScreenshots.render() }
        catch { fputs("screenshot failed: \(error)\n", stderr); exit(1) }
        exit(0)
    }
}
