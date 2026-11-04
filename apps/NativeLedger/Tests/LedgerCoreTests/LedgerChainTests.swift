import Foundation
import Testing
@testable import LedgerCore

struct LedgerChainTests {
    @Test func emptyLedgerIsIntact() {
        #expect(LedgerChain.verify(AppLedger(displayName: "Empty")) == .intact(count: 0))
    }

    @Test func appendedEntriesFormAnIntactLinkedChain() {
        let ledger = threeEntryLedger()
        #expect(ledger.entries.map(\.seq) == [1, 2, 3])
        #expect(ledger.entries[0].previousHash == String(repeating: "0", count: 64))
        #expect(ledger.entries[1].previousHash == ledger.entries[0].entryHash)
        #expect(ledger.entries[2].previousHash == ledger.entries[1].entryHash)
        #expect(ledger.entries.allSatisfy { $0.entryHash.count == 64 && $0.entryHash.allSatisfy(\.isHexDigit) })
        #expect(LedgerChain.verify(ledger) == .intact(count: 3))
    }

    @Test func identicalObservationIsNotAppended() {
        var ledger = threeEntryLedger()
        let latest = ledger.entries[2].observation
        var later = latest; later.observedAt = latest.observedAt.addingTimeInterval(3600)
        #expect(LedgerChain.append(later, kind: .observed, to: &ledger) == nil)
        #expect(ledger.entries.count == 3)
    }

    @Test func acknowledgedEntryIsAppendedEvenIfIdentical() throws {
        var ledger = threeEntryLedger()
        let latest = ledger.entries[2].observation
        let entry = try #require(LedgerChain.append(latest, kind: .acknowledged, to: &ledger))
        #expect(entry.seq == 4)
        #expect(entry.kind == .acknowledged)
        #expect(entry.changes.isEmpty)
        #expect(entry.anomalies.isEmpty)
        #expect(ledger.baseline?.seq == 4)
        #expect(LedgerChain.verify(ledger) == .intact(count: 4))
    }

    @Test func observedEntryAfterAcknowledgementWithSameContentIsNotAppended() {
        var ledger = AppLedger(displayName: "A")
        LedgerChain.append(obs(), kind: .acknowledged, to: &ledger)
        #expect(LedgerChain.append(obs(at: t0.addingTimeInterval(60)), kind: .observed, to: &ledger) == nil)
    }

    @Test func changesAreRecordedAgainstThePreviousEntry() {
        let ledger = threeEntryLedger()
        #expect(ledger.entries[0].changes.isEmpty)
        let fields = ledger.entries[1].changes.map(\.field)
        #expect(fields == [.version, .build, .cdhash, .executableSHA256])
        #expect(ledger.entries[1].changes.first?.before == "1.0")
        #expect(ledger.entries[1].changes.first?.after == "1.1")
    }

    @Test func dateIsNormalizedToMillisecondsBeforeHashing() throws {
        var ledger = AppLedger(displayName: "A")
        let entry = try #require(LedgerChain.append(obs(at: Date(timeIntervalSince1970: 1_790_000_000.123_456)), kind: .observed, to: &ledger))
        #expect(entry.observation.observedAt == Date(timeIntervalSince1970: 1_790_000_000.123))
        let text = String(decoding: LedgerChain.canonicalBytes(entry), as: UTF8.self)
        #expect(text.contains("\"observedAt\":\"2026-09-21T14:13:20.123Z\""))
    }

    @Test func canonicalBytesExcludeEntryHashAndSortKeys() throws {
        let entry = threeEntryLedger().entries[1]
        let text = String(decoding: LedgerChain.canonicalBytes(entry), as: UTF8.self)
        #expect(!text.contains("entryHash"))
        #expect(text.contains("previousHash"))
        let keys = ["anomalies", "changes", "kind", "observation", "previousHash", "seq"]
        let positions = try keys.map { try #require(text.range(of: "\"\($0)\":")).lowerBound }
        #expect(positions == positions.sorted())
        var other = entry; other.entryHash = "changed"
        #expect(LedgerChain.canonicalBytes(other) == LedgerChain.canonicalBytes(entry))
    }

    @Test func canonicalBytesAreStableAcrossEncodeDecodeRoundtrip() throws {
        let ledger = threeEntryLedger()
        let encoders = [LedgerCoding.encoder(), LedgerCoding.encoder(pretty: true)]
        for encoder in encoders {
            let data = try encoder.encode(ledger)
            let decoded = try LedgerCoding.decoder().decode(AppLedger.self, from: data)
            #expect(decoded == ledger)
            for (a, b) in zip(decoded.entries, ledger.entries) { #expect(LedgerChain.canonicalBytes(a) == LedgerChain.canonicalBytes(b)) }
            #expect(LedgerChain.verify(decoded) == .intact(count: 3))
        }
    }

    @Test func dateTextRoundtripsExactly() {
        for value in [0.0, 0.001, 0.999, 1_790_000_000.5, 1_790_000_000.123_4, 1_790_000_000.999_6, -1.25] {
            let date = LedgerCoding.normalized(Date(timeIntervalSince1970: value))
            let text = LedgerCoding.string(from: date)
            #expect(text.hasSuffix("Z"))
            #expect(text.split(separator: ".").last?.count == 4)
            #expect(LedgerCoding.date(from: text) == date)
        }
        #expect(LedgerCoding.date(from: "2026-10-16T07:40:00Z") == Date(timeIntervalSince1970: 1_792_136_400))
        #expect(LedgerCoding.date(from: "not a date") == nil)
    }

    @Test func acknowledgeRefusesABrokenChain() {
        var ledger = threeEntryLedger()
        ledger.entries[1].observation.version = "9.9"
        let before = ledger
        #expect(LedgerChain.acknowledge(ledger.entries[2].observation, in: &ledger) == .chainBroken)
        #expect(ledger == before)
    }
    @Test func appendNumbersByPositionEvenAfterATamperedSeq() throws {
        var ledger = threeEntryLedger()
        ledger.entries[2].seq = Int.max
        let entry = try #require(LedgerChain.append(obs(version: "2.0", build: "400", at: t0.addingTimeInterval(4e5)), kind: .observed, to: &ledger))
        #expect(entry.seq == 4)
        #expect(brokenSeq(LedgerChain.verify(ledger)) == 3)
    }
    @Test func acknowledgeHelperOutcomes() throws {
        var empty = AppLedger(displayName: "Empty")
        #expect(LedgerChain.acknowledge(obs(), in: &empty) == .nothingToAcknowledge)

        var ledger = threeEntryLedger()
        var fresh = ledger.entries[2].observation; fresh.observedAt = t0.addingTimeInterval(4 * 86400)
        guard case .acknowledged(let ack) = LedgerChain.acknowledge(fresh, in: &ledger) else { Issue.record("not acknowledged"); return }
        #expect(ack.seq == 4 && ack.kind == .acknowledged)
        #expect(LedgerChain.acknowledge(fresh, in: &ledger) == .alreadyAcknowledged)

        var changed = fresh; changed.binary.cdhash = String(repeating: "f", count: 40); changed.binary.executableSHA256 = String(repeating: "e", count: 64)
        guard case .changedSinceLatest(let entry) = LedgerChain.acknowledge(changed, in: &ledger) else { Issue.record("not refused"); return }
        #expect(entry.kind == .observed && entry.anomalies == [.silentRebuild])
        #expect(ledger.openAnomalies == [.silentRebuild])
        #expect(LedgerChain.verify(ledger) == .intact(count: 5))
    }

    @Test func openAnomaliesClearAfterAcknowledgement() {
        var ledger = threeEntryLedger()
        LedgerChain.append(obs(version: "1.2", build: "300", cdhash: String(repeating: "9", count: 40), at: t0.addingTimeInterval(9e5)), kind: .observed, to: &ledger)
        #expect(ledger.openAnomalies == [.silentRebuild])
        LedgerChain.append(ledger.entries.last!.observation, kind: .acknowledged, to: &ledger)
        #expect(ledger.openAnomalies.isEmpty)
    }
}

struct ChainTamperTests {
    private func tampered(_ change: (inout LedgerEntry) -> Void, at index: Int = 1) -> ChainVerdict {
        var ledger = threeEntryLedger()
        change(&ledger.entries[index])
        return LedgerChain.verify(ledger)
    }

    @Test func tamperVersionBreaksAtThatEntry() { #expect(brokenSeq(tampered { $0.observation.version = "9.9" }) == 2) }
    @Test func tamperBuildBreaksAtThatEntry() { #expect(brokenSeq(tampered { $0.observation.build = "999" }) == 2) }
    @Test func tamperBundleIDBreaksAtThatEntry() { #expect(brokenSeq(tampered { $0.observation.bundleID = "com.example.other" }) == 2) }
    @Test func tamperArchitectureBreaksAtThatEntry() { #expect(brokenSeq(tampered { $0.observation.architecture = .intelOnly }) == 2) }
    @Test func tamperCdhashBreaksAtThatEntry() { #expect(brokenSeq(tampered { $0.observation.binary.cdhash = String(repeating: "c", count: 40) }) == 2) }
    @Test func tamperExecutableHashBreaksAtThatEntry() { #expect(brokenSeq(tampered { $0.observation.binary.executableSHA256 = nil }) == 2) }
    @Test func tamperDateBreaksAtThatEntry() { #expect(brokenSeq(tampered { $0.observation.observedAt.addTimeInterval(1) }) == 2) }
    @Test func tamperSigningBreaksAtThatEntry() {
        #expect(brokenSeq(tampered { $0.observation.signing = .read(identifier: "com.example.editor", team: "TEAMZZZZZZ", entitlements: [:]) }) == 2)
        #expect(brokenSeq(tampered({ $0.observation.signing = .unsigned }, at: 0)) == 1)
    }
    @Test func tamperKindBreaksAtThatEntry() { #expect(brokenSeq(tampered({ $0.kind = .acknowledged }, at: 2)) == 3) }
    @Test func tamperChangesAndAnomaliesBreakAtThatEntry() {
        #expect(brokenSeq(tampered { $0.changes = [] }) == 2)
        #expect(brokenSeq(tampered { $0.anomalies = [.teamChange] }) == 2)
    }
    @Test func tamperLinksAndHashesBreakAtThatEntry() {
        #expect(brokenSeq(tampered { $0.previousHash = String(repeating: "1", count: 64) }) == 2)
        #expect(brokenSeq(tampered({ $0.previousHash = String(repeating: "1", count: 64) }, at: 0)) == 1)
        #expect(brokenSeq(tampered { $0.entryHash = String(repeating: "e", count: 64) }) == 2)
    }
    @Test func tamperedAndRehashedEntryBreaksAtTheNextEntry() {
        let verdict = tampered { entry in
            entry.observation.version = "1.15"
            entry.entryHash = LedgerChain.hash(entry)
        }
        #expect(verdict == .broken(atSeq: 3, reason: "Entry 3 does not link to entry 2."))
    }
    @Test func deletedMiddleEntryIsDetected() {
        var ledger = threeEntryLedger()
        ledger.entries.remove(at: 1)
        #expect(brokenSeq(LedgerChain.verify(ledger)) == 2)
    }
    @Test func deletedFirstEntryIsDetectedEvenWhenRenumbered() {
        var ledger = threeEntryLedger()
        ledger.entries.removeFirst()
        #expect(brokenSeq(LedgerChain.verify(ledger)) == 1)
        for i in ledger.entries.indices { ledger.entries[i].seq = i + 1 }
        #expect(brokenSeq(LedgerChain.verify(ledger)) == 1)
    }
    @Test func reorderedEntriesAreDetected() {
        var ledger = threeEntryLedger()
        ledger.entries.swapAt(1, 2)
        #expect(brokenSeq(LedgerChain.verify(ledger)) == 2)
        for i in ledger.entries.indices { ledger.entries[i].seq = i + 1 }
        #expect(brokenSeq(LedgerChain.verify(ledger)) == 2)
    }
}
