import SwiftUI
import AppKit
import Combine
import Carbon
import CaptionCoveCore
import MASKit

@main struct CaptionCoveApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var model:AppModel { delegate.ownedModel }
    init() {
        if CommandLine.arguments.contains("--smoke") { exit(SelfTest.run()) }
        if CommandLine.arguments.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { fputs("Screenshot error \(error)\n",stderr); exit(1) }
        }
    }
    var body:some Scene {
        Settings { SettingsView(model:model) }.commands {
            CommandGroup(replacing:.newItem) {
                Button(model.l("Review matrix","Revisar matriz")) { delegate.showDetails() }.keyboardShortcut("o")
            }
            CommandGroup(after:.appInfo) {
                Button(model.l("Sample mode","Modo Sample")) { model.toggleSample(!model.sampleMode); delegate.showDetails() }.keyboardShortcut("s",modifiers:[.command,.option])
            }
        }
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    let ownedModel=AppModel()
    var model:AppModel?
    var status:NSStatusItem?
    var popover=NSPopover()
    var subscription:AnyCancellable?
    var hotkey:Hotkey?
    var detailWindow:NSWindow?
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        attach(ownedModel)
        let item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.target=self; item.button?.action=#selector(togglePanel)
        status=item; popover.behavior = .transient
        refresh()
        if Self.shouldShowOnboarding(project:ownedModel.project,arguments:CommandLine.arguments) { showDetails() }
    }
    static func shouldShowOnboarding(project:Project,arguments:[String])->Bool {
        project.reference == nil && project.languages.isEmpty && !arguments.contains("--login") && !arguments.contains("-psn_login")
    }
    func attach(_ model:AppModel) {
        guard self.model == nil else { return }
        self.model=model
        popover.contentViewController=NSHostingController(rootView:SummaryView(model:model,openDetails:{[weak self] in self?.showDetails()}))
        subscription=model.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
        hotkey=Hotkey(action:{[weak self] in self?.togglePanel()})
        model.configureHotkey={ [weak self] in self?.configureShortcut() }
        configureShortcut(); refresh()
    }
    func configureShortcut() {
        guard let model else { return }
        let result=hotkey?.register(key:model.hotkeyKey,modifiers:model.hotkeyModifiers) ?? -1
        model.hotkeyError=result == noErr ? "" : model.l("Shortcut could not be registered. It may conflict with another app. Choose different keys or turn it off","No se pudo registrar el atajo. Puede estar en uso por otra app. Elige otras teclas o desactívalo")
    }
    @objc func togglePanel() {
        guard let button=status?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { model?.becameActive(); NSApp.activate(ignoringOtherApps:true); popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY) }
    }
    func showDetails() {
        popover.performClose(nil); NSApp.activate(ignoringOtherApps:true)
        if let window=NSApp.windows.first(where:{$0.title == "CaptionCove" && $0.canBecomeKey}) { window.makeKeyAndOrderFront(nil) }
        else if let model {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            detailWindow=window; window.title="CaptionCove"; window.isReleasedWhenClosed=false
            window.contentViewController=NSHostingController(rootView:ContentView(model:model)); window.center(); window.makeKeyAndOrderFront(nil)
        }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool { if !hasVisibleWindows { showDetails() }; return true }
    func applicationDidBecomeActive(_ notification:Notification) { model?.becameActive() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func refresh() {
        guard let button=status?.button else { return }
        let state=model?.state ?? .incomplete
        let suffix=model?.checking == true ? "arrow.triangle.2.circlepath" : model?.result == nil ? "circle" : state == .ready ? "checkmark" : state == .issues ? "exclamationmark" : "questionmark"
        let base=NSImage(systemSymbolName:"captions.bubble",accessibilityDescription:"CaptionCove")!
        let badge=NSImage(systemSymbolName:suffix,accessibilityDescription:nil)!
        let image=NSImage(size:NSSize(width:28,height:18),flipped:false) { rect in
            base.draw(in:NSRect(x:0,y:2,width:19,height:15))
            badge.draw(in:NSRect(x:19,y:4,width:9,height:11))
            return true
        }
        image.isTemplate=true; button.image=image
        button.title=model?.sampleMode == true ? " S" : ""
        button.toolTip=model?.tooltip ?? "CaptionCove Incomplete"
        button.setAccessibilityLabel(button.toolTip)
    }
}
@MainActor final class Hotkey {
    var reference:EventHotKeyRef?
    var handler:EventHandlerRef?
    var action:()->Void
    init(action:@escaping ()->Void) {
        self.action=action
        var event=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{ _,_,context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let object=Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { object.action() }
            return noErr
        },1,&event,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
    func register(key:String,modifiers:String)->OSStatus {
        if let reference { UnregisterEventHotKey(reference); self.reference=nil }
        if modifiers == "off" { return noErr }
        let keys:[String:UInt32]=["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"O":31,"U":32,"I":34,"P":35,"L":37,"J":38,"K":40,"N":45,"M":46]
        guard let code=keys[key] else { return OSStatus(paramErr) }
        let flags=modifiers == "controlOption" ? controlKey|optionKey : modifiers == "commandShift" ? cmdKey|shiftKey : cmdKey|optionKey
        return RegisterEventHotKey(code,UInt32(flags),EventHotKeyID(signature:0x43434f56,id:1),GetApplicationEventTarget(),0,&reference)
    }
}
enum SelfTest {
    @MainActor static func run()->Int32 {
        var checks=[SmokeCheck]()
        do {
            let dir=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("CaptionCoveSmoke")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:dir) }
            let ref=dir.appendingPathComponent("reference.srt")
            try Data(Samples.reference.utf8).write(to:ref)
            let input=InputReference(label:"Reference",bookmark:try ref.bookmarkData(options:[.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys:nil,relativeTo:nil),filename:"reference.srt")
            let parsed=try AppModel.read(input).0
            checks.append(SmokeCheck(name:"sandbox file and bookmark read",pass:parsed.complete && parsed.cues.count == 3,detail:"Container SRT reopened through scoped bookmark. External chooser access needs manual verification"))
            let scan=Comparator.scan(reference:parsed,languages:Samples.languages.map{($0.0,SRTParser.parse($0.1))},sample:true)
            checks.append(SmokeCheck(name:"Sample delivery matrix",pass:scan.rows.count == 5 && scan.rows.first(where:{$0.label == "Spanish"})?.count(.missing) == 1 && scan.rows.first(where:{$0.label == "French"})?.count(.drift) == 1,detail:"Synthetic missing cue and signed drift are distinct"))
            checks.append(SmokeCheck(name:"Incomplete cannot claim ready",pass:scan.state == .incomplete,detail:"Empty translation prevents parity success"))
            var live=scan; live.sample=false
            let project=Project(reference:input,rules:Rules(),result:live)
            let url=dir.appendingPathComponent("state.json")
            try Persistence.save(project,to:url)
            let reopened=try Persistence.load(from:url)
            let reopenedParsed=try AppModel.read(reopened.reference!).0
            checks.append(SmokeCheck(name:"Project reopens after persistence",pass:reopened == project && reopenedParsed == parsed,detail:"Rules summary and bookmark restored from sandbox disk"))
            checks.append(SmokeCheck(name:"Report omits dialogue",pass:scan.report().contains("Sample") && !scan.report().contains("Inicio tranquilo"),detail:"Sample label retained and dialogue omitted by default"))
            checks.append(SmokeCheck(name:"Invalid input recovery",pass:!SRTParser.parse("bad input").complete,detail:"Malformed input is incomplete"))
        } catch { checks.append(SmokeCheck(name:"Sandbox operation",pass:false,detail:error.localizedDescription)) }
        do { try SmokeReport(app:"CaptionCove",bundleID:"com.michaellip.captioncove",version:"1.0.0",checks:checks).write() } catch { return 1 }
        return checks.allSatisfy(\.pass) ? 0 : 1
    }
}
