import SwiftUI
import Carbon
import CronSpindleCore
import MASKit

@main struct CronSpindleApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    @StateObject var model: Model
    init() {
        if CommandLine.arguments.contains("--smoke") {exit(SelfTest.run())}
        if CommandLine.arguments.contains("--screenshots") {
            do {try ScreenshotRenderer.render(to:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0)} catch {fputs("\(error)\n",stderr);exit(1)}
        }
        _model=StateObject(wrappedValue:Model())
    }
    var body: some Scene {
        WindowGroup("CronSpindle") {ContentView(model:model).onAppear{delegate.model=model}.onReceive(model.objectWillChange){_ in DispatchQueue.main.async{delegate.update()}}}
            .commands {CommandGroup(replacing:.newItem){}; CommandGroup(after:.appSettings){Button("Sample mode"){model.toggleSample(!model.sample)}.keyboardShortcut("s",modifiers:[.command,.shift])}}
        Settings {SettingsView(model:model)}
    }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    var model: Model?
    var item: NSStatusItem?
    let popover=NSPopover()
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item?.button?.target=self; item?.button?.action=#selector(toggleSummary)
        HotKey.shared.action={ [weak self] in self?.openPanel() }; HotKey.shared.register(UserDefaults.standard.string(forKey:"shortcut") ?? "K")
        if let appearance=model?.appearance, appearance != "System" {NSApp.appearance=NSAppearance(named:appearance=="Dark" ? .darkAqua : .aqua)}
        update()
    }
    @objc func toggleSummary() {
        guard let button=item?.button, let model else {openPanel();return}
        if popover.isShown {popover.performClose(nil);return}
        popover.behavior = .transient
        popover.contentViewController=NSHostingController(rootView:SummaryView(model:model,open:{[weak self] in self?.popover.performClose(nil);self?.openPanel()}))
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
    }
    @objc func openPanel() {NSApp.activate(ignoringOtherApps:true); if let w=NSApp.windows.first(where:{$0.title=="CronSpindle"}) {w.makeKeyAndOrderFront(nil)} else {NSApp.windows.first(where:{$0.canBecomeKey})?.makeKeyAndOrderFront(nil)}}
    func update() {
        let state=model?.state ?? "No inputs"
        let symbol=state=="Clear" ? "calendar.badge.checkmark" : state=="Conflict" ? "calendar.badge.exclamationmark" : "calendar"
        item?.button?.image=NSImage(systemSymbolName:symbol,accessibilityDescription:state)
        item?.button?.image?.isTemplate=true
        item?.button?.title=" " + (model?.status ?? "No inputs")
        item?.button?.toolTip="CronSpindle \(model?.status ?? state) · Last check \(model?.lastCheck.map{Planner.label($0)} ?? "never")"
        item?.button?.setAccessibilityLabel(item?.button?.toolTip)
    }
}
@MainActor final class HotKey {
    static let shared=HotKey()
    var ref: EventHotKeyRef?
    var handler: EventHandlerRef?
    var action: (() -> Void)?
    var error: String?
    func register(_ letter:String) {
        if let ref {UnregisterEventHotKey(ref)}
        if handler==nil {
            var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), {_,_,_ in Task{@MainActor in HotKey.shared.action?()}; return noErr},1,&spec,nil,&handler)
        }
        let code: UInt32 = letter=="J" ? 38 : letter=="L" ? 37 : 40
        let status=RegisterEventHotKey(code,UInt32(controlKey|optionKey),EventHotKeyID(signature:0x43524F4E,id:1),GetApplicationEventTarget(),0,&ref)
        if status==noErr {UserDefaults.standard.set(letter,forKey:"shortcut")}
        error=status==noErr ? nil : "Shortcut unavailable. Choose another key. Error \(status)"
    }
}
enum SelfTest {
    @MainActor static func run() -> Int32 {
        do {
            let base=try Planner.analyze(Fixtures.jobs,start:Fixtures.start,days:1)
            var proposed=Fixtures.jobs; proposed[1].expression="0 4 * * *"
            let after=try Planner.analyze(proposed,start:Fixtures.start,days:1)
            let file=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("smoke-plan.json")
            try Plan(jobs:Fixtures.jobs).save(file)
            let loaded=try Plan.load(file)
            try FileManager.default.removeItem(at:file)
            let dst=try Planner.analyze(Fixtures.dst,start:Fixtures.autumn,days:1)
            let report=SmokeReport(app:"CronSpindle",bundleID:"com.michaellip.cronspindle",version:"1.0.0",checks:[
                SmokeCheck(name:"Sample collision",pass:base.collisions.count==1,detail:base.state),
                SmokeCheck(name:"Proposal removes contention",pass:after.collisions.isEmpty && Planner.difference(base.collisions,minus:after.collisions).count==1,detail:after.state),
                SmokeCheck(name:"Live plan entry and persistent reopen",pass:loaded.jobs==Fixtures.jobs,detail:"Atomic save loaded from sandbox container"),
                SmokeCheck(name:"Repeated local hour",pass:dst.occurrences.count==2 && dst.occurrences[0].wallLabel != dst.occurrences[1].wallLabel,detail:dst.occurrences.map(\.wallLabel).joined(separator:" | "))])
            try report.write();return report.pass ? 0 : 1
        } catch {fputs("\(error)\n",stderr);return 1}
    }
}

struct SummaryView: View {
    @ObservedObject var model: Model
    let open: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("CronSpindle").font(.headline)
            Text(model.status).font(.title2)
            if model.busy {ProgressView()}
            if let result=model.result {Text("\(result.collisions.count) contention windows");Text("Last check \(model.lastCheck.map{Planner.label($0)} ?? "never")").font(.caption)}
            if model.jobs.isEmpty {Text("Enter jobs or explore Sample to begin").foregroundStyle(.secondary)}
            Button("Open plan",action:open).keyboardShortcut(.defaultAction)
            Button("Check saved plan"){model.analyze()}.disabled(model.jobs.isEmpty || model.busy)
            SettingsLink {Text("Settings")}
            Links()
            Button("Quit"){NSApp.terminate(nil)}
        }.padding(20).frame(width:310)
    }
}
