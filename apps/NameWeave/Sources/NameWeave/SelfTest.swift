import Foundation
import NameWeaveCore
import MASKit

@MainActor
enum SelfTest {
    static func run() -> Int32 {
        do {
            let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("smoke-fixtures")
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let root = base.appendingPathComponent("handoff", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("AUX.txt")
            try Data("Synthetic smoke fixture".utf8).write(to: file)
            let scanned = Scanner.scan(root, policy: Policy())
            let sourceBefore = try Data(contentsOf: file)
            var checks = [SmokeCheck(name: "sample repair collision visible", pass: Weave.plan(Weave.sample, policy: Policy(), edits: Weave.suggestions(Weave.sample)).unresolvedCount > 0, detail: "Synthetic repairs remain unresolved before collision planning")]
            let resolved = Weave.resolve(Weave.sample, policy: Policy(), edits: Weave.suggestions(Weave.sample))
            checks.append(SmokeCheck(name: "complete virtual tree resolves", pass: Weave.plan(Weave.sample, policy: Policy(), edits: resolved).ready, detail: "Sample repaired parent paths and unique candidates checked together"))
            checks.append(SmokeCheck(name: "live filesystem enumeration", pass: scanned.coverage.complete && scanned.entries.contains { $0.path == "AUX.txt" }, detail: "Real Foundation enumeration inside signed container"))
            var state = SavedState(); state.scan = scanned; state.edits = Weave.resolve(scanned, policy: Policy(), edits: [:]); state.rootLabel = "Synthetic live fixture"
            let stateURL = base.appendingPathComponent("roundtrip.json")
            try StateStore.save(state, to: stateURL)
            let restored = try StateStore.load(stateURL)
            checks.append(SmokeCheck(name: "persistence reopen", pass: restored.scan?.entries == state.scan?.entries && restored.edits == state.edits, detail: "Fresh model storage restored from container JSON"))
            checks.append(SmokeCheck(name: "source file unchanged", pass: try Data(contentsOf: file) == sourceBefore, detail: "Scan and repair planning never change the fixture"))
            let sampleModel = AppModel(stateURL: base.appendingPathComponent("isolated.json")); sampleModel.toggleSample(true)
            checks.append(SmokeCheck(name: "sample mode reachable model", pass: sampleModel.sample && sampleModel.plan.report(sample: true).hasPrefix("Sample"), detail: "Sample output and mode labeled"))
            sampleModel.toggleSample(false)
            checks.append(SmokeCheck(name: "sample live isolation", pass: !sampleModel.sample && sampleModel.scan == nil, detail: "Live state cannot inherit sample evidence"))
            let localPrivacy = PolicyButton.bundledText("privacy")
            let localSupport = PolicyButton.bundledText("support")
            checks.append(SmokeCheck(name: "bundled policy and support", pass: localPrivacy.contains("security scoped bookmarks") && localSupport.contains("Command comma") && !localPrivacy.contains("{DOMAIN}"), detail: "Local text is loaded from shipped Contents Resources without a build-folder dependency"))
            let report = SmokeReport(app: "NameWeave", bundleID: "com.michaellip.nameweave", version: "1.0.0", checks: checks)
            try report.write(); return report.pass ? 0 : 1
        } catch { fputs("Smoke failed \(error)\n", stderr); return 1 }
    }
}
