import Foundation
import Testing
@testable import LedgerCore

struct AnomalyTests {
    private let base = obs()
    private func detect(_ current: LedgerObservation) -> [Anomaly] { AnomalyDetector.anomalies(previous: base, current: current) }

    @Test func noPreviousEntryHasNoAnomalies() {
        #expect(AnomalyDetector.anomalies(previous: nil, current: obs(version: "0.1")).isEmpty)
    }
    @Test func identicalObservationHasNoAnomalies() { #expect(detect(obs(at: t0.addingTimeInterval(99))).isEmpty) }

    @Test func silentRebuildWhenCdhashChangesWithSameVersionAndBuild() {
        #expect(detect(obs(cdhash: String(repeating: "c", count: 40), sha: String(repeating: "d", count: 64))) == [.silentRebuild])
    }
    @Test func silentRebuildFromCdhashWhenExecutableHashIsUnknown() {
        #expect(detect(obs(cdhash: String(repeating: "c", count: 40), sha: nil)) == [.silentRebuild])
    }
    @Test func noSilentRebuildWhenOnlyTheSelectedSliceCdhashDiffers() {
        // One universal executable read on an Intel Mac and on an Apple silicon Mac gives two cdhashes and one SHA-256.
        #expect(detect(obs(cdhash: String(repeating: "c", count: 40))).isEmpty)
    }
    @Test func silentRebuildWhenOnlyExecutableHashChanges() {
        #expect(detect(obs(sha: String(repeating: "d", count: 64))) == [.silentRebuild])
    }
    @Test func noSilentRebuildWhenVersionOrBuildChanges() {
        #expect(detect(obs(version: "1.1", cdhash: String(repeating: "c", count: 40))).isEmpty)
        #expect(detect(obs(build: "101", sha: String(repeating: "d", count: 64))).isEmpty)
    }
    @Test func noSilentRebuildWhenHashesAreUnknown() {
        #expect(detect(obs(cdhash: nil, sha: nil)).isEmpty)
        #expect(AnomalyDetector.anomalies(previous: obs(cdhash: nil), current: obs(cdhash: String(repeating: "c", count: 40))).isEmpty)
    }

    @Test func versionRegressionWhenVersionIsLower() {
        #expect(AnomalyDetector.anomalies(previous: obs(version: "1.10"), current: obs(version: "1.9", build: "90")) == [.versionRegression])
    }
    @Test func noVersionRegressionForUpgradeOrEqualVersion() {
        #expect(AnomalyDetector.anomalies(previous: obs(version: "1.9"), current: obs(version: "1.10", build: "110")).isEmpty)
        #expect(AnomalyDetector.anomalies(previous: obs(version: "2.0.0"), current: obs(version: "2.0", build: "200")).isEmpty)
    }
    @Test func noVersionRegressionForNonNumericVersions() {
        #expect(AnomalyDetector.anomalies(previous: obs(version: "2.0 beta"), current: obs(version: "1.0", build: "1")).isEmpty)
        #expect(AnomalyDetector.anomalies(previous: obs(version: "2.0"), current: obs(version: "1.0b1", build: "1")).isEmpty)
    }

    @Test func teamChangeWhenSigningTeamDiffers() {
        #expect(detect(obs(team: "TEAMBBBBBB")) == [.teamChange])
        #expect(detect(obs(team: nil)) == [.teamChange])
    }
    @Test func noTeamChangeForSameTeamOrUnreadSigning() {
        #expect(detect(obs(team: "TEAMAAAAAA", at: t0.addingTimeInterval(5))).isEmpty)
        var unread = obs(); unread.signing = .unavailable
        #expect(detect(unread).isEmpty)
        #expect(AnomalyDetector.anomalies(previous: unread, current: obs(team: "TEAMBBBBBB")).isEmpty)
    }

    @Test func newEntitlementWhenAKeyIsAdded() {
        #expect(detect(obs(ent: ["com.apple.security.app-sandbox": "true", "com.apple.security.network.client": "true"])) == [.newEntitlement])
    }
    @Test func noNewEntitlementForRemovalOrValueChange() {
        #expect(detect(obs(ent: [:])).isEmpty)
        #expect(detect(obs(ent: ["com.apple.security.app-sandbox": "false"])).isEmpty)
    }

    @Test func architectureChangeWhenArchitectureDiffers() {
        #expect(detect(obs(arch: .intelOnly)) == [.architectureChange])
    }
    @Test func noArchitectureChangeWhenEitherSideIsUnknown() {
        #expect(detect(obs(arch: .unknown)).isEmpty)
        #expect(AnomalyDetector.anomalies(previous: obs(arch: .unknown), current: obs(arch: .appleSilicon)).isEmpty)
    }

    @Test func severalAnomaliesAreReportedInFixedOrder() {
        let current = obs(version: "0.9", arch: .intelOnly, team: "TEAMBBBBBB",
                          ent: ["com.apple.security.app-sandbox": "true", "com.apple.security.device.camera": "true"])
        #expect(detect(current) == [.versionRegression, .teamChange, .newEntitlement, .architectureChange])
    }

    @Test func appendedEntryStoresItsAnomalies() throws {
        var ledger = AppLedger(displayName: "A")
        LedgerChain.append(base, kind: .observed, to: &ledger)
        let entry = try #require(LedgerChain.append(obs(sha: String(repeating: "d", count: 64), at: t0.addingTimeInterval(60)), kind: .observed, to: &ledger))
        #expect(entry.anomalies == [.silentRebuild])
        #expect(entry.changes.map(\.field) == [.executableSHA256])
    }
}

struct VersionOrderTests {
    @Test func numericComponentsCompareAsNumbers() {
        #expect(VersionOrder.compare("1.10", "1.9") == .orderedDescending)
        #expect(VersionOrder.compare("1.9", "1.10") == .orderedAscending)
        #expect(VersionOrder.compare("10.0", "9.99") == .orderedDescending)
    }
    @Test func trailingZeroComponentsAreEqual() {
        #expect(VersionOrder.compare("2.0", "2.0.0") == .orderedSame)
        #expect(VersionOrder.compare("2", "2.0.0.0") == .orderedSame)
        #expect(VersionOrder.compare("1.01", "1.1") == .orderedSame)
        #expect(VersionOrder.sameVersion("2.0", "2.0.0"))
    }
    @Test func nonNumericVersionsHaveNoOrder() {
        for (a, b) in [("1.0b2", "1.0"), ("1.0", "beta"), ("", "1"), ("1..2", "1.2"), ("1.2.", "1.2"), ("１.0", "1.0")] {
            #expect(VersionOrder.compare(a, b) == nil)
        }
        #expect(!VersionOrder.sameVersion("1.0b2", "1.0"))
        #expect(VersionOrder.sameVersion("1.0b2", "1.0b2"))
    }
    @Test func longComponentsDoNotOverflow() {
        #expect(VersionOrder.compare("1.99999999999999999999999", "1.99999999999999999999998") == .orderedDescending)
        #expect(VersionOrder.compare("1.000000000000000000000001", "1.1") == .orderedSame)
    }
}
