import Foundation
import MASKit
import LinkSprigCore

@MainActor
enum SelfTest {
    static func run() -> Int32 {
        var checks: [SmokeCheck] = []
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("SmokeDocs")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try Sample.create(at: root)
            let before = try Data(contentsOf: root.appendingPathComponent("guide.md"))
            let tree = try Scanner.scan(root: root)
            let plan = try Planner.plan(tree: tree, proposal: Sample.proposal)
            checks.append(SmokeCheck(name: "Sample inbound and outbound impact", pass: plan.affected.count == 3 && plan.broken.count == 3 && plan.preexisting.count == 1, detail: "\(plan.affected.count) replacements and \(plan.preexisting.count) existing missing target"))
            checks.append(SmokeCheck(name: "Dry run leaves selected inputs unchanged", pass: try Data(contentsOf: root.appendingPathComponent("guide.md")) == before && !FileManager.default.fileExists(atPath: root.appendingPathComponent("archive/guide.md").path), detail: "Source bytes preserved and destination not created"))
            checks.append(SmokeCheck(name: "Plan entry and conflict rejection", pass: (try? Planner.plan(tree: tree, proposal: Proposal(source: "guide.md", destination: "nested/readme.md"))) == nil, detail: "Existing destination refused"))
            let state = SavedState(rootName: "Sample smoke", proposal: Sample.proposal)
            let url = root.appendingPathComponent("state.json")
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            checks.append(SmokeCheck(name: "Saved proposal reopens from container", pass: SavedState.load(try Data(contentsOf: url)).0 == state, detail: "JSON round trip from sandbox container"))
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/Applications"))
            let partial = try Scanner.scan(root: root)
            let partialPlan = try Planner.plan(tree: partial, proposal: Sample.proposal)
            checks.append(SmokeCheck(name: "Symlink coverage stays incomplete", pass: !partial.nodes.contains("escape") && !partial.warnings.isEmpty && partialPlan.incomplete, detail: "Symlink skipped without traversing destination"))
            checks.append(SmokeCheck(name: "Copied sample plan labeled", pass: plan.report(sample: true).contains("Sample") && plan.report(sample: true).contains("../archive/guide.md"), detail: "Report includes source lines and replacement targets"))
            checks.append(SmokeCheck(name: "Corrupt persistence recovers", pass: SavedState.load(Data("invalid".utf8)).1, detail: "Unreadable state resets safely"))
            let model = AppModel(persistent: false)
            model.setSample(true)
            checks.append(SmokeCheck(name: "UI Sample and live states remain separate", pass: model.sampleMode && model.plan?.affected.count == 3, detail: model.status))
            model.setSample(false)
            checks.append(SmokeCheck(name: "Live state does not reuse Sample findings", pass: model.plan == nil && !model.sampleMode, detail: model.status))
        } catch { checks.append(SmokeCheck(name: "Fixture scan", pass: false, detail: error.localizedDescription)) }
        let report = SmokeReport(app: "LinkSprig", bundleID: "com.michaellip.linksprig", version: "1.0.0", checks: checks)
        do { try report.write() } catch { fputs("Smoke write failed \(error)\n", stderr); return 1 }
        return report.pass && report.sandboxed ? 0 : 1
    }
}
