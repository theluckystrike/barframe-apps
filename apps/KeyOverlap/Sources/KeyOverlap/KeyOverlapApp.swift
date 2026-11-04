import SwiftUI
import AppKit
import Combine
import KeyOverlapCore

@main
struct KeyOverlapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: AppModel
    init() {
        let arguments = CommandLine.arguments
        if arguments.contains("--smoke") { exit(SelfTest.run()) }
        if arguments.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { fputs("Screenshots failed \(error.localizedDescription)\n", stderr); exit(1) }
        }
        _model = StateObject(wrappedValue: AppModel())
    }
    var body: some Scene {
        WindowGroup("KeyOverlap", id: "planner") {
            PlannerRootView(model: model, delegate: delegate)
        }.defaultSize(width: 920, height: 750).windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { LabeledButton(model.l("Open planner", "Abrir plan")) { AppDelegate.openPlanner() } }
            CommandGroup(after: .appSettings) {
                LabeledButton(model.l("Try Sample", "Probar ejemplo")) { model.toggleSample(true); AppDelegate.openPlanner() }
            }
        }
        Settings { SettingsView(model: model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    static var reopen: (() -> Void)?
    private var item: NSStatusItem?
    private var observation: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.target = self; status.button?.action = #selector(open)
        item = status; update()
    }
    func connect(_ value: AppModel) {
        if model === value { return }
        model = value
        observation = value.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }
        value.registerShortcut(); update()
    }
    private func update() {
        item?.button?.image = NSImage(systemSymbolName: model?.statusSymbol ?? "keyboard", accessibilityDescription: model?.menuLabel ?? "KeyOverlap plan")
        item?.button?.image?.isTemplate = true
        item?.button?.setAccessibilityLabel(model?.menuLabel ?? "KeyOverlap plan")
        item?.button?.toolTip = model?.menuLabel ?? "KeyOverlap plan"
    }
    @objc private func open() { Self.openPlanner() }
    static func openPlanner() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("planner") == true || $0.title == "KeyOverlap" }) { window.makeKeyAndOrderFront(nil) }
        else { reopen?() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct PlannerRootView: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView(model: model).onAppear {
            delegate.connect(model)
            AppDelegate.reopen = { openWindow(id: "planner") }
        }
    }
}
