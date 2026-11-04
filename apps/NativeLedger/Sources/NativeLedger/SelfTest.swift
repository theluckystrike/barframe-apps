import AppKit
import Foundation
import LedgerCore

/// One result of the launch check.
struct LaunchCheck: Equatable {
    var name: String
    var passed: Bool
    var note: String
}

/// The launch check file, NSHomeDirectory()/smoke.json. Inside App Sandbox that path is the app container.
/// The release gate reads its keys: app, bundleID, version, sandboxed, home, checks (name, pass, detail), pass, generatedAt.
enum LaunchCheckFile {
    static let fileName = "smoke.json"

    static var runsInSandbox: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }

    /// True only when there is at least one result and every result passed.
    static func allPassed(_ results: [LaunchCheck]) -> Bool {
        guard !results.isEmpty else { return false }
        return !results.contains { !$0.passed }
    }

    static func dictionary(app: String, bundleID: String, version: String, results: [LaunchCheck],
                           inSandbox: Bool = runsInSandbox, home: String = NSHomeDirectory(), at date: Date = Date()) -> [String: Any] {
        var rows: [[String: Any]] = []
        for result in results { rows.append(["name": result.name, "pass": result.passed, "detail": result.note]) }
        return [
            "app": app, "bundleID": bundleID, "version": version,
            "sandboxed": inSandbox, "home": home,
            "checks": rows, "pass": allPassed(results),
            "generatedAt": ISO8601DateFormatter().string(from: date),
        ]
    }

    static func serialize(_ dictionary: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
    }

    @discardableResult
    static func save(_ dictionary: [String: Any], in directory: URL = URL(fileURLWithPath: NSHomeDirectory())) throws -> URL {
        let target = directory.appendingPathComponent(fileName)
        try serialize(dictionary).write(to: target, options: .atomic)
        return target
    }
}

@MainActor enum SelfTest {
    static let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")

    static func checks() -> [LaunchCheck] {
        var out: [LaunchCheck] = []
        let inspected = LedgerInspector().inspect(calculator)
        let o = inspected.observation
        out.append(LaunchCheck(name: "inspect-calculator-complete",
            passed: inspected.isComplete && o?.binary.cdhash?.count == 40 && o?.binary.executableSHA256?.count == 64,
            note: "complete=\(inspected.isComplete); failure=\(inspected.failure?.rawValue ?? "none"); version=\(o?.version ?? "none"); architecture=\(o?.architecture.rawValue ?? "none"); cdhash=\(o?.binary.cdhash?.count ?? 0) hex; sha256=\(o?.binary.executableSHA256?.count ?? 0) hex"))
        out.append(chainRoundtrip(o))
        out.append(exportRoundtrip(o))
        out.append(storeRoundtrip(o))
        out.append(containerBookmark())
        out.append(watchFolderDiscovery())
        out.append(ownExecutable())
        out.append(desktopDenied())
        return out
    }

    /// Two real readings, an appended rebuild and a tampered copy.
    static func chainRoundtrip(_ o: LedgerObservation?) -> LaunchCheck {
        guard let o else { return LaunchCheck(name: "chain-append-verify", passed: false, note: "no observation") }
        var ledger = AppLedger(displayName: "Calculator")
        let first = LedgerChain.append(o, kind: .observed, to: &ledger) != nil
        var again = o; again.observedAt = o.observedAt.addingTimeInterval(60)
        let duplicateSkipped = LedgerChain.append(again, kind: .observed, to: &ledger) == nil
        var rebuilt = again; rebuilt.binary.executableSHA256 = String(repeating: "0", count: 64)
        let second = LedgerChain.append(rebuilt, kind: .observed, to: &ledger)
        let intact = LedgerChain.verify(ledger) == .intact(count: 2)
        var tampered = ledger; tampered.entries[0].observation.version += ".1"
        let broken: Bool = { if case .broken(1, _) = LedgerChain.verify(tampered) { return true }; return false }()
        let flagged = second?.anomalies == [.silentRebuild]
        return LaunchCheck(name: "chain-append-verify", passed: first && duplicateSkipped && intact && broken && flagged,
            note: "appended=\(first); duplicate-skipped=\(duplicateSkipped); intact=\(intact); tamper-detected-at-1=\(broken); silent-rebuild-flagged=\(flagged)")
    }

    static func exportRoundtrip(_ o: LedgerObservation?) -> LaunchCheck {
        guard let o else { return LaunchCheck(name: "export-roundtrip", passed: false, note: "no observation") }
        var ledger = AppLedger(displayName: "Calculator", bookmark: Data(repeating: 7, count: 32))
        LedgerChain.append(o, kind: .observed, to: &ledger)
        do {
            let data = try LedgerFile(ledgers: [ledger], exportedAt: Date()).encoded()
            let text = String(decoding: data, as: UTF8.self)
            let file = try LedgerFile.decode(data)
            let clean = !text.contains("\"bookmark\"") && !PathScreen.looksLikePath(text)
            let intact = file.ledgers.first.map { LedgerChain.verify($0) } == .intact(count: 1)
            let rows = CrossMacComparison.compare(here: [ledger], there: file)
            let same = rows.map(\.verdict) == [.sameBuild]
            return LaunchCheck(name: "export-roundtrip", passed: clean && intact && same && file.ledgers.first?.bookmark == nil,
                note: "bytes=\(data.count); no-bookmark-or-path=\(clean); verifies=\(intact); compare-same-build=\(same)")
        } catch {
            return LaunchCheck(name: "export-roundtrip", passed: false, note: "encode or decode failed")
        }
    }

    static func storeRoundtrip(_ o: LedgerObservation?) -> LaunchCheck {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NativeLedger-store-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        var ledger = AppLedger(displayName: "Calculator")
        if let o { LedgerChain.append(o, kind: .observed, to: &ledger) }
        guard case .loaded(let empty) = store.load(), empty.isEmpty else {
            return LaunchCheck(name: "store-roundtrip", passed: false, note: "empty load failed")
        }
        do { try store.save([ledger]) } catch { return LaunchCheck(name: "store-roundtrip", passed: false, note: "save failed") }
        let reloaded = LedgerStore(directory: dir).load()
        let same = reloaded == .loaded([ledger])
        try? Data("not json".utf8).write(to: store.fileURL)
        let fresh = LedgerStore(directory: dir)
        let paused = fresh.load() == .corrupt && fresh.writesPaused
        return LaunchCheck(name: "store-roundtrip", passed: same && paused && o != nil,
                          note: "reloaded-equal=\(same); corrupt-pauses-writes=\(paused)")
    }

    /// A temporary folder with two synthetic apps, one at depth 1 and one at depth 2. Discovery, then
    /// AutoRecorder.step with the real LedgerInspector, a second step that reads nothing, and a deleted folder that
    /// is reported as unreadable instead of empty. The folder is deleted afterwards.
    static func watchFolderDiscovery() -> LaunchCheck {
        let name = "watch-folder-discovery"
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NativeLedger-watch-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        // A thin arm64 Mach-O header. The real inspector reads it as an unsigned Apple silicon executable.
        let header = Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]) + Data(count: 24)
        func makeApp(_ relative: String, id: String) throws {
            let app = root.appendingPathComponent(relative)
            try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "Main", "CFBundleName": app.deletingPathExtension().lastPathComponent,
                                        "CFBundleShortVersionString": "1.0", "CFBundleVersion": "100", "LSMinimumSystemVersion": "14.0"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            try header.write(to: app.appendingPathComponent("Contents/MacOS/Main"))
        }
        do {
            try makeApp("Alpha.app", id: "com.example.selftest.alpha")
            try makeApp("Tools/Beta.app", id: "com.example.selftest.beta")
        } catch {
            return LaunchCheck(name: name, passed: false, note: "temporary apps could not be written")
        }
        let folderID = UUID()
        let inspector = LedgerInspector()
        let recorder = AutoRecorder(folderID: folderID)
        guard let discovered = recorder.discover(root: root) else {
            return LaunchCheck(name: name, passed: false, note: "discovery returned nil")
        }
        let first = recorder.step(previous: [], discovered: discovered, inspector: { inspector.inspect($0) }, now: Date())
        let ledgers = first.ledgers
        let bundles = Set(ledgers.compactMap(\.pinnedBundleID))
        let shaped = ledgers.count == 2 && bundles == ["com.example.selftest.alpha", "com.example.selftest.beta"]
            && ledgers.allSatisfy { $0.source == .folder(folderID) && $0.entries.count == 1 && $0.entries[0].kind == .observed
                && $0.appKey != nil && $0.lastFingerprint != nil && $0.bookmark == nil }
        let intact = ledgers.allSatisfy { LedgerChain.verify($0) == .intact(count: 1) }
        let second = recorder.discover(root: root).map {
            recorder.step(previous: ledgers, discovered: $0, inspector: { inspector.inspect($0) }, now: Date())
        }
        let quiet = second.map { $0.inspectedCount == 0 && $0.newEntries.isEmpty && $0.ledgers == ledgers } ?? false
        let pathFree = ledgers.allSatisfy { ledger in
            let text = (try? LedgerCoding.encoder().encode(ledger)).map { String(decoding: $0, as: UTF8.self) } ?? "/"
            return !text.contains(root.lastPathComponent) && !text.contains(usersPrefix)
        }
        try? fm.removeItem(at: root)
        let goneIsUnreadable = recorder.discover(root: root) == nil
        let pass = discovered.count == 2 && first.inspectedCount == 2 && first.failures.isEmpty && first.newEntries.count == 2
            && shaped && intact && quiet && pathFree && goneIsUnreadable
        return LaunchCheck(name: name, passed: pass,
            note: "discovered=\(discovered.count); inspected=\(first.inspectedCount); failures=\(first.failures.count); entries=\(first.newEntries.count); ledgers-ok=\(shaped); intact=\(intact); unchanged-step-reads-nothing=\(quiet); path-free=\(pathFree); deleted-folder-unreadable=\(goneIsUnreadable)")
    }

    static func containerBookmark() -> LaunchCheck {
        do {
            let directory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let data = try directory.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                  includingResourceValuesForKeys: nil, relativeTo: nil)
            var stale = false
            let resolved = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            let active = resolved.startAccessingSecurityScopedResource()
            defer { if active { resolved.stopAccessingSecurityScopedResource() } }
            let same = resolved.standardizedFileURL == directory.standardizedFileURL
            let readable = FileManager.default.isReadableFile(atPath: resolved.path)
            return LaunchCheck(name: "container-bookmark-roundtrip", passed: same && !stale && readable,
                note: "bytes=\(data.count); same-location=\(same); stale=\(stale); readable=\(readable); scope-started=\(active)")
        } catch {
            return LaunchCheck(name: "container-bookmark-roundtrip", passed: false, note: "bookmark failed")
        }
    }

    static func ownExecutable() -> LaunchCheck {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let arch = (try? FileHandle(forReadingFrom: executable)).flatMap { handle -> Arch? in
            defer { try? handle.close() }
            return (try? handle.read(upToCount: 4096)).map(MachOArchitecture.classify)
        } ?? .unknown
        return LaunchCheck(name: "own-universal-executable", passed: arch == .universal, note: arch.rawValue)
    }

    /// A denied read of an unselected protected folder shows the sandbox grants no blanket home access.
    static func desktopDenied() -> LaunchCheck {
        let home = NSHomeDirectory().components(separatedBy: "/Library/Containers/").first ?? NSHomeDirectory()
        let desktop = URL(fileURLWithPath: home).appendingPathComponent("Desktop")
        let denied = (try? FileManager.default.contentsOfDirectory(at: desktop, includingPropertiesForKeys: nil)) == nil
        let sandboxed = LaunchCheckFile.runsInSandbox
        return LaunchCheck(name: "unselected-desktop-denied", passed: sandboxed && denied,
                          note: "sandboxed=\(sandboxed); unselected Desktop read denied=\(denied)")
    }

    /// "/Users/", assembled at run time so the shipped executable carries no home folder prefix.
    static var usersPrefix: String { NSString.path(withComponents: ["/", "Users"]) + "/" }

    static func reportDictionary() -> [String: Any] {
        LaunchCheckFile.dictionary(app: "NativeLedger", bundleID: Bundle.main.bundleIdentifier ?? "",
                                   version: ProductInfo.version, results: checks())
    }

    /// --selftest prints the report. --smoke also writes smoke.json. The exit code is 0 only when every check passes.
    static func run(writeSmoke: Bool) -> Int32 {
        let dictionary = reportDictionary()
        if writeSmoke {
            do { try LaunchCheckFile.save(dictionary) } catch { fputs("Launch check write failed\n", stderr); return 1 }
        }
        if let data = try? LaunchCheckFile.serialize(dictionary) { print(String(decoding: data, as: UTF8.self)) }
        return dictionary["pass"] as? Bool == true ? 0 : 1
    }
}
