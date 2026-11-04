import AppKit
import Foundation
import Testing
import LedgerCore
@testable import NativeLedger

@MainActor @Suite struct LaunchCheckFileTests {
    @Test func reportHasContractKeys() throws {
        let report = LaunchCheckFile.dictionary(app: "NativeLedger", bundleID: "com.example.nativeledger", version: "1.0.0",
                                                results: [LaunchCheck(name: "a", passed: true, note: "1")])
        let json = try #require(try JSONSerialization.jsonObject(with: LaunchCheckFile.serialize(report)) as? [String: Any])
        #expect(Set(json.keys) == ["app", "bundleID", "version", "sandboxed", "home", "checks", "pass", "generatedAt"])
        #expect(json["pass"] as? Bool == true)
        #expect(json["sandboxed"] is Bool && json["home"] is String && json["app"] as? String == "NativeLedger")
        let checks = try #require(json["checks"] as? [[String: Any]])
        #expect(Set(checks[0].keys) == ["name", "pass", "detail"])
        #expect(checks[0]["name"] as? String == "a" && checks[0]["pass"] as? Bool == true && checks[0]["detail"] as? String == "1")
        #expect(ISO8601DateFormatter().date(from: json["generatedAt"] as? String ?? "") != nil)
    }

    @Test func passNeedsChecksAndEveryPass() {
        #expect(!LaunchCheckFile.allPassed([]))
        #expect(!LaunchCheckFile.allPassed([LaunchCheck(name: "x", passed: true, note: ""), LaunchCheck(name: "y", passed: false, note: "")]))
        #expect(LaunchCheckFile.dictionary(app: "A", bundleID: "b", version: "1", results: [])["pass"] as? Bool == false)
    }

    @Test func writeCreatesSmokeJSON() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try LaunchCheckFile.save(LaunchCheckFile.dictionary(app: "A", bundleID: "b", version: "1",
                                                                      results: [LaunchCheck(name: "x", passed: true, note: "")]), in: folder)
        #expect(url.lastPathComponent == "smoke.json")
        let decoded = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect((decoded["checks"] as? [[String: Any]])?.count == 1)
    }

    @Test func usersPrefixIsBuiltAtRunTime() {
        #expect(SelfTest.usersPrefix == "/" + "Users" + "/")
    }

    @Test func selfTestRunsMeaningfulChecks() {
        let checks = SelfTest.checks()
        #expect(checks.count >= 5)
        #expect(Set(checks.map(\.name)).count == checks.count)
        let byName = Dictionary(uniqueKeysWithValues: checks.map { ($0.name, $0) })
        // These do not depend on the sandbox or on a universal release build.
        for name in ["inspect-calculator-complete", "chain-append-verify", "export-roundtrip", "store-roundtrip", "container-bookmark-roundtrip",
                     "watch-folder-discovery"] {
            #expect(byName[name]?.passed == true, "\(name): \(byName[name]?.note ?? "missing")")
        }
        #expect(checks.allSatisfy { !$0.note.contains("/Users/") })
    }
}

@MainActor @Suite struct PresentationTests {
    @Test func badgeOrder() {
        var anomalous = AppLedger(displayName: "A")
        LedgerChain.append(observation(), kind: .observed, to: &anomalous)
        LedgerChain.append(observation(team: "TEAMBBBBBB", at: appT0.addingTimeInterval(9)), kind: .observed, to: &anomalous)
        let empty = AppLedger(displayName: "E")
        let model = LedgerModel(store: nil, seed: [anomalous, empty])
        #expect(model.badge(anomalous) == .anomaly)
        #expect(model.badge(empty) == .notInspected)
        #expect(LedgerModel.Badge.allCases.map(\.label) == ["Intact", "Anomaly", "Chain broken", "Not inspected", "Unavailable", "Removed"])
    }

    @Test func chipTextNamesHashesAndValues() {
        #expect(Change(field: .version, before: "1.0", after: "1.1").chipText == "Version 1.0 → 1.1")
        #expect(Change(field: .cdhash, before: "aa", after: "bb").chipText == "Code directory hash changed")
        #expect(Change(field: .entitlement("com.apple.security.network.client"), before: nil, after: "true").chipText == "Entitlement added network.client")
        #expect(Change(field: .team, before: "TEAMA", after: nil).chipText == "Signing team removed TEAMA")
    }

    @Test func screenshotCaptionsFollowStoreRules() {
        #expect(ScreenshotRenderer.shots.count == 5)
        #expect(Set(ScreenshotRenderer.shots.map(\.file)).count == 5)
        for shot in ScreenshotRenderer.shots {
            #expect(shot.label.hasPrefix("Sample"))
            for text in [shot.title, shot.subtitle] {
                #expect(!text.contains(":") && !text.contains(" - ") && !text.contains("—"))
                #expect(!text.lowercased().contains("intel"))
                #expect(!text.lowercased().split(separator: " ").contains("first"))
                #expect(!text.lowercased().split(separator: " ").contains("only"))
            }
        }
    }

    @Test func rendersFiveStoreScreenshots() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try ScreenshotRenderer.render(to: folder)
        for shot in ScreenshotRenderer.shots {
            let image = try #require(NSImage(contentsOf: folder.appendingPathComponent(shot.file)))
            let rep = try #require(image.representations.first)
            #expect(rep.pixelsWide == 2880 && rep.pixelsHigh == 1800)
            #expect(!rep.hasAlpha)
        }
    }

    @Test func linksUseNewResourceBundleName() {
        #expect(AppLinks.resourceBundleName == "NativeLedger_NativeLedger.bundle")
        let privacy = "https://barframe.com/apps/nativeledger/privacy/"
        #expect(AppLinks.webAddress(privacy, path: PolicyPage.privacy.sitePath)?.absoluteString == privacy)
        #expect(AppLinks.webAddress(privacy, path: "/elsewhere/") == nil)
        #expect(AppLinks.webAddress("http://barframe.com/apps/nativeledger/privacy/", path: PolicyPage.privacy.sitePath) == nil)
        #expect(AppLinks.webAddress("https://{DOMAIN}/apps/nativeledger/privacy/", path: PolicyPage.privacy.sitePath) == nil)
        #expect(PolicyPage.privacy.infoKey == "MASPrivacyPolicyURL" && PolicyPage.support.infoKey == "MASSupportURL")
        let info = ["MASPrivacyPolicyURL": privacy, "MASSupportURL": "https://barframe.com/apps/nativeledger/support/"]
        #expect(AppLinks.address(of: .privacy, info: info)?.absoluteString == privacy)
        #expect(AppLinks.address(of: .support, info: info)?.absoluteString == "https://barframe.com/apps/nativeledger/support/")
        // A missing or wrong key falls back to the bundled page, never to an unchecked address.
        let fallback = AppLinks.address(of: .support, info: ["MASSupportURL": "https://example.com/other/"])
        #expect(fallback == nil || fallback?.isFileURL == true)
    }

    @Test func headlinesUseMacNotMacs() {
        for shot in ScreenshotRenderer.shots {
            #expect(!shot.title.split(separator: " ").contains("Macs") && !shot.subtitle.contains("Macs"))
            #expect(shot.title.split(separator: " ").count <= 7)
        }
        #expect(ScreenshotRenderer.shots[3].title == "Compare ledgers from two Mac computers")
    }
}
