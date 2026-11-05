import SwiftUI
import Carbon
import MASKit
import HashDockCore
@main struct HashDockApp: App {
    @StateObject var model: Model
    init() {
        if CommandLine.arguments.contains("--smoke") { exit(SelfTest.run()) }
        if CommandLine.arguments.contains("--screenshots") { do { try ScreenshotRenderer.render(to:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) } catch { exit(1) } }
        if CommandLine.arguments.contains("--external-reopen") { exit(SelfTest.external(reopen:true)) }
        let external=CommandLine.arguments.contains("--external-select")
        let file=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/HashDock/ExternalTest/state.json")
        _model=StateObject(wrappedValue:Model(storage:external ? file : nil))
    }
    var body: some Scene {
        WindowGroup("HashDock", id:"matrix") { ContentView(model:model).modifier(PanelAccess()).onAppear { HotKey.shared.register(HotKey.shared.key)
        } }
            .commands { CommandGroup(replacing:.newItem) {} }
        MenuBarExtra { MenuContent(model:model) } label: {
            HStack(spacing:2) { Image(systemName:model.symbol); if model.busy { ProgressView().controlSize(.mini) }; if model.sample { Text("S").font(.system(size:9,weight:.bold)) } }.help(model.menuTitle).accessibilityLabel(model.menuTitle)
        }.menuBarExtraStyle(.window)
        Settings { SettingsView(model:model) }
    }
}
@MainActor final class HotKey {
    static let shared=HotKey()
    var key: UInt32 = UserDefaults.standard.object(forKey:"hotkey") as? UInt32 ?? 4
    var message="Control Option H opens the delivery matrix"
    var openAction: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    func open() { openAction?(); NSApp.activate(ignoringOtherApps:true); for window in NSApp.windows where window.canBecomeKey && window.title != "" { window.makeKeyAndOrderFront(nil) } }
    func register(_ key: UInt32) {
        if let ref { UnregisterEventHotKey(ref) }; self.ref=nil; self.key=key; UserDefaults.standard.set(key,forKey:"hotkey")
        if key == 999 { message="Shortcut disabled"; return }
        if handler == nil { InstallEventHandler(GetApplicationEventTarget(), { _,_,_ in Task { @MainActor in HotKey.shared.open() }; return noErr },1,[EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))],nil,&handler) }
        let result=RegisterEventHotKey(key,UInt32(controlKey|optionKey),EventHotKeyID(signature:0x48415348,id:1),GetApplicationEventTarget(),0,&ref)
        message=result == noErr ? "Shortcut registered" : "Shortcut unavailable or in conflict. Choose another."
    }
}

struct PanelAccess: ViewModifier {
    @Environment(\.openWindow) var openWindow
    func body(content: Content) -> some View {
        content.onAppear { HotKey.shared.openAction = { openWindow(id:"matrix") } }
    }
}

struct MenuContent: View {
    @ObservedObject var model: Model
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(model.menuTitle).font(.headline); Text(D(model.message))
            Button(L("Open delivery matrix","Abrir matriz de entregas")) { openWindow(id:"matrix"); NSApp.activate(ignoringOtherApps:true) }
            Button(L("See Sample","Ver ejemplo")) { model.switchSample(true); openWindow(id:"matrix"); NSApp.activate(ignoringOtherApps:true) }
            SettingsLink { Text(L("Settings","Ajustes")) }; Links(); Button(L("Quit","Salir")) { NSApp.terminate(nil) }
        }.padding().frame(width:330).modifier(PanelAccess())
    }
}
