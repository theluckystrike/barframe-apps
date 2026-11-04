import Foundation
import Testing
import LedgerCore
@testable import NativeLedger

@MainActor @Suite struct LedgerModelTicketTests {
    @Test func lateResultAfterRemoveIsDiscarded() async throws {
        let inspector = ScriptedInspector([.complete(observation())], gated: true)
        let ledger = AppLedger(displayName: "Tool")
        let model = LedgerModel(store: nil, inspector: inspector, seed: [ledger])
        let task = try #require(model.inspect(ledger.id))
        #expect(model.isBusy(ledger.id))
        model.remove(ledger.id)
        inspector.gate?.signal()
        await task.value
        #expect(model.ledgers.isEmpty)
        #expect(model.notices[ledger.id] == nil)
        #expect(!model.isBusy(ledger.id))
    }

    @Test func lateResultAfterReloadIsDiscarded() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LedgerStore(directory: folder)
        _ = store.load()
        let ledger = AppLedger(displayName: "Tool")
        try store.save([ledger])
        let inspector = ScriptedInspector([.complete(observation())], gated: true)
        let model = LedgerModel(store: store, inspector: inspector)
        let task = try #require(model.inspect(ledger.id))
        model.retrySavedData()
        inspector.gate?.signal()
        await task.value
        #expect(model.ledger(ledger.id)?.entries.isEmpty == true)
        guard case .loaded(let saved) = LedgerStore(directory: folder).load() else { Issue.record("store unreadable"); return }
        #expect(saved.first?.entries.isEmpty == true)
    }

    @Test func lateResultAfterAccessRenewedIsDiscarded() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try fakeApp(in: folder)
        let inspector = ScriptedInspector([.complete(observation())], gated: true)
        let model = LedgerModel(store: nil, inspector: inspector)
        let id = try #require(model.add(urls: [app]).first)
        let task = try #require(model.inspect(id))
        #expect(model.add(urls: [app]) == [id])
        #expect(model.ledgers.count == 1)
        inspector.gate?.signal()
        await task.value
        #expect(model.ledger(id)?.entries.isEmpty == true)
        #expect(!model.isBusy(id))
    }

    @Test func secondInspectWhileBusyIsRefused() async throws {
        let inspector = ScriptedInspector([.complete(observation())], gated: true)
        let ledger = AppLedger(displayName: "Tool")
        let model = LedgerModel(store: nil, inspector: inspector, seed: [ledger])
        let task = try #require(model.inspect(ledger.id))
        #expect(model.inspect(ledger.id) == nil)
        inspector.gate?.signal()
        await task.value
        #expect(model.ledger(ledger.id)?.entries.count == 1)
        #expect(inspector.calls == 1)
    }
}

@MainActor @Suite struct LedgerModelFlowTests {
    @Test func inspectionAppendsPersistsAndSkipsDuplicates() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inspector = ScriptedInspector([.complete(observation()), .complete(observation(at: appT0.addingTimeInterval(60))),
                                           .complete(observation(sha: String(repeating: "c", count: 64), at: appT0.addingTimeInterval(120)))])
        let store = LedgerStore(directory: folder)
        let ledger = AppLedger(displayName: "Tool")
        _ = store.load(); try store.save([ledger])
        let model = LedgerModel(store: LedgerStore(directory: folder), inspector: inspector)
        #expect(model.badge(ledger) == .notInspected)
        await model.inspect(ledger.id)?.value
        #expect(model.notices[ledger.id] == "Entry 1 recorded.")
        await model.inspect(ledger.id)?.value
        #expect(model.notices[ledger.id] == "No change since entry 1. Nothing was added.")
        await model.inspect(ledger.id)?.value
        let saved = try #require(model.ledger(ledger.id))
        #expect(saved.entries.count == 2)
        #expect(saved.entries[1].anomalies == [.silentRebuild])
        #expect(model.badge(saved) == .anomaly)
        let reloaded = LedgerModel(store: LedgerStore(directory: folder))
        #expect(reloaded.ledger(ledger.id)?.entries == saved.entries)
        #expect(reloaded.verdicts[ledger.id] == .intact(count: 2))
    }

    @Test func differentBundleIdentifierIsRefused() async throws {
        let inspector = ScriptedInspector([.complete(observation()), .complete(observation("com.example.other", version: "2.0"))])
        let ledger = AppLedger(displayName: "Tool")
        let model = LedgerModel(store: nil, inspector: inspector, seed: [ledger])
        await model.inspect(ledger.id)?.value
        await model.inspect(ledger.id)?.value
        #expect(model.ledger(ledger.id)?.entries.count == 1)
        #expect(model.failures[ledger.id] == .identityDiffers)
    }

    @Test func failedOrPartialInspectionAddsNothingAndShowsUnavailable() async throws {
        let partial = InspectionResult(observation: observation(), failure: .signingUnreadable)
        let inspector = ScriptedInspector([.failed(.accessUnavailable), partial])
        let ledger = AppLedger(displayName: "Tool")
        let model = LedgerModel(store: nil, inspector: inspector, seed: [ledger])
        await model.inspect(ledger.id)?.value
        #expect(model.badge(model.ledger(ledger.id)!) == .unavailable)
        #expect(model.notices[ledger.id] == InspectionFailure.accessUnavailable.safeMessage)
        await model.inspect(ledger.id)?.value
        #expect(model.ledger(ledger.id)?.entries.isEmpty == true)
        #expect(model.failures[ledger.id] == .signingUnreadable)
    }

    @Test func acknowledgeRecordsBaselineEntry() async throws {
        let inspector = ScriptedInspector([.complete(observation()), .complete(observation(at: appT0.addingTimeInterval(30)))])
        let ledger = AppLedger(displayName: "Tool")
        let model = LedgerModel(store: nil, inspector: inspector, seed: [ledger])
        #expect(model.acknowledge(ledger.id) == nil)
        await model.inspect(ledger.id)?.value
        await model.acknowledge(ledger.id)?.value
        let after = try #require(model.ledger(ledger.id))
        #expect(after.entries.map(\.kind) == [.observed, .acknowledged])
        #expect(after.baseline?.seq == 2)
        #expect(!model.canAcknowledge(after))
        #expect(model.notices[ledger.id] == "Entry 2 is now the reviewed baseline.")
    }

    @Test func acknowledgeAfterChangeRecordsObservedEntryInstead() async throws {
        let inspector = ScriptedInspector([.complete(observation()), .complete(observation(version: "1.1", build: "110", at: appT0.addingTimeInterval(30)))])
        let ledger = AppLedger(displayName: "Tool")
        let model = LedgerModel(store: nil, inspector: inspector, seed: [ledger])
        await model.inspect(ledger.id)?.value
        await model.acknowledge(ledger.id)?.value
        let after = try #require(model.ledger(ledger.id))
        #expect(after.entries.map(\.kind) == [.observed, .observed])
        #expect(after.baseline == nil)
    }

    @Test func verifyNamesBrokenEntryAndBadgeShowsIt() throws {
        var ledger = AppLedger(displayName: "Tool")
        LedgerChain.append(observation(), kind: .observed, to: &ledger)
        LedgerChain.append(observation(version: "1.1", at: appT0.addingTimeInterval(60)), kind: .observed, to: &ledger)
        ledger.entries[1].observation.build = "999"
        let model = LedgerModel(store: nil, seed: [ledger])
        #expect(model.badge(ledger) == .broken)
        let verdict = model.verify(ledger.id)
        if case .broken(let seq, _) = verdict { #expect(seq == 2) } else { Issue.record("expected broken") }
        #expect(model.notices[ledger.id]?.hasPrefix("Chain broken at entry 2.") == true)
        #expect(model.verifiedAt[ledger.id] != nil)
    }

    @Test func corruptStorePausesWritesAndRecoveryKeepsCopy() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{broken".utf8).write(to: folder.appendingPathComponent(LedgerStore.fileName))
        let model = LedgerModel(store: LedgerStore(directory: folder))
        #expect(model.storageCorrupt)
        #expect(!model.canWrite)
        #expect(!model.canAddApps)
        #expect(model.add(urls: [folder.appendingPathComponent("X.app")]).isEmpty)
        #expect(try Data(contentsOf: folder.appendingPathComponent(LedgerStore.fileName)) == Data("{broken".utf8))
        model.recoverStartingFresh()
        #expect(!model.storageCorrupt)
        #expect(model.canWrite)
        let copies = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("ledgers.corrupt-") }
        #expect(copies.count == 1)
    }

    @Test func addRefusesNonAppsAndRemoveDeletes() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = LedgerModel(store: LedgerStore(directory: folder))
        let a = try fakeApp(in: folder, named: "Alpha"), b = try fakeApp(in: folder, named: "Beta")
        let ids = model.add(urls: [a, b, folder.appendingPathComponent("notes.txt")])
        #expect(ids.count == 2)
        #expect(model.ledgers.map(\.displayName) == ["Alpha", "Beta"])
        #expect(model.notice.contains("notes"))
        #expect(model.ledgers.allSatisfy { $0.bookmark != nil })
        model.remove(ids[0])
        #expect(model.ledgers.map(\.displayName) == ["Beta"])
        #expect(model.selection == ids[1])
        guard case .loaded(let saved) = LedgerStore(directory: folder).load() else { Issue.record("unreadable"); return }
        #expect(saved.map(\.id) == [ids[1]])
    }

    @Test func unchangedReadIsSavedAndClearsTheStaleLabelAfterRelaunch() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LedgerStore(directory: folder)
        _ = store.load()
        var ledger = AppLedger(displayName: "Tool")
        let old = observation(at: Date().addingTimeInterval(-20 * 86400))
        LedgerChain.append(old, kind: .observed, to: &ledger)
        try store.save([ledger])
        var fresh = old; fresh.observedAt = Date()
        let model = LedgerModel(store: store, inspector: ScriptedInspector([.complete(fresh)]))
        await model.inspect(ledger.id)?.value
        #expect(model.ledger(ledger.id)?.entries.count == 1)
        let relaunched = LedgerModel(store: LedgerStore(directory: folder))
        let saved = try #require(relaunched.ledger(ledger.id))
        #expect(saved.lastCheckedAt != nil)
        #expect(!relaunched.isStale(saved, days: 14))
    }

    @Test func renewedBookmarkFromAStaleOneIsSaved() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LedgerStore(directory: folder)
        _ = store.load()
        let ledger = AppLedger(displayName: "Tool", bookmark: Data([1]))
        try store.save([ledger])
        var result = InspectionResult.complete(observation())
        result.refreshedBookmark = Data([2, 2])
        let model = LedgerModel(store: store, inspector: ScriptedInspector([result]))
        await model.inspect(ledger.id)?.value
        guard case .loaded(let back) = LedgerStore(directory: folder).load() else { Issue.record("unreadable"); return }
        #expect(back.first?.bookmark == Data([2, 2]))
    }

    @Test func brokenChainCannotBeAcknowledged() {
        var ledger = AppLedger(displayName: "Tool")
        LedgerChain.append(observation(), kind: .observed, to: &ledger)
        LedgerChain.append(observation(version: "1.1", build: "110"), kind: .observed, to: &ledger)
        ledger.entries[0].observation.build = "999"
        let model = LedgerModel(store: nil, inspector: ScriptedInspector([.complete(ledger.entries[1].observation)]), seed: [ledger])
        #expect(model.badge(ledger) == .broken)
        #expect(!model.canAcknowledge(ledger))
        #expect(model.acknowledge(ledger.id) == nil)
    }

    @Test func staleLabelUsesNewestRead() {
        var ledger = AppLedger(displayName: "Tool")
        LedgerChain.append(observation(at: Date().addingTimeInterval(-20 * 86400)), kind: .observed, to: &ledger)
        let model = LedgerModel(store: nil, seed: [ledger])
        #expect(model.isStale(ledger, days: 14))
        #expect(!model.isStale(ledger, days: 30))
    }
}
