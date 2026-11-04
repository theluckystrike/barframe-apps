import SwiftUI
import AppKit
import Carbon
import Combine
import MASKit
import RouteLoomCore

@main
struct RouteLoomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: AppModel
    init() {
        let args = CommandLine.arguments
        if args.contains("--smoke") { exit(SelfTest.run()) }
        if args.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("screenshots"));exit(0) }
            catch { fputs("Screenshot failed \(error)\n",stderr);exit(1) }
        }
        _model = StateObject(wrappedValue:AppModel())
    }
    var body: some Scene {
        Window("RouteLoom",id:"main") { PanelScene(model:model,delegate:delegate) }
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing:.newItem) {} }
        Settings { SettingsView(model:model) }
    }
}
struct PanelScene: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    var body: some View {
        ContentView(model:model).onAppear {
            delegate.showWindow = { openWindow(id:"main") }
            delegate.model = model
        }
    }
}
@MainActor
final class AppDelegate: NSObject,NSApplicationDelegate {
    var model: AppModel? { didSet { connect() } }
    var statusItem: NSStatusItem?
    var showWindow: (() -> Void)?
    private var window: NSWindow?
    private var observer: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?
    private var subscription: AnyCancellable?
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var lastShortcut = -1
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem?.button?.target = self;statusItem?.button?.action = #selector(openPanel)
        observer = NotificationCenter.default.addObserver(forName:.routeWindow,object:nil,queue:.main) { [weak self] n in
            if let w = n.object as? NSWindow { Task { @MainActor in self?.window = w;w.isReleasedWhenClosed = false } }
        }
        keyObserver = NotificationCenter.default.addObserver(forName:.routeHotkey,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.openIncident() } }
        var spec = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _,_,_ in
            DispatchQueue.main.async { NotificationCenter.default.post(name:.routeHotkey,object:nil) };return noErr
        },1,&spec,nil,&handler)
        connect();update()
    }
    private func connect() {
        subscription = model?.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }
        update()
    }
    func update() {
        guard let model else { statusItem?.button?.image = NSImage(systemSymbolName:"network",accessibilityDescription:"RouteLoom idle");return }
        let image = NSImage(systemSymbolName:model.menuSymbol,accessibilityDescription:model.menuLabel)
        image?.isTemplate = true;statusItem?.button?.image = image
        statusItem?.button?.imagePosition = .imageLeading
        statusItem?.button?.title = model.sample ? " Sample" : model.showMenuText ? " " + model.tr(model.running ? "Running" : "Stopped") : ""
        statusItem?.button?.setAccessibilityLabel("RouteLoom " + model.menuLabel)
        statusItem?.button?.toolTip = "RouteLoom · " + model.menuLabel
        if lastShortcut != model.shortcut { register(model.shortcut) }
    }
    private func register(_ value:Int) {
        lastShortcut = value
        if let key { UnregisterEventHotKey(key);self.key = nil }
        guard value != 2 else { model?.shortcutError = nil;return }
        let modifiers = value == 0 ? UInt32(controlKey | optionKey) : UInt32(cmdKey | shiftKey)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_R),modifiers,EventHotKeyID(signature:0x524C4F4D,id:1),GetApplicationEventTarget(),0,&key)
        model?.shortcutError = result == noErr ? nil : "Shortcut unavailable. Choose another shortcut in Settings or use the menu bar."
    }
    @objc func openPanel() {
        showWindow?()
        NSApp.activate(ignoringOtherApps:true)
        (window ?? NSApp.windows.first { $0.title == "RouteLoom" })?.makeKeyAndOrderFront(nil)
    }
    func openIncident() { model?.selectedID = model?.current?.id;openPanel() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification:Notification) { model?.stop();if let key { UnregisterEventHotKey(key) };if let handler { RemoveEventHandler(handler) } }
}
