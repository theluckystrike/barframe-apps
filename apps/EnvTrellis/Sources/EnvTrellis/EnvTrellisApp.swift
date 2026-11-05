import AppKit
import SwiftUI
import Carbon
import Darwin
import MASKit

@main
struct EnvTrellisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel
    init() {
        let args = CommandLine.arguments
        if args.contains("--smoke") { exit(SelfTest.run()) }
        if args.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { exit(1) }
        }
        _model = StateObject(wrappedValue: AppModel())
    }
    var body: some Scene {
        Window("EnvTrellis", id: "matrix") {
            ContentView(model: model).onAppear { delegate.attach(model: model) }
        }.defaultSize(width: 950, height: 710)
            .commands { CommandGroup(replacing: .newItem) {}; CommandGroup(after: .appSettings) { Button(model.t("Rescan all")) { model.scan() }.keyboardShortcut("r", modifiers: [.command]) } }
        MenuBarExtra {
            SummaryView(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.state == .noInputs ? "leaf" : "leaf.fill")
                if model.scanning { ProgressView().controlSize(.mini) } else { Text(model.badge) }
                if model.sampleMode { Text("S") }
            }.accessibilityLabel("EnvTrellis " + model.menuState + " " + model.lastScanText + (model.sampleMode ? " Sample" : ""))
                .help("EnvTrellis " + model.menuState + " " + model.lastScanText + (model.sampleMode ? " Sample" : ""))
        }.menuBarExtraStyle(.window)
        Settings { SettingsView(model: model) }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationDidBecomeActive(_ notification: Notification) { model?.refreshStale() }
    func attach(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.shortcutChanged = { [weak self] in self?.registerShortcut() }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                NSApp.activate(ignoringOtherApps: true)
                delegate.model?.openPanel?()
                delegate.model?.refreshStale()
            }
            return noErr
        }, 1, &type, pointer, &handler)
        if status != noErr { model.shortcutError = "Shortcut registration failed. Use the menu bar to open the panel." }
        else { registerShortcut() }
    }
    func registerShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        let codes: [String: UInt32] = ["E": 14, "R": 15, "T": 17, "Y": 16, "U": 32]
        let id = EventHotKeyID(signature: 0x4554524c, id: 1)
        let status = RegisterEventHotKey(codes[model?.shortcutKey ?? "E"] ?? 14, UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey)
        model?.shortcutError = status == noErr ? "" : "Shortcut registration failed. Use the menu bar to open the panel."
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
