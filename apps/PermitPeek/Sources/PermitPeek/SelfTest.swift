import Foundation
import MASKit
import PermitPeekCore

enum SelfTest {
    @MainActor static func run(writeSmoke: Bool) -> Int32 {
        var checks: [SmokeCheck]=[]
        do {
            let snapshot=try Inspector.inspect(Bundle.main.bundleURL)
            checks.append(SmokeCheck(name:"Security API reads signed sandbox bundle",pass:snapshot.sandboxed,detail:"identity \(snapshot.identity), declarations \(snapshot.declarations.count)"))
            let external = try Inspector.inspect(URL(fileURLWithPath:"/Applications/Safari.app"))
            checks.append(SmokeCheck(name:"Installed app static signature read",pass:!external.identity.isEmpty,detail:"Read installed Safari main signature using Security APIs inside sandbox"))
            var watch=Watch(id:"smoke",name:"Smoke",baseline:snapshot)
            var changed=snapshot; changed.declarations["com.apple.security.network.client"]="true"
            watch.receive(changed)
            checks.append(SmokeCheck(name:"Persistent acknowledgement diff",pass:watch.changes.count == 1,detail:watch.report))
            let url=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("smoke-baseline.json")
            try JSONEncoder().encode(watch).write(to:url)
            var restored=try JSONDecoder().decode(Watch.self,from:Data(contentsOf:url))
            restored.fail("simulated denied read"); restored.acknowledge()
            checks.append(SmokeCheck(name:"Failed read retains persisted baseline",pass:restored.baseline == snapshot,detail:"Serialized baseline survived failure and acknowledgement attempt"))
            restored.receive(changed); restored.acknowledge()
            checks.append(SmokeCheck(name:"Explicit acknowledgement clears inbox",pass:restored.changes.isEmpty,detail:"Baseline replaced only after success"))
            try FileManager.default.removeItem(at:url)
        } catch { checks.append(SmokeCheck(name:"Static signing inspection",pass:false,detail:error.localizedDescription)) }
        let report=SmokeReport(app:"PermitPeek",bundleID:"com.michaellip.permitpeek",version:"1.0.0",checks:checks)
        do { _ = try report.write() } catch { return 1 }
        return report.pass ? 0 : 1
    }
}
