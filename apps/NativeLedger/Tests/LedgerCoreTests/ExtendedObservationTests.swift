import Foundation
import Testing
@testable import LedgerCore

struct ExtendedAnomalyTests {
    private let base = extendedObs()
    private func detect(_ current: LedgerObservation, previous: LedgerObservation? = nil) -> [Anomaly] {
        AnomalyDetector.anomalies(previous: previous ?? base, current: current)
    }

    @Test func newBackgroundItemWhenAnItemIsAdded() {
        #expect(detect(extendedObs(background: ["com.example.editor.helper", "com.example.editor.launcher.plist"])) == [.newBackgroundItem])
        #expect(detect(extendedObs(background: ["com.example.editor.other"])) == [.newBackgroundItem])
    }
    @Test func noNewBackgroundItemForRemovalSameItemsOrOlderReadings() {
        #expect(detect(extendedObs(background: [])).isEmpty)
        #expect(detect(extendedObs(at: t0.addingTimeInterval(60))).isEmpty)
        let older = extendedObs(usage: [:], background: [], feed: nil, minimum: nil, slices: [], validity: .notChecked, extended: false)
        #expect(detect(extendedObs(), previous: older).isEmpty)
    }

    @Test func newPrivacyUsageWhenADescriptionKeyIsAdded() {
        let usage = ["NSCameraUsageDescription": "Scans pages.", "NSMicrophoneUsageDescription": "Records notes."]
        #expect(detect(extendedObs(usage: usage)) == [.newPrivacyUsage])
    }
    @Test func noNewPrivacyUsageForTextChangeRemovalOrOlderReadings() {
        #expect(detect(extendedObs(usage: ["NSCameraUsageDescription": "Scans receipts."])).isEmpty)
        #expect(detect(extendedObs(usage: [:])).isEmpty)
        let older = extendedObs(usage: [:], extended: false)
        #expect(detect(extendedObs(usage: ["NSContactsUsageDescription": "Finds people."]), previous: older).isEmpty)
    }

    @Test func signatureInvalidWhenValidationFails() {
        let broken = extendedObs(validity: .invalid(code: -67061))
        #expect(detect(broken) == [.signatureInvalid])
        #expect(AnomalyDetector.anomalies(previous: nil, current: broken) == [.signatureInvalid])
        let rebuilt = extendedObs(validity: .invalid(code: -67061), cdhash: String(repeating: "e", count: 40), sha: String(repeating: "e", count: 64))
        #expect(detect(rebuilt, previous: broken) == [.silentRebuild, .signatureInvalid])
    }
    @Test func noSignatureInvalidForValidUncheckedUnsignedOrRepeatedReadings() {
        #expect(detect(extendedObs(validity: .valid, at: t0.addingTimeInterval(5))).isEmpty)
        #expect(detect(extendedObs(validity: .notChecked)).isEmpty)
        #expect(detect(extendedObs(validity: .invalid(code: SignatureValidity.unsignedCode))).isEmpty)
        let broken = extendedObs(validity: .invalid(code: -67061))
        #expect(detect(extendedObs(validity: .invalid(code: -67061), at: t0.addingTimeInterval(9)), previous: broken).isEmpty)
        #expect(!SignatureValidity.invalid(code: SignatureValidity.unsignedCode).isFailure && SignatureValidity.invalid(code: -1).isFailure)
    }

    @Test func updateFeedChangedWhenTheFeedDiffersOrAppears() {
        #expect(detect(extendedObs(feed: "https://other.example.net/appcast.xml")) == [.updateFeedChanged])
        #expect(detect(extendedObs(), previous: extendedObs(feed: nil)) == [.updateFeedChanged])
    }
    @Test func noUpdateFeedChangedForSameFeedRemovalOrOlderReadings() {
        #expect(detect(extendedObs(at: t0.addingTimeInterval(3))).isEmpty)
        #expect(detect(extendedObs(feed: nil)).isEmpty)
        #expect(detect(extendedObs(), previous: extendedObs(feed: nil, extended: false)).isEmpty)
    }

    @Test func severityFollowsTheDisplayOrder() {
        #expect(Anomaly.displayOrder == [.signatureInvalid, .teamChange, .newBackgroundItem, .silentRebuild, .versionRegression,
                                         .newEntitlement, .newPrivacyUsage, .updateFeedChanged, .architectureChange])
        #expect(Set(Anomaly.displayOrder) == Set(Anomaly.allCases) && Anomaly.displayOrder.count == Anomaly.allCases.count)
        #expect(Anomaly.displayOrder.map(\.severity) == Array((1...9).reversed()))
        #expect(Anomaly.allCases.filter(\.isHighSeverity) == [.teamChange, .newBackgroundItem, .signatureInvalid])
        #expect(Anomaly.bySeverity([.architectureChange, .signatureInvalid, .silentRebuild, .signatureInvalid])
                == [.signatureInvalid, .silentRebuild, .architectureChange])
        #expect(Anomaly.allCases.allSatisfy { !$0.label.isEmpty && $0.explanation.hasSuffix(".") })
    }

    @Test func detectionOutputKeepsAllCasesOrderWithNewAnomalies() {
        let current = extendedObs(usage: ["NSCameraUsageDescription": "Scans pages.", "NSPhotoLibraryUsageDescription": "Saves pages."],
                                  background: ["com.example.editor.helper", "com.example.editor.daemon"],
                                  feed: "https://other.example.net/appcast.xml", validity: .invalid(code: -67030))
        #expect(detect(current) == [.newBackgroundItem, .newPrivacyUsage, .signatureInvalid, .updateFeedChanged])
    }
}

struct ExtendedCodingTests {
    // Written by the previous LedgerCore, before the extended fields existed.
    static let oldLedgerJSON = #"""
    {"displayName":"Old Editor","entries":[{"anomalies":[],"changes":[],"entryHash":"b36843380d9e0f840cea0e185de36f9383b508e5e54fa8efd71924d1ba8ef58e","kind":"observed","observation":{"architecture":"Universal","binary":{"cdhash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","executableSHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"build":"100","bundleID":"com.example.editor","observedAt":"2026-09-21T14:13:20.123Z","signing":{"read":{"entitlements":{"com.apple.security.app-sandbox":"true"},"identifier":"com.example.editor","team":"TEAMAAAAAA"}},"version":"1.0"},"previousHash":"0000000000000000000000000000000000000000000000000000000000000000","seq":1},{"anomalies":[],"changes":[{"after":"1.1","before":"1.0","field":{"version":{}}},{"after":"110","before":"100","field":{"build":{}}},{"after":"cccccccccccccccccccccccccccccccccccccccc","before":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","field":{"cdhash":{}}}],"entryHash":"406ac5e70dc8a5f84053da9c0c312f495aa22a5a37e2d7f292422e547c427122","kind":"observed","observation":{"architecture":"Universal","binary":{"cdhash":"cccccccccccccccccccccccccccccccccccccccc","executableSHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"build":"110","bundleID":"com.example.editor","observedAt":"2026-09-22T14:13:20.123Z","signing":{"read":{"entitlements":{"com.apple.security.app-sandbox":"true"},"identifier":"com.example.editor","team":"TEAMAAAAAA"}},"version":"1.1"},"previousHash":"b36843380d9e0f840cea0e185de36f9383b508e5e54fa8efd71924d1ba8ef58e","seq":2},{"anomalies":[],"changes":[],"entryHash":"80e4ef33539186949c1f97493a5b2f519f651cdd422a4b4c61e69ed099be9d7b","kind":"acknowledged","observation":{"architecture":"Universal","binary":{"cdhash":"cccccccccccccccccccccccccccccccccccccccc","executableSHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"build":"110","bundleID":"com.example.editor","observedAt":"2026-09-22T15:13:20.123Z","signing":{"read":{"entitlements":{"com.apple.security.app-sandbox":"true"},"identifier":"com.example.editor","team":"TEAMAAAAAA"}},"version":"1.1"},"previousHash":"406ac5e70dc8a5f84053da9c0c312f495aa22a5a37e2d7f292422e547c427122","seq":3}],"id":"0B5E0001-0000-4000-8000-000000000001"}
    """#

    @Test func oldLedgerWithoutNewFieldsDecodesAndStillVerifies() throws {
        let ledger = try LedgerCoding.decoder().decode(AppLedger.self, from: Data(Self.oldLedgerJSON.utf8))
        #expect(ledger.entries.count == 3 && LedgerChain.verify(ledger) == .intact(count: 3))
        #expect(ledger.source == .picked && ledger.appKey == nil && ledger.lastFingerprint == nil && !ledger.isRemoved)
        let o = ledger.entries[0].observation
        #expect(o.usageDescriptions.isEmpty && o.backgroundItems.isEmpty && o.updateFeedURL == nil)
        #expect(o.minimumSystemVersion == nil && o.architectureSlices.isEmpty && o.signatureValidity == .notChecked && !o.extendedFields)
        #expect(try LedgerCoding.encoder().encode(ledger.entries[1]).count > 0)
        let reencoded = String(decoding: try LedgerCoding.encoder().encode(ledger), as: UTF8.self)
        #expect(reencoded.contains(#""source":{"picked":{}}"#))
        let stripped = reencoded.replacingOccurrences(of: #","source":{"picked":{}}"#, with: "")
        #expect(stripped == Self.oldLedgerJSON.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func oldLedgerFileAndStoreDecodeAndKeepVerifying() throws {
        let file = #"{"exportedAt":"2026-10-01T00:00:00.000Z","format":"nativeledger.v1","ledgers":["# + Self.oldLedgerJSON + "]}"
        let decoded = try LedgerFile.decode(Data(file.utf8))
        #expect(decoded.ledgers.count == 1 && LedgerChain.verify(decoded.ledgers[0]).isIntact)
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data((#"{"schema":2,"ledgers":["# + Self.oldLedgerJSON + "]}").utf8).write(to: dir.appendingPathComponent(LedgerStore.fileName))
        guard case .loaded(let ledgers) = LedgerStore(directory: dir).load() else { Issue.record("store did not load"); return }
        #expect(ledgers.count == 1 && LedgerChain.verify(ledgers[0]).isIntact)
        var next = ledgers[0]
        let entry = try #require(LedgerChain.append(extendedObs(cdhash: String(repeating: "c", count: 40), at: t0.addingTimeInterval(9e5)).withVersion("1.1", build: "110"),
                                                   kind: .observed, to: &next))
        #expect(entry.anomalies.isEmpty && entry.changes.isEmpty)
        #expect(LedgerChain.verify(next).isIntact)
    }

    @Test func extendedObservationRoundTripsAndDefaultsAreOmitted() throws {
        let full = extendedObs(validity: .invalid(code: -67061), at: LedgerCoding.normalized(t0))
        let data = try LedgerCoding.encoder().encode(full)
        #expect(try LedgerCoding.decoder().decode(LedgerObservation.self, from: data) == full)
        let text = String(decoding: data, as: UTF8.self)
        for key in ["usageDescriptions", "backgroundItems", "updateFeedURL", "minimumSystemVersion", "architectureSlices",
                    "signatureValidity", "extendedFields"] { #expect(text.contains("\"\(key)\"")) }
        #expect(text.contains(#""signatureValidity":{"invalid":{"code":-67061}}"#))
        let plain = String(decoding: try LedgerCoding.encoder().encode(obs()), as: UTF8.self)
        #expect(plain.contains(#""extendedFields":true"#))
        for key in ["usageDescriptions", "backgroundItems", "updateFeedURL", "minimumSystemVersion", "architectureSlices", "signatureValidity"] {
            #expect(!plain.contains("\"\(key)\""))
        }
    }

    @Test func appLedgerSourceAndKeyRoundTripAndExportStripsLocalState() throws {
        let id = UUID()
        var ledger = AppLedger(displayName: "Tool", source: .folder(id), appKey: "k1-abc", lastFingerprint: Fingerprint("c1:xyz"))
        LedgerChain.append(extendedObs(), kind: .observed, to: &ledger)
        let back = try LedgerCoding.decoder().decode(AppLedger.self, from: try LedgerCoding.encoder().encode(ledger))
        #expect(back == ledger && back.source.folderID == id)
        let exported = String(decoding: try LedgerFile(ledgers: [ledger], exportedAt: t0).encoded(), as: UTF8.self)
        #expect(!exported.contains("k1-abc") && !exported.contains("c1:xyz") && !exported.contains("lastFingerprint"))
        let file = try LedgerFile.decode(Data(exported.utf8))
        #expect(file.ledgers[0].appKey == nil && file.ledgers[0].lastFingerprint == nil && LedgerChain.verify(file.ledgers[0]).isIntact)
    }

    @Test func hasSameContentCoversEveryNewField() {
        let a = extendedObs()
        var variants: [LedgerObservation] = []
        var v = a; v.usageDescriptions["NSCameraUsageDescription"] = "Other."; variants.append(v)
        v = a; v.backgroundItems = []; variants.append(v)
        v = a; v.updateFeedURL = nil; variants.append(v)
        v = a; v.minimumSystemVersion = "15.0"; variants.append(v)
        v = a; v.architectureSlices = ["arm64"]; variants.append(v)
        v = a; v.signatureValidity = .notChecked; variants.append(v)
        v = a; v.extendedFields = false; variants.append(v)
        #expect(variants.allSatisfy { !$0.hasSameContent(as: a) })
        var later = a; later.observedAt = t0.addingTimeInterval(99)
        #expect(later.hasSameContent(as: a))
    }

    @Test func changesRecordEachNewField() {
        let a = extendedObs()
        let b = extendedObs(usage: ["NSMicrophoneUsageDescription": "Records."], background: ["com.example.editor.launcher"],
                            feed: "https://other.example.net/feed.xml", minimum: "15.0", slices: ["arm64"], validity: .invalid(code: -67061))
        let fields = LedgerComparison.changes(a, b).map(\.field)
        #expect(fields == [.usageDescription("NSCameraUsageDescription"), .usageDescription("NSMicrophoneUsageDescription"),
                           .backgroundItem("com.example.editor.helper"), .backgroundItem("com.example.editor.launcher"),
                           .updateFeedURL, .minimumSystemVersion, .architectureSlices, .signatureValidity])
        let changes = LedgerComparison.changes(a, b)
        #expect(changes[2].kind == "Removed" && changes[3].kind == "Added")
        #expect(changes.last?.before == "Valid" && changes.last?.after == "Invalid (code -67061)")
        #expect(changes[6].before == "arm64, x86_64" && changes[6].after == "arm64")
        #expect(ChangeField.minimumSystemVersion.label == "Minimum macOS version" && ChangeField.backgroundItem("x").label == "Background item x")
        let older = extendedObs(usage: [:], background: [], feed: nil, minimum: nil, slices: [], validity: .notChecked, extended: false)
        #expect(LedgerComparison.changes(older, b).isEmpty)
    }
}

struct ExtendedTamperTests {
    private func tampered(_ change: (inout LedgerObservation) -> Void) -> ChainVerdict {
        var ledger = AppLedger(displayName: "Tamper")
        LedgerChain.append(extendedObs(), kind: .observed, to: &ledger)
        LedgerChain.append(extendedObs(cdhash: String(repeating: "c", count: 40), at: t0.addingTimeInterval(60)), kind: .observed, to: &ledger)
        LedgerChain.append(extendedObs(cdhash: String(repeating: "d", count: 40), at: t0.addingTimeInterval(120)), kind: .observed, to: &ledger)
        #expect(LedgerChain.verify(ledger) == .intact(count: 3))
        change(&ledger.entries[1].observation)
        return LedgerChain.verify(ledger)
    }

    @Test func tamperUsageDescriptionsBreaksAtThatEntry() {
        #expect(brokenSeq(tampered { $0.usageDescriptions["NSCameraUsageDescription"] = "Edited." }) == 2)
        #expect(brokenSeq(tampered { $0.usageDescriptions = [:] }) == 2)
    }
    @Test func tamperBackgroundItemsBreaksAtThatEntry() {
        #expect(brokenSeq(tampered { $0.backgroundItems = [] }) == 2)
        #expect(brokenSeq(tampered { $0.backgroundItems.append("com.example.extra") }) == 2)
    }
    @Test func tamperUpdateFeedBreaksAtThatEntry() {
        #expect(brokenSeq(tampered { $0.updateFeedURL = "https://evil.example.org/feed.xml" }) == 2)
        #expect(brokenSeq(tampered { $0.updateFeedURL = nil }) == 2)
    }
    @Test func tamperMinimumSystemVersionBreaksAtThatEntry() {
        #expect(brokenSeq(tampered { $0.minimumSystemVersion = "10.13" }) == 2)
    }
    @Test func tamperArchitectureSlicesBreaksAtThatEntry() {
        #expect(brokenSeq(tampered { $0.architectureSlices = ["x86_64"] }) == 2)
    }
    @Test func tamperSignatureValidityBreaksAtThatEntry() {
        #expect(brokenSeq(tampered { $0.signatureValidity = .notChecked }) == 2)
        #expect(brokenSeq(tampered { $0.signatureValidity = .invalid(code: -1) }) == 2)
    }
    @Test func tamperExtendedFlagBreaksAtThatEntry() {
        #expect(brokenSeq(tampered { $0.extendedFields = false }) == 2)
    }
    @Test func tamperRemovedKindBreaksAtThatEntry() {
        var ledger = threeEntryLedger()
        LedgerChain.markRemoved(&ledger, at: t0.addingTimeInterval(9e5))
        #expect(LedgerChain.verify(ledger) == .intact(count: 4))
        ledger.entries[3].kind = .observed
        #expect(brokenSeq(LedgerChain.verify(ledger)) == 4)
    }
}

struct ExtendedInspectionTests {
    @Test func signatureOfASystemAppIsValidWithBothSlices() throws {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        try #require(FileManager.default.fileExists(atPath: calculator.path))
        #expect(SystemInspectionSource.checkValidity(of: calculator) == .valid)
        #expect(MachOArchitecture.slicesOfAppBundle(at: calculator) == ["arm64", "x86_64"])
    }

    @Test func modifiedCopyOfASignedAppIsInvalid() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let copy = try adHocSignedBundle(in: dir)
        #expect(SystemInspectionSource.checkValidity(of: copy) == .valid)
        let exe = try #require(MachOArchitecture.executableURL(forBundle: copy))
        var bytes = try Data(contentsOf: exe)
        let header = Array(bytes.prefix(16))
        let firstSliceOffset = header.starts(with: [0xca, 0xfe, 0xba, 0xbe])
            ? Int(bytes[16]) << 24 | Int(bytes[17]) << 16 | Int(bytes[18]) << 8 | Int(bytes[19]) : 0
        let target = firstSliceOffset + 0x100
        try #require(target < bytes.count)
        bytes[target] ^= 0xff
        try bytes.write(to: exe)
        let result = SystemInspectionSource.checkValidity(of: copy)
        #expect(result != .valid && result != .notChecked && result.isFailure)
        #expect(AnomalyDetector.anomalies(previous: nil, current: extendedObs(validity: result)) == [.signatureInvalid])
    }

    @Test func unsignedFakeBundleIsNotValidAndNotAFailure() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = try makeApp(dir, "Plain.app", id: "com.example.plain", codeResources: false)
        let result = SystemInspectionSource.checkValidity(of: app)
        #expect(result == .invalid(code: SignatureValidity.unsignedCode))
        #expect(!result.isFailure && result.label == "Not signed")
        #expect(SystemInspectionSource.checkValidity(of: dir.appendingPathComponent("Missing.app")) != .valid)
    }

    @Test func checkThatOutlastsTheTimeoutIsNotChecked() throws {
        #expect(SystemInspectionSource.validityTimeout == 20)
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        #expect(SystemInspectionSource.checkValidity(of: calculator, timeout: 0) == .notChecked)
    }

    @Test func backgroundItemsAreReadFromNestedFolders() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = try makeApp(dir, "Host.app", id: "com.example.host")
        try makeApp(app, "Contents/Library/LoginItems/Helper.app", id: "com.example.host.login-helper")
        try makeApp(app, "Contents/XPCServices/Fetcher.xpc", id: "com.example.host.fetcher")
        let fm = FileManager.default
        for folder in ["Library/LaunchAgents", "Library/LaunchDaemons", "Library/LaunchServices", "Helpers"] {
            try fm.createDirectory(at: app.appendingPathComponent("Contents/\(folder)"), withIntermediateDirectories: true)
        }
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Library/LaunchAgents/com.example.host.launcher.plist"))
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Library/LaunchDaemons/com.example.host.daemon.plist"))
        try Data("tool".utf8).write(to: app.appendingPathComponent("Contents/Library/LaunchServices/com.example.host.privileged"))
        try Data("tool".utf8).write(to: app.appendingPathComponent("Contents/Helpers/convert"))
        try Data("x".utf8).write(to: app.appendingPathComponent("Contents/Helpers/.DS_Store"))
        try fm.createDirectory(at: app.appendingPathComponent("Contents/Helpers/Broken.app"), withIntermediateDirectories: true)
        #expect(SystemInspectionSource.backgroundItems(in: app) == [
            "Broken.app", "com.example.host.daemon.plist", "com.example.host.fetcher", "com.example.host.launcher.plist",
            "com.example.host.login-helper", "com.example.host.privileged", "convert"])
        #expect(SystemInspectionSource.backgroundItems(in: try makeApp(dir, "Bare.app", id: "com.example.bare")).isEmpty)
    }

    @Test func systemSourceRecordsInfoPlistDetailsAndInspectorStoresThem() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let extra: [String: Any] = ["NSCameraUsageDescription": "Scans pages.", "NSAppleEventsUsageDescription": "Controls Finder.",
                                    "NSLocationUsageDescription": "/Users/someone/where", "NSUsageNotADescription": "x",
                                    "SUFeedURL": "https://updates.example.com/appcast.xml", "LSMinimumSystemVersion": "13.5"]
        let app = try makeApp(dir, "Detail.app", id: "com.example.detail", exe: fatHeader([CPUType.arm64, CPUType.x86_64]), extra: extra)
        try makeApp(app, "Contents/Library/LoginItems/Helper.app", id: "com.example.detail.helper")
        let details = try #require(SystemInspectionSource().details(app))
        #expect(details.usageDescriptions.keys.sorted() == ["NSAppleEventsUsageDescription", "NSCameraUsageDescription", "NSLocationUsageDescription"])
        #expect(details.usageDescriptions["NSCameraUsageDescription"] == "Scans pages.")
        #expect(details.usageDescriptions["NSLocationUsageDescription"]?.hasPrefix("path value sha256 ") == true)
        #expect(details.updateFeedURL == "https://updates.example.com/appcast.xml" && details.minimumSystemVersion == "13.5")
        #expect(details.architectureSlices == ["arm64", "x86_64"] && details.backgroundItems == ["com.example.detail.helper"])
        let result = LedgerInspector(source: SystemInspectionSource(), now: { t0 }).inspect(app)
        let o = try #require(result.observation)
        #expect(o.extendedFields && o.usageDescriptions == details.usageDescriptions && o.backgroundItems == details.backgroundItems)
        #expect(o.signatureValidity == .invalid(code: SignatureValidity.unsignedCode))
        let text = String(decoding: try LedgerCoding.encoder().encode(o), as: UTF8.self)
        #expect(!text.contains("/Users"))
        #expect(SystemInspectionSource().details(dir.appendingPathComponent("Missing.app")) == nil)
    }

    @Test func sliceNamesComeFromThinAndFatHeaders() {
        #expect(MachOArchitecture.slices(thinArm64Header) == ["arm64"])
        #expect(MachOArchitecture.slices(fatHeader([CPUType.x86_64, CPUType.arm64, CPUType.arm64])) == ["arm64", "x86_64"])
        #expect(MachOArchitecture.slices(fatHeader([CPUType.x86, 0x0000000c])) == ["i386", "other"])
        #expect(MachOArchitecture.slices(Data("#!/bin/sh\n".utf8)).isEmpty)
        #expect(MachOArchitecture.slices(Data([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 9])).isEmpty)
        #expect(MachOArchitecture.classify(fatHeader([CPUType.x86, 0x0000000c])) == .intelOnly)
    }

    @Test func inspectorWithoutDetailsRecordsNoExtendedFields() throws {
        struct Minimal: BundleInspectionSource {
            func fingerprint(_ bundle: URL) -> Fingerprint? { Fingerprint("x") }
            func bundleInfo(_ bundle: URL) -> BundleInfo? { BundleInfo(bundleID: "com.example.min", version: "1", build: "1") }
            func architecture(_ bundle: URL) -> Arch { .appleSilicon }
            func signing(_ bundle: URL) -> SigningRead { .unsigned }
            func binary(_ bundle: URL) -> BinaryIdentity { BinaryIdentity(executableSHA256: String(repeating: "f", count: 64)) }
        }
        let o = try #require(LedgerInspector(source: Minimal()).inspect(URL(fileURLWithPath: "/nonexistent")).observation)
        #expect(!o.extendedFields && o.signatureValidity == .notChecked && o.backgroundItems.isEmpty)
    }

    @Test func reportShowsExtendedFieldsWithoutPaths() {
        var ledger = AppLedger(displayName: "Report")
        var first = extendedObs(); first.usageDescriptions["NSDesktopFolderUsageDescription"] = "Reads /Users/someone/Desktop"
        LedgerChain.append(first, kind: .observed, to: &ledger)
        LedgerChain.append(extendedObs(background: ["com.example.editor.helper", "com.example.new-launcher"], validity: .invalid(code: -67061),
                                       at: t0.addingTimeInterval(60)), kind: .observed, to: &ledger)
        let text = LedgerReport.make(ledger, verdict: LedgerChain.verify(ledger), now: t0)
        #expect(text.contains("Signature validity Invalid (code -67061)"))
        #expect(text.contains("Architecture slices arm64, x86_64") && text.contains("Minimum macOS version 14.0"))
        #expect(text.contains("Update feed https://updates.example.com/appcast.xml"))
        #expect(text.contains("Added Background item com.example.new-launcher"))
        #expect(text.contains("Anomaly New background item.") && text.contains("Anomaly Signature invalid."))
        #expect(!text.lowercased().contains("/users"))
    }

    @Test func sampleLedgersCarryExtendedFieldsWithoutNewAnomalies() {
        let ledgers = SampleLedger.ledgers(now: t0)
        #expect(ledgers.allSatisfy { $0.entries.allSatisfy { $0.observation.extendedFields && $0.observation.signatureValidity == .valid } })
        #expect(ledgers[1].latest?.observation.backgroundItems == ["com.example.notes.sync-helper"])
        #expect(ledgers.flatMap { $0.entries.flatMap(\.anomalies) }.allSatisfy { !$0.isHighSeverity || $0 == .teamChange })
    }
}

extension LedgerObservation {
    func withVersion(_ version: String, build: String) -> LedgerObservation {
        var o = self; o.version = version; o.build = build; return o
    }
}
