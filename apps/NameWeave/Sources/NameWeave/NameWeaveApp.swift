import SwiftUI
import Combine
import Carbon
import Darwin
import NameWeaveCore

@main
struct NameWeaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        if CommandLine.arguments.contains("--smoke") { exit(SelfTest.run()) }
        if CommandLine.arguments.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { fputs("Screenshot failed \(error)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        Settings { SettingsView(model: delegate.model) }
    }
}
private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let context else { return OSStatus(eventNotHandledErr) }
    let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { owner.togglePanel() }
    return noErr
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    override init() { model = AppModel(); super.init() }
    init(model: AppModel) { self.model = model; super.init() }
    private var status: NSStatusItem?
    private var popover = NSPopover()
    private var detailWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var shortcutSignature = ""
    var isStatusInstalled: Bool { status != nil }
    var hasDetailWindow: Bool { detailWindow != nil }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        install(model)
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.markStaleOnReturn() }
    func install(_ model: AppModel) {
        guard status == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self; item.button?.action = #selector(togglePanel)
        item.button?.font = .systemFont(ofSize: 12, weight: .semibold)
        status = item
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SummaryView(model: model, detail: { [weak self] in self?.showDetail() }))
        model.onChange = { [weak self] in self?.updateStatus() }
        subscription = model.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatus() } }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        updateStatus()
    }
    func applicationWillTerminate(_ notification: Notification) { model.persist(); if let hotkey { UnregisterEventHotKey(hotkey) }; if let handler { RemoveEventHandler(handler) } }
    func updateStatus() {
        let image = NSImage(systemSymbolName: "textformat", accessibilityDescription: model.stateAccessibility)
        image?.isTemplate = true; status?.button?.image = image
        status?.button?.title = " " + model.badge + (model.sample ? " S" : "")
        status?.button?.toolTip = model.stateAccessibility
        status?.button?.setAccessibilityLabel(model.stateAccessibility)
        registerShortcut()
    }
    private func registerShortcut() {
        let signature = model.shortcutModifier + model.shortcutKey
        guard signature != shortcutSignature else { return }
        shortcutSignature = signature
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        guard !model.shortcutKey.isEmpty else { model.shortcutError = nil; return }
        let keys: [String: UInt32] = ["N": 45, "W": 13, "P": 35, "K": 40]
        let modifiers = model.shortcutModifier == "commandShift" ? UInt32(cmdKey | shiftKey) : UInt32(controlKey | optionKey)
        let result = RegisterEventHotKey(keys[model.shortcutKey] ?? 45, modifiers, EventHotKeyID(signature: 0x4E575645, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        model.shortcutError = result == noErr ? nil : model.l("Shortcut unavailable. Choose a different key. System code ", "Atajo no disponible. Elige otra tecla. Código ") + String(result)
    }
    @objc func togglePanel() {
        guard let button = status?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    private func showDetail() {
        popover.performClose(nil); NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "NameWeave" }) { window.makeKeyAndOrderFront(nil) }
        else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 730), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "NameWeave"; window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: ContentView(model: model))
            window.center(); window.makeKeyAndOrderFront(nil); detailWindow = window
        }
    }
}
