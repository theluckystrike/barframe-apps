import Foundation
import EnvTrellisCore
import MASKit

@MainActor
enum SelfTest {
    static func run() -> Int32 {
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/EnvTrellisSmoke", isDirectory: true)
        var checks: [SmokeCheck] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("live.env")
            try Data("TOKEN=smoke_fixture_secret\nEMPTY=\n".utf8).write(to: url)
            let bookmarked = InputFile(label: "Smoke environment", bookmark: try FileAccess.bookmark(url))
            let scanned = FileAccess.scan(bookmarked)
            checks.append(SmokeCheck(name: "Live scoped file read", pass: scanned.parsed?.keys["TOKEN"]?.presence == .present && scanned.parsed?.keys["EMPTY"]?.presence == .empty && !scanned.unavailable, detail: "Container fixture read through scoped bookmark"))
            var project = SampleFixtures.project()
            let sampleReport = project.report(sample: true)
            checks.append(SmokeCheck(name: "Sample rule matrix", pass: project.readiness == .findings && sampleReport.contains("Missing required") && sampleReport.contains("Forbidden present") && sampleReport.contains("Duplicate key MODE"), detail: "Sample has missing required, forbidden and duplicate findings"))
            checks.append(SmokeCheck(name: "Value free reports", pass: !sampleReport.contains("fixture_secret") && !sampleReport.contains("duplicate_fixture"), detail: "Fixture values absent from copied report source"))
            project.template = scanned; project.environments = [scanned]; project.rules = [scanned.id: ["TOKEN": .required, "EMPTY": .optional]]
            let state = SavedState(projects: [project], pinned: project.id)
            let stateURL = directory.appendingPathComponent("state.json")
            try state.encoded().write(to: stateURL, options: .atomic)
            let restored = AppModel(stateURL: stateURL)
            checks.append(SmokeCheck(name: "Restart state and bookmark restoration", pass: restored.project?.rules[scanned.id]?["TOKEN"] == .required && restored.project?.readiness == .ready && FileAccess.scan(restored.project!.environments[0]).parsed?.keys["TOKEN"] != nil, detail: "New app model restored stored rules and scoped bookmark"))
            try Data("TOKEN=changed_fixture\nEMPTY=\nEXTRA=present\n".utf8).write(to: url)
            restored.refreshStale()
            checks.append(SmokeCheck(name: "Observed change marks stale", pass: restored.state == .stale, detail: "File metadata change invalidated the prior readiness"))
            let missing = FileAccess.scan(InputFile(label: "Unavailable", bookmark: Data("invalid".utf8)))
            checks.append(SmokeCheck(name: "Unavailable input stays unknown", pass: missing.unavailable && missing.parsed == nil, detail: "Invalid bookmark never produces a successful scan"))
            try Data("corrupt".utf8).write(to: stateURL)
            let corrupt = AppModel(stateURL: stateURL)
            checks.append(SmokeCheck(name: "Corrupt state recovery", pass: corrupt.live.projects.isEmpty && !corrupt.notice.isEmpty, detail: "Corrupt state shows recovery guidance"))
            try FileManager.default.removeItem(at: directory)
        } catch { checks.append(SmokeCheck(name: "Smoke fixture setup", pass: false, detail: "Could not set up container fixtures")) }
        let report = SmokeReport(app: "EnvTrellis", bundleID: "com.michaellip.envtrellis", version: "1.0.0", checks: checks)
        do { try report.write() } catch { return 1 }
        return report.pass ? 0 : 1
    }
}
