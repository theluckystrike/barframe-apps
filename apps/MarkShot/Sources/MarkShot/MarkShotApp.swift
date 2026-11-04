import SwiftUI
import AppKit
import ServiceManagement
import Carbon
import MASKit

@main struct MarkShotApp:App {
    @StateObject var model:AppModel
    init() {
        if CommandLine.arguments.contains("--smoke") {exit(SelfTest.run())}
        if CommandLine.arguments.contains("--screenshots") {
            do {try ScreenshotRenderer.render(to:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("screenshots"));exit(0)} catch {fputs("Screenshots failed: \(error)\n",stderr);exit(1)}
        }
        if let index=CommandLine.arguments.firstIndex(of:"--render-screenshots"),index+1<CommandLine.arguments.count {
            do {try ScreenshotRenderer.render(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));exit(0)} catch {fputs("Screenshots failed: \(error)\n",stderr);exit(1)}
        }
        _model=StateObject(wrappedValue:AppModel())
    }
    var body:some Scene {
        MenuBarExtra("MarkShot",systemImage:"viewfinder") {PopoverView(model:model)}.menuBarExtraStyle(.window)
        Settings {SettingsView(model:model)}
    }
}
enum LocalPolicy {
    static func webURL(_ value:String) -> URL? {
        guard !value.contains("{"), !value.contains("}"), let url=URL(string:value),
              url.scheme == "https", let host=url.host, !host.isEmpty else {return nil}
        return url
    }
    static func text(_ name:String) throws -> String {
        let resources=Bundle.main.resourceURL.flatMap {Bundle(url:$0.appendingPathComponent("MarkShot_MarkShot.bundle"))} ?? Bundle.module
        guard let url=resources.url(forResource:name,withExtension:"md",subdirectory:"Resources") else {throw CocoaError(.fileReadNoSuchFile)}
        return try String(contentsOf:url,encoding:.utf8)
    }
}
@MainActor enum PolicyWindow {
    static var window:NSWindow?
    static func show(_ name:String) {
        let title=name == "privacy" ? "Privacy Policy" : "Support"
        let key=name == "privacy" ? "MASPrivacyPolicyURL" : "MASSupportURL"
        let fallback="https://barframe.com/apps/markshot/" + name + "/"
        let value=Bundle.main.object(forInfoDictionaryKey:key) as? String ?? fallback
        let content=(try? LocalPolicy.text(name)) ?? "Contact Michael Lip for help with MarkShot."
        let view=VStack(alignment:.leading,spacing:16) {
            Text(title).font(.title2.bold())
            ScrollView {Text(content).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
            if let url=LocalPolicy.webURL(value) {Link("Open website",destination:url)}
            Text("© 2026 Michael Lip").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:580,height:520)
        let w=window ?? NSWindow(contentRect:NSRect(x:0,y:0,width:628,height:568),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.title="MarkShot · " + title;w.isReleasedWhenClosed=false
        w.contentView=NSHostingView(rootView:view);window=w
        w.center();w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
}
struct PolicyLinks:View {
    var body:some View {HStack {
        Button("Privacy Policy") {PolicyWindow.show("privacy")}
        Button("Support") {PolicyWindow.show("support")}
    }.buttonStyle(.link).font(.caption)}
}
struct PopoverView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("MarkShot").font(.title2.bold());Spacer();if model.busy {ProgressView().controlSize(.small)}}
            HStack {Button("Area") {model.begin(.area)};Button("Window") {model.begin(.window)};Button("Full screen") {model.begin(.screen)}}.disabled(model.busy)
            if !model.error.isEmpty {Text(model.error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
            if model.permissionDenied {Button("Open Screen Recording settings") {model.openPrivacySettings()}}
            Button("Open Sample editor") {model.sample()}
            Divider()
            HStack {Text("Recent captures").font(.headline);Spacer();if !model.records.isEmpty {Button("Clear") {model.clearHistory()}}}
            if model.records.isEmpty {Text("Your last 10 captures will appear here.").font(.caption).foregroundStyle(.secondary)}
            ScrollView {
                VStack(alignment:.leading,spacing:6) {
                    ForEach(model.records) {record in
                        Button {model.reopen(record)} label: {
                            HStack {
                                if let image=NSImage(contentsOf:model.historyURL.appendingPathComponent(record.filename)) {Image(nsImage:image).resizable().scaledToFit().frame(width:68,height:44)}
                                VStack(alignment:.leading) {Text(record.sample ? "Sample" : "Capture");Text(record.date,style:.time).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"pencil")
                            }.padding(4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight:300)
            Divider()
            HStack {SettingsLink {Text("Settings…")};Spacer();Button("Quit") {NSApp.terminate(nil)}}
            PolicyLinks()
        }.padding(18).frame(width:350)
    }
}
struct CapturePicker:View {
    @ObservedObject var model:AppModel
    let mode:AppModel.Mode
    var body:some View {
        VStack(alignment:.leading) {
            Text(mode == .window ? "Choose a window" : "Choose a display").font(.title2.bold())
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    if mode == .window {
                        if model.windows.isEmpty {Text("No capturable windows are available.")}
                        ForEach(model.windows,id:\.windowID) {window in
                            Button("\(window.owningApplication?.applicationName ?? "Application") · \(window.title ?? "Untitled window")") {if let display=model.displays.first {model.choose(mode,display:display,window:window)}}
                        }
                    } else {
                        ForEach(Array(model.displays.enumerated()),id:\.element.displayID) {index,display in
                            Button("Display \(index+1) · \(display.width) × \(display.height)") {model.choose(mode,display:display)}
                        }
                    }
                }
            }
        }.padding(24).frame(width:520,height:420)
    }
}
struct SettingsView:View {
    @ObservedObject var model:AppModel
    @State var login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    @State var loginError=""
    @AppStorage("shortcutKey") var key=Int(kVK_ANSI_S)
    @AppStorage("shortcutOption") var option=true
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("MarkShot settings").font(.title2.bold())
            Toggle("Launch at login",isOn:Binding(get:{login},set:{value in
                do {if value {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()};loginError=SMAppService.mainApp.status == .requiresApproval ? "Approve MarkShot in System Settings → General → Login Items.":""}
                catch {loginError=error.localizedDescription}
                login=SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            }))
            if !loginError.isEmpty {Text(loginError).font(.caption).foregroundStyle(.orange)}
            Divider()
            Text("Global area capture shortcut").font(.headline)
            HStack {Text("Command + Shift +");Picker("Key",selection:$key) {Text("4").tag(Int(kVK_ANSI_4));Text("5").tag(Int(kVK_ANSI_5));Text("6").tag(Int(kVK_ANSI_6));Text("S").tag(Int(kVK_ANSI_S))}.labelsHidden().frame(width:90)}
            Toggle("Add Option modifier",isOn:$option)
            Text("If a shortcut is used by the system or another app, select a different key or add Option.").font(.caption).foregroundStyle(.secondary)
            if !model.shortcutError.isEmpty {Text(model.shortcutError).font(.caption).foregroundStyle(.orange)}
            Divider()
            HStack {Text("Save folder: \(model.folderName)");Spacer();Button("Choose folder…") {model.chooseFolder()}}
            if !model.error.isEmpty {Text(model.error).font(.caption).foregroundStyle(.orange)}
            Text("Without a saved folder, Save PNG opens a save dialog. History stores the last 10 flattened PNGs locally. Use Clear in the menu to remove them.").font(.caption).foregroundStyle(.secondary)
            Button("Open Screen Recording settings") {model.openPrivacySettings()}
            PolicyLinks()
            Text("Version 1.0.0 · Local capture and annotation").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:550)
            .onChange(of:key) {_,_ in model.configureShortcut()}.onChange(of:option) {_,_ in model.configureShortcut()}
    }
}
