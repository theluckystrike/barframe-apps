import Foundation
import MASKit
import RouteLoomCore
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        let model = AppModel(defaults:UserDefaults(suiteName:"RouteLoomSmoke")!,storage:nil,observeSystem:false)
        model.toggleSample(true)
        let s = model.selected!
        let report = Report.text(s)
        let checks = [
            SmokeCheck(name:"paired incident and recovery",pass:s.incidents.count == 2 && s.incidents.allSatisfy { $0.end != nil },detail:"\(s.incidents.count) recovered fixture incidents"),
            SmokeCheck(name:"sleep is unknown time",pass:s.gaps.count == 1 && s.incidents.last?.observedDuration == 30,detail:"\(s.gaps.count) sleep gap excluded from observed span"),
            SmokeCheck(name:"sample network isolation",pass:model.sample && !model.running && !model.checking,detail:"Sample is stopped and no probe task runs"),
            SmokeCheck(name:"report and comparison",pass:report.contains("reference.example") && report.contains("Unknown gap") && Report.comparison(s,Fixtures.earlier).contains("earlier"),detail:"hostnames and unknown gap included with session comparison"),
            SmokeCheck(name:"sandbox history round trip",pass:roundtrip(s),detail:"session encoded and decoded in container home"),
            SmokeCheck(name:"credential rejection",pass:(try? Endpoint.validate("https://user:secret@work.example")) == nil,detail:"embedded credentials rejected")
        ]
        do { try SmokeReport(app:"RouteLoom",bundleID:"com.michaellip.routeloom",version:"1.0.0",checks:checks).write();return checks.allSatisfy(\.pass) ? 0 : 1 } catch { return 1 }
    }
    static func roundtrip(_ s:Session) -> Bool {
        let url = URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("route-smoke-session.json")
        do { try JSONEncoder().encode(s).write(to:url,options:.atomic);let read = try JSONDecoder().decode(Session.self,from:Data(contentsOf:url));try FileManager.default.removeItem(at:url);return read == s } catch { return false }
    }
}
