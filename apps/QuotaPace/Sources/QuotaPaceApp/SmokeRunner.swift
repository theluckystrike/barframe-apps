import Foundation
import Darwin
import MASKit
import QuotaPaceCore

enum SmokeRunner {
    static func run() {
        var checks: [SmokeCheck] = []
        func check(_ name: String, _ work: () throws -> (Bool, String)) {
            do { let (pass, detail) = try work(); checks.append(SmokeCheck(name: name, pass: pass, detail: detail)) }
            catch { checks.append(SmokeCheck(name: name, pass: false, detail: error.localizedDescription)) }
        }
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("QuotaPace-smoke-\(UUID().uuidString)")
        let now = JSONLParser.date("2026-10-12T10:00:00Z")!
        func copiedFixture(_ provider: Provider) throws -> URL {
            let folder = root.appendingPathComponent(provider.rawValue)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("session.jsonl")
            if !FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: FixtureFiles.url(provider.rawValue), to: file)
            }
            return folder
        }
        check("in-app privacy and support pages are reachable") {
            guard let privacy = AppLinks.privacyPolicy(), let support = AppLinks.support() else { return (false, "missing in-app link") }
            if privacy.isFileURL && support.isFileURL {
                let policy = try String(contentsOf: privacy, encoding: .utf8)
                let help = try String(contentsOf: support, encoding: .utf8)
                return (policy.contains("privacy policy") && help.contains("Try Sample mode"), "bundled offline privacy and support pages readable")
            }
            return (privacy.scheme == "https" && support.scheme == "https", "final-domain HTTPS links present; hosting availability untested")
        }
        check("read-only bookmark create and resolve") {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let proof = Data(UUID().uuidString.utf8)
            try proof.write(to: root.appendingPathComponent("bookmark-proof"), options: .atomic)
            let grant = try FolderGrant(url: root)
            let resolved = try grant.resolve()
            let restored = try Data(contentsOf: resolved.url.appendingPathComponent("bookmark-proof"))
            return (restored == proof && !grant.bookmark.isEmpty, "bookmark=\(grant.bookmark.count) bytes, proof readback=\(restored == proof), stale=\(resolved.stale)")
        }
        check("stream Claude JSONL from container fixture") {
            let scan = try LogScanner().scan(folder: copiedFixture(.claude), provider: .claude)
            let total = scan.samples.reduce(0) { $0 + $1.tokens }
            return (total == 13200 && scan.samples.count == 3 && scan.warnings.isEmpty, "tokens=\(total), unique messages=\(scan.samples.count)")
        }
        check("stream Codex cumulative counters from container fixture") {
            let scan = try LogScanner().scan(folder: copiedFixture(.codex), provider: .codex)
            let total = scan.samples.reduce(0) { $0 + $1.tokens }
            return (total == 5000 && scan.samples.count == 3, "tokens=\(total), delta events=\(scan.samples.count)")
        }
        check("rolling windows over file-backed usage") {
            let scan = try LogScanner().scan(folder: copiedFixture(.claude), provider: .claude)
            let short = WindowSummary.calculate(samples: scan.samples, window: .fiveHours, limit: 5000, now: now)
            let week = WindowSummary.calculate(samples: scan.samples, window: .sevenDays, limit: 20000, now: now)
            return (short.used == 3200 && week.used == 13200, "5h=\(short.used), 7d=\(week.used)")
        }
        check("pace forecast over file-backed usage") {
            let scan = try LogScanner().scan(folder: copiedFixture(.claude), provider: .claude)
            let summary = WindowSummary.calculate(samples: scan.samples, window: .fiveHours, limit: 5000, now: now)
            return (summary.tokensPerHour == 1600 && summary.secondsToLimit == 4050 && summary.projected == 8000, "pace=\(summary.tokensPerHour)/h, time-to-limit=\(summary.secondsToLimit ?? -1)s")
        }
        check("sandbox denies ungranted Desktop directory") {
            guard let record = getpwuid(getuid()), let directory = record.pointee.pw_dir else { return (false, "getpwuid failed") }
            let desktop = String(cString: directory) + "/Desktop"
            errno = 0
            if let handle = opendir(desktop) { closedir(handle); return (false, "ungranted Desktop was readable") }
            let code = errno
            return (code == EPERM || code == EACCES, "opendir ungranted Desktop errno=\(code)")
        }
        try? FileManager.default.removeItem(at: root)
        let report = SmokeReport(app: "QuotaPace", bundleID: Bundle.main.bundleIdentifier ?? "unknown", version: "1.0.0", checks: checks)
        do { try report.write(); exit(report.pass ? 0 : 1) }
        catch { NSLog("QuotaPace smoke report error: %@", error.localizedDescription); exit(1) }
    }
}
