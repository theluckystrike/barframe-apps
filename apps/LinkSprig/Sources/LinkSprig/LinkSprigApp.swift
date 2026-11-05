import SwiftUI
import AppKit
import Combine
import Carbon
import LinkSprigCore

@main
struct LinkSprigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: AppModel
    init() {
        let args = CommandLine.arguments
        if args.contains("--smoke") { exit(SelfTest.run()) }
        if args.contains("--screenshots") {
            do { try ScreenshotRenderer.render(); exit(0) } catch { fputs("Screenshot render failed \(error)\n", stderr); exit(1) }
        }
        _model = StateObject(wrappedValue: AppModel())
    }
    var body: some Scene {
        Window("LinkSprig", id: "detail") {
            DetailScene(model: model, delegate: delegate)
        }.defaultSize(width: 820, height: 640)
        .commands { CommandGroup(replacing: .newItem) {}; CommandGroup(after: .appInfo) { Button(model.tr("See Sample", "Ver Sample")) { model.setSample(true) }.keyboardShortcut("s", modifiers: [.command, .shift]) } }
        Settings { SettingsView(model: model) }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var popover = NSPopover()
    private weak var model: AppModel?
    private var changes: AnyCancellable?
    private var hotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var openDetail: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.target = self; item?.button?.action = #selector(togglePanel)
        item?.button?.image = NSImage(systemSymbolName: "link", accessibilityDescription: "LinkSprig")
        item?.button?.image?.isTemplate = true
        popover.behavior = .transient
    }
    func connect(_ model: AppModel, openDetail: @escaping () -> Void) {
        self.openDetail = openDetail
        guard self.model == nil else { return }
        self.model = model
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, openWindow: { [weak self] in self?.showWindow() }))
        model.shortcutChanged = { [weak self] in self?.registerShortcut() }
        changes = model.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateState() } }
        updateState(); registerShortcut()
    }
    private func updateState() {
        guard let model else { return }
        item?.button?.title = " " + model.menuTitle
        let base = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        let badge = NSImage(systemSymbolName: model.busy ? "arrow.triangle.2.circlepath" : model.badge, accessibilityDescription: nil)
        let icon = NSImage(size: NSSize(width: 26, height: 18), flipped: false) { _ in
            base?.draw(in: NSRect(x: 0, y: 1, width: 17, height: 17))
            badge?.draw(in: NSRect(x: 17, y: 0, width: 9, height: 9))
            return true
        }
        icon.isTemplate = true
        item?.button?.image = icon
        let time = model.plan?.scannedAt.formatted(date: .abbreviated, time: .shortened) ?? model.tr("No completed check", "Sin revisión completada")
        item?.button?.toolTip = (model.sampleMode ? "Sample · " : "") + "LinkSprig · \(model.status) · \(time)"
        item?.button?.setAccessibilityLabel(item?.button?.toolTip)
    }
    @objc func togglePanel() {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil) } else { NSApp.activate(ignoringOtherApps: true); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func showWindow() {
        popover.performClose(nil); NSApp.activate(ignoringOtherApps: true)
        openDetail?()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationDidBecomeActive(_ notification: Notification) { model?.becameActive() }
    func applicationWillTerminate(_ notification: Notification) { model?.cancel(); if let hotkey { UnregisterEventHotKey(hotkey) }; if let eventHandler { RemoveEventHandler(eventHandler) } }
    func registerShortcut() {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        guard let model else { return }
        model.shortcutError = ""
        guard model.shortcutKey != UInt32.max else { return }
        if eventHandler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in delegate.togglePanel() }; return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            if status != noErr { model.shortcutError = model.tr("Shortcut handler failed", "Error de controlador de atajo") + " \(status)"; return }
        }
        let status = RegisterEventHotKey(model.shortcutKey, model.shortcutModifiers, EventHotKeyID(signature: 0x4C535052, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        if status != noErr { model.shortcutError = model.tr("Shortcut unavailable. Choose another key.", "Atajo no disponible. Elige otra tecla.") + " \(status)" }
    }
}

struct DetailScene: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView(model: model).onAppear { delegate.connect(model, openDetail: { openWindow(id: "detail") }) }
    }
}
