import SwiftUI
import Carbon
import MASKit
import StepQuayCore

@main
struct StepQuayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: AppModel
    init() {
        if CommandLine.arguments.contains("--smoke") { exit(SelfTest.run()) }
        if CommandLine.arguments.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { fputs("Screenshot failure \(error)\n", stderr); exit(1) }
        }
        _model = StateObject(wrappedValue: AppModel())
    }
    var body: some Scene {
        WindowGroup("StepQuay") {
            ContentView(model: model).onAppear { delegate.connect(model) }
        }.windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(model.l("Actions")) {
                Button(model.l(model.sampleMode ? "Use live queue" : "Try Sample")) { model.toggleSample(!model.sampleMode) }
                Button(model.l("Reset Sample")) { model.resetSample() }.disabled(!model.sampleMode)
            }
        }
        Settings { SettingsView(model: model) }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var panel: NSWindow?
    func connect(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        retainPanel()
        model.shortcutChanged = { [weak self] in self?.registerShortcut() }
        registerShortcut(); updateStatus()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self; item.button?.action = #selector(openPanel)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusItem = item
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.updateStatus() } }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().openPanel() }
            return noErr
        }, 1, &spec, context, &eventHandler)
        updateStatus()
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.change { $0.tick(ProcessInfo.processInfo.systemUptime); $0.recoverAfterLaunch() }
        if let hotKey { UnregisterEventHotKey(hotKey) }
    }
    @objc func openPanel() {
        NSApp.activate(ignoringOtherApps: true)
        retainPanel()
        panel?.makeKeyAndOrderFront(nil)
    }
    private func retainPanel() {
        if panel == nil { panel = NSApp.windows.first { $0.title == "StepQuay" } }
        panel?.isReleasedWhenClosed = false
    }
    private func registerShortcut() {
        guard let model else { return }
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        let keys: [String: UInt32] = ["K": UInt32(kVK_ANSI_K), "J": UInt32(kVK_ANSI_J), "U": UInt32(kVK_ANSI_U), "P": UInt32(kVK_ANSI_P), "L": UInt32(kVK_ANSI_L), "Space": UInt32(kVK_Space)]
        let modifiers: UInt32 = model.shortcutModifiers == "controlOption" ? UInt32(controlKey | optionKey) : model.shortcutModifiers == "commandShift" ? UInt32(cmdKey | shiftKey) : UInt32(cmdKey | optionKey)
        let id = EventHotKeyID(signature: 0x53514559, id: 1)
        let status = RegisterEventHotKey(keys[model.shortcutKey] ?? UInt32(kVK_ANSI_K), modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        model.shortcutError = status == noErr ? "" : model.l("Shortcut unavailable. Choose another combination in Settings. The menu bar button still works.") + " (\(status))"
    }
    private func updateStatus() {
        retainPanel()
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: model?.symbol ?? "list.bullet", accessibilityDescription: model?.menuLabel ?? "StepQuay")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.title = model?.showTime == true && model?.queue.current != nil ? " " + TimeText.clock(model!.queue.current!.remaining) : ""
        button.setAccessibilityLabel(model?.menuLabel ?? "StepQuay")
        button.toolTip = model?.menuLabel ?? "StepQuay"
    }
}
