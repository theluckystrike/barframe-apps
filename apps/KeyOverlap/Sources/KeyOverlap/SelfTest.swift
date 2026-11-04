import Foundation
import MASKit
import KeyOverlapCore

@MainActor
enum SelfTest {
    static func run() -> Int32 {
        var checks: [SmokeCheck] = []
        var plan = ShortcutPlan.sample()
        let before = OverlapEngine.overlaps(plan.records, contexts: plan.contexts)
        checks.append(SmokeCheck(name: "scope classification", pass: before.filter { $0.kind == .definite }.count == 1 && before.filter { $0.kind == .possible }.count == 1 && before.filter { $0.kind == .separate }.count == 2, detail: "Sample covers global, unknown, distinct apps and explicit contexts"))
        let after = OverlapEngine.overlaps(plan.proposedRecords, contexts: plan.contexts)
        checks.append(SmokeCheck(name: "staged replacement resolves global overlap", pass: after.filter { $0.kind == .definite }.isEmpty && plan.records[0].chord != plan.proposedRecords[0].chord, detail: "Baseline isolated from proposal"))
        let snapshot = plan
        do {
            _ = try PlanImport.importing(Data("[{\"command\":\"Bad\"}]".utf8), into: plan)
            checks.append(SmokeCheck(name: "invalid import atomicity", pass: false, detail: "Invalid row accepted"))
        } catch { checks.append(SmokeCheck(name: "invalid import atomicity", pass: plan == snapshot, detail: error.localizedDescription)) }
        do {
            let record = try ShortcutRecord(command: "Smoke candidate", key: "5", modifiers: ["shift","command"], scope: "Orbit Editor", context: nil)
            let result = OverlapEngine.candidate(record, in: plan.records, contexts: plan.contexts)
            checks.append(SmokeCheck(name: "candidate checks leave baseline unchanged", pass: result.filter { $0.kind == .definite }.count == 2 && plan == snapshot, detail: "Preview found matching scopes without mutation"))
            let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("keyoverlap-smoke-plan.json")
            try JSONEncoder().encode(plan).write(to: file, options: .atomic)
            let restored = try JSONDecoder().decode(ShortcutPlan.self, from: Data(contentsOf: file)).validated()
            try FileManager.default.removeItem(at: file)
            checks.append(SmokeCheck(name: "sandbox local persistence", pass: restored == plan, detail: "Atomic write and validated read in container"))
            plan.apply()
            checks.append(SmokeCheck(name: "local application clears staging", pass: plan.replacements.isEmpty && OverlapEngine.overlaps(plan.records, contexts: plan.contexts).filter { $0.kind == .definite }.isEmpty, detail: "Applied only to local records"))
            checks.append(SmokeCheck(name: "strict import template", pass: try PlanImport.decode(Data(PlanImport.template.utf8)).count == 2, detail: "Documented template accepted"))
        } catch { checks.append(SmokeCheck(name: "sandbox operations", pass: false, detail: error.localizedDescription)) }
        let report = SmokeReport(app: "KeyOverlap", bundleID: "com.michaellip.keyoverlap", version: "1.0.0", checks: checks)
        do { try report.write() } catch { fputs("Smoke write failed \(error.localizedDescription)\n", stderr); return 1 }
        return report.pass ? 0 : 1
    }
}
