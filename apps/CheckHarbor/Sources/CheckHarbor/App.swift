import SwiftUI
import MASKit
import CheckHarborCore
@main struct CheckHarborApp: App {
    @StateObject var model: Model
    init() {
        if CommandLine.arguments.contains("--smoke") { exit(Smoke.run()) }
        if CommandLine.arguments.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) } catch { fputs("\(error)\n",stderr); exit(1) }
        }
        _model=StateObject(wrappedValue:Model())
    }
    var body: some Scene {
        Window("CheckHarbor",id:"main") { ContentView(model:model).onAppear { model.startShortcut() } }.windowResizability(.contentSize)
        MenuBarExtra { ContentView(model:model) } label: { Image(systemName:model.symbol).accessibilityLabel(model.status) }.menuBarExtraStyle(.window)
        Settings { SettingsView(model:model) }
    }
}
enum Smoke {
    @MainActor static func run() -> Int32 {
        let model=Model(ephemeral:true); model.toggleSample(true)
        let dedup=model.state.inbox.active.count == 2 && model.state.inbox.active.first?.failures == 2
        let episode=model.state.inbox.active[0]; model.acknowledge(episode); model.snooze(episode)
        let persisted=model.state.inbox.active[0].acknowledged && model.state.inbox.active[0].snoozed(at:Date())
        model.sampleRecovery()
        let recovery=model.state.inbox.active.count == 1 && model.state.inbox.recovered.count == 1
        let report=SmokeReport(app:"CheckHarbor",bundleID:"com.michaellip.checkharbor",version:"1.0.0",checks:[
            SmokeCheck(name:"deduplicated branch episodes",pass:dedup,detail:"Repeated main failures form one episode and docs success leaves it open"),
            SmokeCheck(name:"acknowledge and snooze preserve unresolved",pass:persisted,detail:"Actions preserve the unresolved episode"),
            SmokeCheck(name:"matching recovery only",pass:recovery,detail:"Main recovers and release remains unresolved"),
            SmokeCheck(name:"bundled offline help",pass:LocalHelp.privacy.text.contains("Unresolved episodes") && LocalHelp.support.text.contains("Try Sample"),detail:"Policy retention and offline Sample guidance load from installed bundle"),
            SmokeCheck(name:"sample network isolation",pass:!Validation.mayFetch(sample:model.sample,until:nil,now:Date()),detail:"Sample cannot enter network refresh"),
            SmokeCheck(name:"sandbox persistence round trip",pass:(try? JSONDecoder().decode(Inbox.self,from:JSONEncoder().encode(model.state.inbox))) == model.state.inbox,detail:"Recovery inbox retains source runs and actions")])
        do { try report.write() } catch { return 1 }; return report.pass ? 0 : 1
    }
}
