import SwiftUI
import CacheSlopeCore
import MASKit

@main struct CacheSlopeApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    @StateObject var model: Model
    init() {
        if CommandLine.arguments.contains("--smoke") { exit(Smoke.run()) }
        if CommandLine.arguments.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
        }
        _model = StateObject(wrappedValue: Model())
    }
    var body: some Scene {
        WindowGroup { ContentView(model: model).onAppear { delegate.model = model } }.windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
        Settings { SettingsView(model: model) }.windowResizability(.contentSize)
    }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: Model? { didSet { NSApp.windows.first { $0.canBecomeKey }?.delegate = self } }
    var item: NSStatusItem?
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.target = self; item?.button?.action = #selector(show)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.update() } }
        update()
    }
    func update() {
        item?.button?.image = NSImage(systemSymbolName: model?.symbol ?? "folder", accessibilityDescription: model?.state ?? "No baseline")
        item?.button?.title = model?.sample == true ? " Sample" : ""
        item?.button?.toolTip = model?.state ?? "CacheSlope"
        item?.button?.setAccessibilityLabel("CacheSlope · " + (model?.state ?? "No baseline"))
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    @objc func show() { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.title == "CacheSlope" && $0.canBecomeKey }?.makeKeyAndOrderFront(nil) }
}
enum Smoke {
    @MainActor static func run() -> Int32 {
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("Cache"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("Cache/a")
            try Data(repeating: 1, count: 12).write(to: file)
            let before = Scanner.scan(dir)
            try Data(repeating: 1, count: 29).write(to: file)
            let after = Scanner.scan(dir)
            let changes = Analysis.compare(after, to: before)
            let partial = Scanner.scan(dir, cancelled: { true })
            let checks = [SmokeCheck(name: "Real logical size scan", pass: before.total == 12 && after.total == 29 && before.sizes["Cache"] == 12 && after.sizes["Cache"] == 29, detail: "Temporary sandbox files measured"), SmokeCheck(name: "Growth comparison", pass: changes.first?.delta == 17, detail: "Complete snapshots compared"), SmokeCheck(name: "Cancellation excludes partial", pass: !partial.complete && Analysis.compare(partial, to: before).isEmpty, detail: "Cancelled scan cannot compare"), SmokeCheck(name: "Sample isolation", pass: Fixtures.history.count == 2 && Fixtures.partial.complete == false, detail: "Fictional data is separate")]
            let report = SmokeReport(app: "CacheSlope", bundleID: "com.michaellip.cacheslope", version: "1.0.0", checks: checks)
            try report.write(); return report.pass ? 0 : 1
        } catch { fputs("\(error)\n", stderr); return 1 }
    }
}
