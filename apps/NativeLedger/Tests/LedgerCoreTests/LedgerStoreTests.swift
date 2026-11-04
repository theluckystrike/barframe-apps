import Foundation
import Testing
@testable import LedgerCore

struct LedgerStoreTests {
    @Test func missingFileLoadsEmptyAndSaveRoundtrips() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        #expect(throws: LedgerStoreError.notLoaded) { try store.save([]) }
        #expect(store.load() == .loaded([]))
        let ledger = threeEntryLedger()
        try store.save([ledger])
        #expect(store.fileURL.lastPathComponent == "ledgers.json")
        #expect(LedgerStore(directory: dir).load() == .loaded([ledger]))
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"schema\":2"))
        guard case .loaded(let back) = LedgerStore(directory: dir).load() else { Issue.record("not loaded"); return }
        #expect(LedgerChain.verify(back[0]) == .intact(count: 3))
        #expect(back[0].bookmark == ledger.bookmark)
    }

    @Test func corruptFilePausesWritesAndKeepsBytes() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        let garbage = Data("{\"schema\":2,\"ledgers\":[{\"broken\"".utf8)
        try garbage.write(to: store.fileURL)
        #expect(store.load() == .corrupt)
        #expect(store.writesPaused)
        #expect(throws: LedgerStoreError.writesPaused) { try store.save([threeEntryLedger()]) }
        #expect(try Data(contentsOf: store.fileURL) == garbage)
        #expect(store.retry() == .corrupt)
    }

    @Test func duplicateLedgerIDsAreTreatedAsCorrupt() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        #expect(store.load() == .loaded([]))
        let ledger = threeEntryLedger()
        try store.save([ledger, ledger])
        let reread = LedgerStore(directory: dir)
        #expect(reread.load() == .corrupt)
        #expect(reread.writesPaused)
    }

    @Test func ledgerWithoutLastCheckedDateDecodes() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        let id = UUID().uuidString
        try Data(#"{"schema":2,"ledgers":[{"id":"\#(id)","displayName":"Old","entries":[]}]}"#.utf8).write(to: store.fileURL)
        guard case .loaded(let back) = store.load() else { Issue.record("not loaded"); return }
        #expect(back.first?.lastCheckedAt == nil)
        #expect(back.first?.displayName == "Old")
    }

    @Test func otherSchemaIsTreatedAsCorrupt() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        try Data("{\"schema\":1,\"ledgers\":[]}".utf8).write(to: store.fileURL)
        #expect(store.load() == .corrupt)
    }

    @Test func retryResumesWhenTheFileIsRepaired() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        try Data("nope".utf8).write(to: store.fileURL)
        #expect(store.load() == .corrupt)
        try Data("{\"schema\":2,\"ledgers\":[]}".utf8).write(to: store.fileURL)
        #expect(store.retry() == .loaded([]))
        #expect(!store.writesPaused)
        try store.save([threeEntryLedger()])
    }

    @Test func explicitRecoveryCopiesTheCorruptFileFirst() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        let garbage = Data("corrupt bytes".utf8)
        try garbage.write(to: store.fileURL)
        #expect(store.load() == .corrupt)
        let copy = try #require(try store.recoverByStartingFresh())
        #expect(copy.lastPathComponent.hasPrefix("ledgers.corrupt-"))
        #expect(try Data(contentsOf: copy) == garbage)
        #expect(!store.writesPaused)
        #expect(LedgerStore(directory: dir).load() == .loaded([]))
        try store.save([threeEntryLedger()])
    }
}
