import Foundation
import Testing
@testable import LedgerCore

private func single(_ o: LedgerObservation, name: String = "Fixture") -> AppLedger {
    var l = AppLedger(displayName: name, bookmark: Data("bookmark-bytes".utf8))
    LedgerChain.append(o, kind: .observed, to: &l)
    return l
}
private func verdict(_ here: LedgerObservation, _ there: LedgerObservation) -> CrossMacVerdict? {
    CrossMacComparison.compare(here: [single(here)], there: LedgerFile(ledgers: [single(there)], exportedAt: t0)).first?.verdict
}

struct CrossMacTests {
    @Test func sameBuildWhenVersionBuildAndHashesMatch() {
        #expect(verdict(obs(), obs(at: t0.addingTimeInterval(500))) == .sameBuild)
        #expect(verdict(obs(version: "2.0"), obs(version: "2.0.0")) == .sameBuild)
    }
    @Test func differentBinaryForTheSameVersion() {
        #expect(verdict(obs(), obs(sha: String(repeating: "d", count: 64))) == .differentBinarySameVersion)
        #expect(verdict(obs(sha: nil), obs(cdhash: String(repeating: "c", count: 40), sha: nil)) == .differentBinarySameVersion)
        #expect(verdict(obs(), obs(build: "101")) == .differentBinarySameVersion)
        #expect(verdict(obs(cdhash: nil, sha: nil), obs(cdhash: nil, sha: nil)) == .differentBinarySameVersion)
    }
    @Test func sameUniversalExecutableOnTwoArchitecturesIsTheSameBuild() {
        #expect(verdict(obs(), obs(cdhash: String(repeating: "c", count: 40))) == .sameBuild)
        #expect(verdict(obs(cdhash: nil), obs(cdhash: String(repeating: "c", count: 40))) == .sameBuild)
    }
    @Test func differentVersion() {
        #expect(verdict(obs(version: "1.0"), obs(version: "1.1")) == .differentVersion)
        #expect(verdict(obs(version: "1.0b1"), obs(version: "1.0b2")) == .differentVersion)
    }
    @Test func onlyHereAndOnlyThereRowsAreSortedByBundleID() {
        let here = [single(obs("com.example.b")), single(obs("com.example.a"))]
        let there = LedgerFile(ledgers: [single(obs("com.example.c")), single(obs("com.example.a"))], exportedAt: t0)
        let rows = CrossMacComparison.compare(here: here, there: there)
        #expect(rows.map(\.bundleID) == ["com.example.a", "com.example.b", "com.example.c"])
        #expect(rows.map(\.verdict) == [.sameBuild, .onlyHere, .onlyThere])
        #expect(rows[1].there == nil && rows[2].here == nil)
    }
    @Test func latestEntryOfTheNewestLedgerIsCompared() {
        var older = threeEntryLedger()
        older.entries = Array(older.entries.prefix(1))
        let newer = threeEntryLedger()
        let there = LedgerFile(ledgers: [single(newer.entries[2].observation)], exportedAt: t0)
        let rows = CrossMacComparison.compare(here: [newer, older], there: there)
        #expect(rows.count == 1)
        #expect(rows[0].verdict == .sameBuild)
        #expect(rows[0].here?.version == "1.2")
    }
    @Test func sampleOtherMacCoversEveryVerdict() {
        let now = t0
        let rows = CrossMacComparison.compare(here: SampleLedger.ledgers(now: now), there: SampleLedger.otherMac(now: now))
        #expect(Set(rows.map(\.verdict)) == Set(CrossMacVerdict.allCases))
        #expect(CrossMacVerdict.allCases.map(\.label).allSatisfy { !$0.isEmpty })
    }
}

struct LedgerExportTests {
    private func exportedText() throws -> (Data, String) {
        var ledger = threeEntryLedger()
        ledger.displayName = "/Users/someone/Applications/Editor.app"
        LedgerChain.append(obs(version: "1.3", build: "400",
                               ent: DeclarationNormalizer.normalize(entitlements: [
                                   "com.apple.security.temporary-exception.files.absolute-path.read-only": ["/Users/someone/Library/Data"]]),
                               at: t0.addingTimeInterval(9e5)), kind: .observed, to: &ledger)
        let data = try LedgerFile(ledgers: [ledger], exportedAt: t0).encoded()
        return (data, String(decoding: data, as: UTF8.self))
    }

    @Test func exportStripsBookmarksAndPaths() throws {
        let (_, text) = try exportedText()
        #expect(!text.contains("/Users"))
        #expect(!text.contains("\"bookmark\""))
        #expect(!text.contains("file://"))
        #expect(text.contains("\"format\" : \"nativeledger.v1\""))
        #expect(text.contains("path value sha256 "))
    }
    @Test func exportedFileDecodesAndChainStillVerifies() throws {
        let (data, _) = try exportedText()
        let file = try LedgerFile.decode(data)
        #expect(file.format == LedgerFile.currentFormat)
        #expect(file.ledgers.count == 1)
        #expect(file.ledgers[0].bookmark == nil)
        #expect(file.ledgers[0].displayName == "com.example.editor")
        #expect(LedgerChain.verify(file.ledgers[0]) == .intact(count: 4))
    }
    @Test func decodeRejectsOtherFormatsAndGarbage() throws {
        var file = LedgerFile(ledgers: [], exportedAt: t0)
        file.format = "nativeledger.v9"
        let data = try LedgerCoding.encoder().encode(file)
        #expect(throws: LedgerFileError.unsupportedFormat("nativeledger.v9")) { try LedgerFile.decode(data) }
        #expect(throws: LedgerFileError.unreadable) { try LedgerFile.decode(Data("{not json".utf8)) }
    }
    @Test func decodeStripsBookmarksFromForeignFiles() throws {
        struct Raw: Encodable { var format = "nativeledger.v1"; var exportedAt = t0; var ledgers: [AppLedger] }
        let data = try LedgerCoding.encoder().encode(Raw(ledgers: [threeEntryLedger()]))
        #expect(String(decoding: data, as: UTF8.self).contains("\"bookmark\""))
        #expect(try LedgerFile.decode(data).ledgers[0].bookmark == nil)
    }
    @Test func pathLikeEntitlementValuesAreStoredAsDigests() {
        let values = DeclarationNormalizer.normalize(entitlements: [
            "a": ["/Users/someone/x"], "b": ["/Users/someone/y"], "c": true, "d": "group.example"])
        #expect(values["a"]?.hasPrefix("path value sha256 ") == true)
        #expect(values["a"] != values["b"])
        #expect(values["c"] == "true")
        #expect(values["d"] == "\"group.example\"")
    }
}
