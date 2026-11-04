import Foundation
import CryptoKit
import Testing
@testable import LedgerCore

struct LedgerReportTests {
    private func pathLedger() -> AppLedger {
        var ledger = threeEntryLedger()
        ledger.displayName = "/Users/someone/Applications/Editor.app"
        let ent = ["com.apple.security.app-sandbox": "true", "com.example.raw": "\"/Users/someone/Secret\"",
                   "com.example.encoded": "\"%2FUsers%2Fsomeone\"", "com.example.url": "\"file:///Volumes/Disk\""]
        LedgerChain.append(obs(version: "1.3", build: "400", ent: ent, at: t0.addingTimeInterval(9e5)), kind: .observed, to: &ledger)
        return ledger
    }

    @Test func reportHasNoPaths() {
        let ledger = pathLedger()
        let text = LedgerReport.make(ledger, verdict: LedgerChain.verify(ledger), now: t0)
        #expect(!text.lowercased().contains("/users"))
        #expect(!text.lowercased().contains("%2fusers"))
        #expect(!text.contains("file://"))
        #expect(!text.contains("/Volumes"))
        #expect(text.contains(PathScreen.omittedPath))
        #expect(text.contains("Chain intact (4 entries verified)"))
    }
    @Test func reportListsEntriesNewestFirstWithShortHashesAndAnomalies() {
        var ledger = threeEntryLedger()
        LedgerChain.append(obs(version: "1.2", build: "300", cdhash: String(repeating: "9", count: 40), at: t0.addingTimeInterval(9e5)), kind: .observed, to: &ledger)
        let text = LedgerReport.make(ledger, verdict: LedgerChain.verify(ledger), now: t0, sample: true)
        #expect(text.hasPrefix("NativeLedger report (Sample)"))
        let e4 = text.range(of: "Entry 4 observed")!.lowerBound, e1 = text.range(of: "Entry 1 observed")!.lowerBound
        #expect(e4 < e1)
        #expect(text.contains("hash \(ledger.entries[3].shortHash)"))
        #expect(ledger.entries[3].shortHash.count == 12)
        #expect(text.contains("Anomaly Silent rebuild."))
        #expect(text.contains("Open anomalies Silent rebuild"))
    }
    @Test func reportNamesTheBrokenEntry() {
        var ledger = threeEntryLedger()
        ledger.entries[1].observation.version = "7.0"
        let text = LedgerReport.make(ledger, verdict: LedgerChain.verify(ledger), now: t0)
        #expect(text.contains("Chain broken at entry 2. Entry 2 was changed after it was recorded."))
    }
}

private final class Script: BundleInspectionSource, @unchecked Sendable {
    var fingerprints: [Fingerprint?]
    var signingRead: SigningRead = .read(identifier: "com.example.editor", team: "TEAMAAAAAA", entitlements: [:])
    var identity = BinaryIdentity(cdhash: String(repeating: "a", count: 40), executableSHA256: String(repeating: "b", count: 64))
    init(_ fingerprints: [Fingerprint?]) { self.fingerprints = fingerprints }
    func fingerprint(_ bundle: URL) -> Fingerprint? { fingerprints.isEmpty ? nil : fingerprints.removeFirst() }
    func bundleInfo(_ bundle: URL) -> BundleInfo? { BundleInfo(bundleID: "com.example.editor", version: "1.0", build: "100") }
    func architecture(_ bundle: URL) -> Arch { .universal }
    func signing(_ bundle: URL) -> SigningRead { signingRead }
    func binary(_ bundle: URL) -> BinaryIdentity { identity }
}

struct InspectionTests {
    private let url = URL(fileURLWithPath: "/nonexistent/Fixture.app")

    @Test func completeInspectionProducesAnObservationWithBuildAndBinary() throws {
        let result = LedgerInspector(source: Script([Fingerprint("x"), Fingerprint("x")]), now: { t0 }).inspect(url)
        #expect(result.isComplete)
        let o = try #require(result.observation)
        #expect(o.build == "100" && o.version == "1.0")
        #expect(o.binary.cdhash?.count == 40)
        #expect(o.observedAt == t0)
    }
    @Test func changedFingerprintRefusesTheWholeResult() {
        let result = LedgerInspector(source: Script([Fingerprint("x"), Fingerprint("y")])).inspect(url)
        #expect(result == .failed(.changedDuringInspection))
        #expect(LedgerInspector(source: Script([])).inspect(url) == .failed(.bundleUnreadable))
    }
    @Test func signingAndExecutableFailuresArePartial() {
        let s = Script([Fingerprint("x"), Fingerprint("x")]); s.signingRead = .failed
        let a = LedgerInspector(source: s).inspect(url)
        #expect(a.failure == .signingUnreadable && a.observation?.signing == .unavailable && !a.isComplete)
        let u = Script([Fingerprint("x"), Fingerprint("x")]); u.identity.executableSHA256 = nil
        #expect(LedgerInspector(source: u).inspect(url).failure == .executableUnreadable)
    }
    @Test func chunkedExecutableHashMatchesOneShotHash() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("blob")
        let bytes = Data((0..<(3 * SystemInspectionSource.chunkSize + 12345)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try bytes.write(to: file)
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(SystemInspectionSource.sha256(of: file) == expected)
        #expect(SystemInspectionSource.sha256(of: file, chunkSize: 7) == expected)
        try Data().write(to: file)
        #expect(SystemInspectionSource.sha256(of: file) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SystemInspectionSource.sha256(of: dir.appendingPathComponent("missing")) == nil)
    }
    @Test func systemSourceReadsAFixtureBundle() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = dir.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.fixture", "CFBundleExecutable": "Fixture",
                                    "CFBundleShortVersionString": "3.1", "CFBundleVersion": "310"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let header = Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]) + Data(count: 24)
        try header.write(to: app.appendingPathComponent("Contents/MacOS/Fixture"))
        let source = SystemInspectionSource()
        #expect(source.bundleInfo(app) == BundleInfo(bundleID: "com.example.fixture", version: "3.1", build: "310"))
        #expect(source.architecture(app) == .appleSilicon)
        let binary = source.binary(app)
        #expect(binary.executableSHA256 == SHA256.hash(data: header).map { String(format: "%02x", $0) }.joined())
        #expect(binary.cdhash == nil)
        let result = LedgerInspector(source: source).inspect(app)
        #expect(result.observation?.bundleID == "com.example.fixture")
        #expect(result.observation?.signing == .unsigned)
    }
    @Test func cdhashOfSignedSystemCodeIsHex() throws {
        let hash = try #require(SystemInspectionSource.cdhash(of: URL(fileURLWithPath: "/usr/bin/true")))
        #expect(hash.count == 40)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }
    @Test func missingBookmarkIsAccessUnavailable() {
        #expect(BookmarkInspector().inspect(bookmark: nil, id: UUID()) == .failed(.accessUnavailable))
        #expect(BookmarkInspector().inspect(bookmark: Data([0, 1, 2]), id: UUID()) == .failed(.accessUnavailable))
    }
    @Test func sampleLedgersAreIntactAndShowEachAnomaly() {
        let ledgers = SampleLedger.ledgers(now: t0)
        #expect(ledgers.allSatisfy { LedgerChain.verify($0).isIntact })
        #expect(ledgers[0].openAnomalies == [.silentRebuild])
        #expect(ledgers[1].openAnomalies.isEmpty && ledgers[1].latest?.kind == .acknowledged)
        #expect(ledgers[2].openAnomalies == [.versionRegression, .teamChange, .newEntitlement, .architectureChange])
        let inspector = SampleLedger.Inspector(now: t0)
        #expect(inspector.inspect(bookmark: nil, id: SampleLedger.clockID) == .failed(.accessUnavailable))
        var editor = ledgers[0]
        let fresh = inspector.inspect(bookmark: nil, id: SampleLedger.editorID).observation!
        #expect(LedgerChain.append(fresh, kind: .observed, to: &editor) == nil)
    }
}

struct MachOArchitectureTests {
    private func word(_ value: UInt32, little: Bool) -> [UInt8] {
        let b = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
        return little ? b.reversed() : b
    }
    private func thin(_ cpu: UInt32, little: Bool = true, wide: Bool = true) -> Data {
        Data(word(wide ? 0xfeedfacf : 0xfeedface, little: little) + word(cpu, little: little) + Array(repeating: 0, count: wide ? 24 : 20))
    }
    private func fat(_ cpus: [UInt32], little: Bool = false, wide: Bool = false) -> Data {
        var bytes = word(wide ? 0xcafebabf : 0xcafebabe, little: little) + word(UInt32(cpus.count), little: little)
        for cpu in cpus { bytes += word(cpu, little: little) + Array(repeating: 0, count: wide ? 28 : 16) }
        return Data(bytes)
    }
    @Test func thinAndFatHeadersClassify() {
        for little in [true, false] {
            for wide in [true, false] {
                #expect(MachOArchitecture.classify(thin(CPUType.arm64, little: little, wide: wide)) == .appleSilicon)
                #expect(MachOArchitecture.classify(thin(CPUType.x86_64, little: little, wide: wide)) == .intelOnly)
                #expect(MachOArchitecture.classify(fat([CPUType.arm64, CPUType.x86_64], little: little, wide: wide)) == .universal)
            }
        }
        #expect(MachOArchitecture.classify(Data("#!/bin/sh\n".utf8)) == .script)
    }
    @Test func truncatedAndMalformedHeadersAreUnknown() {
        for count in 0..<32 { #expect(MachOArchitecture.classify(thin(CPUType.arm64).prefix(count)) == .unknown) }
        #expect(MachOArchitecture.classify(fat([])) == .unknown)
        #expect(MachOArchitecture.classify(Data([0xca, 0xfe, 0xba, 0xbe, 255, 255, 255, 255])) == .unknown)
        #expect(MachOArchitecture.classify(Data([0]) + thin(CPUType.arm64).dropFirst(0)) == .unknown)
        #expect(MachOArchitecture.classify((Data([0]) + thin(CPUType.arm64)).dropFirst()) == .appleSilicon)
    }
    @Test func architectureRawValuesNameSlicesNotVendors() throws {
        #expect(Arch.intelOnly.rawValue == "x86_64 only")
        #expect(Arch.allCases.allSatisfy { !$0.rawValue.contains("Intel") })
        let text = String(decoding: try LedgerCoding.encoder().encode(obs(arch: .intelOnly)), as: UTF8.self)
        #expect(text.contains(#""architecture":"x86_64 only""#))
        #expect(try LedgerCoding.decoder().decode(LedgerObservation.self, from: Data(text.utf8)).architecture == .intelOnly)
    }
}
