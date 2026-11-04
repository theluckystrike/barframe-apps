import Foundation
import Testing
@testable import LedgerCore

struct FolderCatalogTests {
    @Test func enumeratesAppsAtDepthOneAndTwoSorted() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "Zeta.app", id: "com.example.zeta")
        try makeApp(root, "Alpha.app", id: "com.example.alpha")
        try makeApp(root, "Utilities/Tool.app", id: "com.example.tool")
        try makeApp(root, "Utilities/Deeper/TooDeep.app", id: "com.example.deep")
        try Data("x".utf8).write(to: root.appendingPathComponent("Readme.txt"))
        try Data("x".utf8).write(to: root.appendingPathComponent("Plain.app"))
        let found = relativeNames(FolderCatalog.enumerate(root: root), in: root)
        #expect(found == ["Alpha.app", "Utilities/Tool.app", "Zeta.app"])
    }

    @Test func skipsSymlinkedAppsAndSymlinkedFolders() throws {
        let root = try tempDirectory(), other = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
        try makeApp(root, "Real.app", id: "com.example.real")
        let target = try makeApp(other, "Elsewhere.app", id: "com.example.elsewhere")
        try makeApp(other, "Group/Inside.app", id: "com.example.inside")
        let fm = FileManager.default
        try fm.createSymbolicLink(at: root.appendingPathComponent("Link.app"), withDestinationURL: target)
        try fm.createSymbolicLink(at: root.appendingPathComponent("LinkedGroup"), withDestinationURL: other.appendingPathComponent("Group"))
        try fm.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("Folder/Nested.app"), withDestinationURL: target)
        #expect(relativeNames(FolderCatalog.enumerate(root: root), in: root) == ["Real.app"])
    }

    @Test func doesNotDescendIntoBundlesOrPackages() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "Outer.app", id: "com.example.outer")
        try makeApp(root, "Outer.app/Inner.app", id: "com.example.inner")
        try makeApp(root, "Outer.app/Contents/Library/LoginItems/Helper.app", id: "com.example.helper")
        try makeApp(root, "Kit.bundle/Hidden.app", id: "com.example.hidden")
        try makeApp(root, ".Secret/Invisible.app", id: "com.example.invisible")
        #expect(relativeNames(FolderCatalog.enumerate(root: root), in: root) == ["Outer.app"])
    }

    @Test func missingFolderIsNotReadableAndDiscoverReturnsNil() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("Gone")
        #expect(!FolderCatalog.isReadable(root: missing))
        #expect(FolderCatalog.enumerate(root: missing).isEmpty)
        #expect(AutoRecorder(folderID: UUID()).discover(root: missing) == nil)
        #expect(AutoRecorder(folderID: UUID()).discover(root: root) == [])
    }
}

struct CheapFingerprintTests {
    @Test func fingerprintIsStableWhenNothingChanges() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root, "A.app", id: "com.example.a")
        let first = try #require(CheapFingerprint.of(bundle: app))
        _ = try Data(contentsOf: app.appendingPathComponent("Contents/MacOS/Main"))
        try Data("note".utf8).write(to: app.appendingPathComponent("Contents/Resources.txt"))
        #expect(CheapFingerprint.of(bundle: app) == first)
    }

    @Test func fingerprintChangesWhenExecutableIsRewritten() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root, "A.app", id: "com.example.a")
        let first = try #require(CheapFingerprint.of(bundle: app))
        try thinArm64Header.write(to: app.appendingPathComponent("Contents/MacOS/Main"))
        let second = try #require(CheapFingerprint.of(bundle: app))
        #expect(second != first)
        try (thinArm64Header + Data([1])).write(to: app.appendingPathComponent("Contents/MacOS/Main"), options: .atomic)
        #expect(CheapFingerprint.of(bundle: app) != second)
    }

    @Test func fingerprintChangesWhenInfoPlistOrCodeResourcesChange() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root, "A.app", id: "com.example.a")
        let first = try #require(CheapFingerprint.of(bundle: app))
        try Data("changed resources".utf8).write(to: app.appendingPathComponent("Contents/_CodeSignature/CodeResources"))
        let second = try #require(CheapFingerprint.of(bundle: app))
        #expect(second != first)
        try makeApp(root, "A.app", id: "com.example.a", version: "1.1", codeResources: false)
        #expect(CheapFingerprint.of(bundle: app) != second)
    }

    @Test func fingerprintHoldsNoPathAndNeedsInfoPlist() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root, "Path Probe.app", id: "com.example.probe")
        let value = try #require(CheapFingerprint.of(bundle: app)).value
        #expect(!value.contains("/") && !value.contains("Path Probe") && !value.contains("Main"))
        #expect(!PathScreen.looksLikePath(value))
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Info.plist"))
        #expect(CheapFingerprint.of(bundle: app) == nil)
    }
}

struct AutoRecorderTests {
    let folder = UUID(uuidString: "F01DE500-0000-4000-8000-000000000001")!

    private func run(_ recorder: AutoRecorder, _ root: URL, _ previous: [AppLedger], _ fake: FakeInspector,
                     now: Date = t0) throws -> AutoRecordResult {
        let discovered = try #require(recorder.discover(root: root))
        return recorder.step(previous: previous, discovered: discovered, inspector: fake.inspect, now: now)
    }

    @Test func newAppGetsAFolderLedgerWithAFirstObservedEntry() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "Editor.app", id: "com.example.editor")
        try makeApp(root, "Utilities/Tool.app", id: "com.example.tool")
        let fake = FakeInspector()
        let result = try run(AutoRecorder(folderID: folder), root, [], fake)
        #expect(result.inspectedCount == 2 && fake.calls == ["Editor.app", "Tool.app"])
        #expect(result.ledgers.count == 2 && result.newEntries.count == 2)
        let editor = result.ledgers[0]
        #expect(editor.source == .folder(folder) && editor.source.folderID == folder)
        #expect(editor.displayName == "Editor")
        #expect(editor.entries.map(\.kind) == [.observed] && editor.pinnedBundleID == "com.example.editor")
        #expect(editor.appKey == AutoRecorder.appKey(folderID: folder, relativePath: "Editor.app", bundleID: "com.example.editor"))
        #expect(editor.lastFingerprint != nil && editor.bookmark == nil)
        #expect(result.newEntries.map(\.ledgerID) == result.ledgers.map(\.id))
        #expect(result.newEntries[0].displayName == "Editor")
        #expect(result.ledgers.allSatisfy { LedgerChain.verify($0).isIntact })
    }

    @Test func unchangedAppsAreNotInspectedAgain() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "A.app", id: "com.example.a")
        try makeApp(root, "B.app", id: "com.example.b")
        let recorder = AutoRecorder(folderID: folder)
        let first = try run(recorder, root, [], FakeInspector())
        let fake = FakeInspector()
        let second = try run(recorder, root, first.ledgers, fake, now: t0.addingTimeInterval(60))
        #expect(fake.calls.isEmpty && second.inspectedCount == 0 && second.newEntries.isEmpty)
        #expect(second.ledgers == first.ledgers)
    }

    @Test func onlyAppsWithAChangedFingerprintAreInspected() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "A.app", id: "com.example.a")
        let b = try makeApp(root, "B.app", id: "com.example.b")
        try makeApp(root, "Group/C.app", id: "com.example.c")
        let recorder = AutoRecorder(folderID: folder)
        let first = try run(recorder, root, [], FakeInspector())
        try (thinArm64Header + Data("rebuilt".utf8)).write(to: b.appendingPathComponent("Contents/MacOS/Main"))
        let fake = FakeInspector()
        let second = try run(recorder, root, first.ledgers, fake, now: t0.addingTimeInterval(60))
        #expect(fake.calls == ["B.app"] && second.inspectedCount == 1)
        #expect(second.newEntries.count == 1)
        let entry = try #require(second.newEntries.first?.entry)
        #expect(entry.seq == 2 && entry.anomalies == [.silentRebuild])
        #expect(second.ledgers[0] == first.ledgers[0] && second.ledgers[2] == first.ledgers[2])
        #expect(second.ledgers[1].entries.count == 2 && LedgerChain.verify(second.ledgers[1]).isIntact)
    }

    @Test func changedFingerprintWithSameContentAddsNoEntry() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try makeApp(root, "A.app", id: "com.example.a")
        let recorder = AutoRecorder(folderID: folder)
        let first = try run(recorder, root, [], FakeInspector())
        try thinArm64Header.write(to: a.appendingPathComponent("Contents/MacOS/Main"))
        let fake = FakeInspector()
        let second = try run(recorder, root, first.ledgers, fake)
        #expect(fake.calls == ["A.app"] && second.newEntries.isEmpty)
        #expect(second.ledgers[0].entries.count == 1)
        #expect(second.ledgers[0].lastFingerprint != first.ledgers[0].lastFingerprint)
        #expect(second.ledgers[0].lastCheckedAt == LedgerCoding.normalized(t0.addingTimeInterval(1)))
    }

    @Test func removedAppGetsExactlyOneRemovedEntry() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "A.app", id: "com.example.a")
        let b = try makeApp(root, "B.app", id: "com.example.b")
        let recorder = AutoRecorder(folderID: folder)
        let first = try run(recorder, root, [], FakeInspector())
        try FileManager.default.removeItem(at: b)
        let later = t0.addingTimeInterval(3600)
        let second = try run(recorder, root, first.ledgers, FakeInspector(), now: later)
        #expect(second.newEntries.count == 1)
        let removed = second.ledgers[1]
        #expect(removed.isRemoved && removed.entries.map(\.kind) == [.observed, .removed])
        #expect(removed.latest?.observation.observedAt == LedgerCoding.normalized(later))
        #expect(removed.latest?.changes.isEmpty == true && removed.latest?.anomalies.isEmpty == true)
        #expect(removed.lastFingerprint == nil && LedgerChain.verify(removed).isIntact)
        let third = try run(recorder, root, second.ledgers, FakeInspector(), now: later.addingTimeInterval(60))
        #expect(third.newEntries.isEmpty && third.ledgers == second.ledgers)
        #expect(third.ledgers.count == 2 && !third.ledgers[0].isRemoved)
    }

    @Test func returningAppIsObservedAgainAfterRemoval() throws {
        let root = try tempDirectory(), stash = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: stash) }
        let a = try makeApp(root, "A.app", id: "com.example.a")
        let recorder = AutoRecorder(folderID: folder)
        let first = try run(recorder, root, [], FakeInspector())
        try FileManager.default.moveItem(at: a, to: stash.appendingPathComponent("A.app"))
        let second = try run(recorder, root, first.ledgers, FakeInspector())
        try FileManager.default.moveItem(at: stash.appendingPathComponent("A.app"), to: a)
        let fake = FakeInspector()
        let third = try run(recorder, root, second.ledgers, fake)
        #expect(fake.calls == ["A.app"])
        #expect(third.ledgers[0].entries.map(\.kind) == [.observed, .removed, .observed])
        #expect(!third.ledgers[0].isRemoved && LedgerChain.verify(third.ledgers[0]).isIntact)
    }

    @Test func pickedAndOtherFolderLedgersStayUnchanged() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "A.app", id: "com.example.a")
        var picked = AppLedger(displayName: "Picked", bookmark: Data([9]))
        LedgerChain.append(obs("com.example.picked"), kind: .observed, to: &picked)
        var foreign = AppLedger(displayName: "Other folder", source: .folder(UUID()), appKey: "k1-other")
        LedgerChain.append(obs("com.example.foreign"), kind: .observed, to: &foreign)
        let result = try run(AutoRecorder(folderID: folder), root, [picked, foreign], FakeInspector())
        #expect(result.ledgers.count == 3)
        #expect(result.ledgers[0] == picked && result.ledgers[1] == foreign)
        #expect(result.newEntries.count == 1 && result.newEntries[0].ledgerID == result.ledgers[2].id)
    }

    @Test func failedInspectionKeepsAnEmptyLedgerAndWaitsForTheNextChange() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try makeApp(root, "A.app", id: "com.example.a")
        let recorder = AutoRecorder(folderID: folder)
        let failing = FakeInspector(); failing.failure = .signingUnreadable
        let first = try run(recorder, root, [], failing)
        #expect(first.ledgers.count == 1 && first.ledgers[0].entries.isEmpty && first.newEntries.isEmpty)
        #expect(first.failures == [first.ledgers[0].id: .signingUnreadable])
        let again = FakeInspector()
        #expect(try run(recorder, root, first.ledgers, again).inspectedCount == 0)
        let racing = FakeInspector(); racing.failure = .changedDuringInspection
        try thinArm64Header.write(to: a.appendingPathComponent("Contents/MacOS/Main"))
        let raced = try run(recorder, root, first.ledgers, racing)
        #expect(raced.inspectedCount == 1 && raced.ledgers[0].lastFingerprint == first.ledgers[0].lastFingerprint)
        let retry = FakeInspector()
        let fixed = try run(recorder, root, raced.ledgers, retry)
        #expect(retry.calls == ["A.app"] && fixed.ledgers[0].entries.count == 1)
        try FileManager.default.removeItem(at: a)
        let emptyFailing = try run(recorder, root, first.ledgers, FakeInspector())
        #expect(emptyFailing.ledgers.isEmpty && emptyFailing.newEntries.isEmpty)
    }

    @Test func appKeyIsPathFreeAndFollowsPlaceAndIdentity() {
        let key = AutoRecorder.appKey(folderID: folder, relativePath: "Utilities/Tool.app", bundleID: "com.example.tool")
        #expect(key == AutoRecorder.appKey(folderID: folder, relativePath: "Utilities/Tool.app", bundleID: "com.example.tool"))
        #expect(key.hasPrefix("k1-") && key.count == 35 && !key.contains("/") && !key.contains("Tool"))
        #expect(key != AutoRecorder.appKey(folderID: folder, relativePath: "Tool.app", bundleID: "com.example.tool"))
        #expect(key != AutoRecorder.appKey(folderID: folder, relativePath: "Utilities/Tool.app", bundleID: "com.example.other"))
        #expect(key != AutoRecorder.appKey(folderID: UUID(), relativePath: "Utilities/Tool.app", bundleID: "com.example.tool"))
    }

    @Test func removedLedgersRefuseAcknowledgementAndLeaveTheComparison() throws {
        var ledger = AppLedger(displayName: "A", source: .folder(folder), appKey: "k1-a")
        #expect(LedgerChain.markRemoved(&ledger, at: t0) == nil)
        LedgerChain.append(obs(), kind: .observed, to: &ledger)
        let removed = try #require(LedgerChain.markRemoved(&ledger, at: t0.addingTimeInterval(60)))
        #expect(removed.kind == .removed && removed.seq == 2)
        #expect(LedgerChain.markRemoved(&ledger, at: t0.addingTimeInterval(120)) == nil)
        #expect(LedgerChain.acknowledge(obs(at: t0.addingTimeInterval(180)), in: &ledger) == .nothingToAcknowledge)
        #expect(ledger.entries.count == 2 && LedgerChain.verify(ledger).isIntact)
        let other = LedgerFile(ledgers: [], exportedAt: t0)
        #expect(CrossMacComparison.compare(here: [ledger], there: other).isEmpty)
        let text = LedgerReport.make(ledger, verdict: LedgerChain.verify(ledger), now: t0)
        #expect(text.contains("Entry 2 removed"))
    }
}

struct ReviewTwoCoreTests {
    @Test func aFolderThatCannotBeListedGivesNoEntriesInsteadOfAnEmptyList() throws {
        let root = try tempDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "Alpha.app", id: "com.example.alpha")
        #expect(FolderCatalog.entries(root: root)?.count == 1)
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        #expect(FolderCatalog.entries(root: root) == nil)
        #expect(AutoRecorder(folderID: UUID()).discover(root: root) == nil)
    }

    @Test func slowSignatureChecksAreBoundedAndDoNotPileUp() {
        let pool = ValidityChecks(lingeringLimit: 1)
        let calls = Counter()
        let release = DispatchSemaphore(value: 0)
        let slow: @Sendable (URL) -> SignatureValidity = { _ in calls.bump(); release.wait(); return .valid }
        let url = URL(fileURLWithPath: "/nonexistent/Slow.app")
        #expect(pool.check(url, timeout: 0.05, using: slow) == .notChecked)
        #expect(pool.lingeringCount == 1)
        for _ in 0..<1000 where calls.value == 0 { usleep(10_000) }
        // The limit is reached, so the next check is recorded as notChecked without starting.
        #expect(pool.check(url, timeout: 0.05, using: slow) == .notChecked)
        #expect(calls.value == 1)
        release.signal()
        for _ in 0..<1000 where pool.lingeringCount > 0 { usleep(10_000) }
        #expect(pool.lingeringCount == 0)
        #expect(pool.check(url, timeout: 2, using: { _ in .valid }) == .valid)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
