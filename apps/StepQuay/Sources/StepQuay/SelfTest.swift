import Foundation
import MASKit
import StepQuayCore

@MainActor
enum SelfTest {
    static func run() -> Int32 {
        // Let LaunchServices register its open -W process wait before the smoke process exits.
        defer { Thread.sleep(forTimeInterval: 0.5) }
        var q = Queue.sample()
        let note = q.current?.notes.last?.note
        try? q.resume(now: 10); q.tick(40)
        let remaining = q.current?.remaining
        try? q.interrupt(note: "Resume at the support link", now: 40)
        q.tick(400)
        let pausePassed = q.current?.remaining == remaining && q.current?.phase == .paused
        var persistencePassed = false
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("stepquay-smoke-state.json")
            try q.encoded().write(to: url, options: .atomic)
            persistencePassed = try Queue.decoded(Data(contentsOf: url)) == q
            try FileManager.default.removeItem(at: url)
        } catch { persistencePassed = false }
        let live = Queue()
        let checks = [
            SmokeCheck(name: "interruption preserves remaining effort", pass: pausePassed, detail: "Monotonic tick frozen while paused"),
            SmokeCheck(name: "resume note retained", pass: note == "Continue at the support link", detail: "Fictional Check links note visible before resume"),
            SmokeCheck(name: "container persistence round trip", pass: persistencePassed, detail: "Codable queue written and read inside container"),
            SmokeCheck(name: "budget preserves overflow", pass: q.fittingIDs.count == 2 && q.actions.count == 3, detail: "Consecutive fit with retained overflow action"),
            SmokeCheck(name: "sample isolation", pass: live.actions.isEmpty, detail: "Live queue untouched by sample reducer"),
            SmokeCheck(name: "sleep pauses active timing", pass: sleepPass(), detail: "Sleep reducer requires explicit resume"),
            SmokeCheck(name: "local privacy and support bundled", pass: LocalDocument.allCases.allSatisfy { $0.text().count > 300 && $0.text(spanish: true).count > 300 }, detail: "English and Spanish documents load from app resources without the build tree")
        ]
        do { try SmokeReport(app: "StepQuay", bundleID: "com.michaellip.stepquay", version: "1.0.0", checks: checks).write() }
        catch { fputs("Smoke write failed \(error)\n", stderr); return 1 }
        return checks.allSatisfy(\.pass) ? 0 : 1
    }
    static func sleepPass() -> Bool {
        var q = Queue(); try? q.add(title: "Sleep fixture", minutes: 1); try? q.start(now: 1)
        q.sleep(now: 11); q.tick(1000)
        return q.current?.phase == .paused && q.current?.active == 10
    }
}
