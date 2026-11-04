import Foundation
import Testing
@testable import AgentPing
@testable import AgentPingCore
struct MergedTests {
    @Test @MainActor func configuredLinksUseBundleValues() {
        let info = ["MASPrivacyPolicyURL": "https://example.invalid/relaynook/privacy/", "MASSupportURL": "https://example.invalid/relaynook/support/"]
        #expect(AppLinks.configuredURL("MASPrivacyPolicyURL", fallback: "https://invalid.invalid", info: info)?.absoluteString == info["MASPrivacyPolicyURL"])
        #expect(AppLinks.configuredURL("MASSupportURL", fallback: "https://invalid.invalid", info: info)?.absoluteString == info["MASSupportURL"])
    }
    @Test @MainActor func configuredLinksRejectNonHTTPS() {
        #expect(AppLinks.configuredURL("MASPrivacyPolicyURL", fallback: "https://example.invalid/relaynook/privacy/", info: ["MASPrivacyPolicyURL": "http://insecure.invalid"]) == nil)
    }
    @Test func sampleHistoryIsIsolatedAndFictional() {
        var first = SampleContent.history
        first.clear()
        #expect(SampleContent.history.events.count == 10)
        #expect(SampleContent.history.events.allSatisfy { $0.agent.hasPrefix("Sample Agent") && $0.project == "Sample Project" && $0.session.hasPrefix("sample-") })
    }
    @Test func sampleHistoryHasTenRows() {
        #expect(SampleContent.history.events.count == 10)
        #expect(SampleContent.history.waitingCount == 3)
        #expect(Set(SampleContent.history.events.map(\.kind)).count == 4)
    }
    @Test func hookParserUsesDataOnlySystemTools() {
        #expect(Snippets.urlCommand(payload: "{}", mode: "done", token: SampleContent.token).hasPrefix("/usr/bin/perl -MJSON::PP -MEncode -e "))
        #expect(Snippets.hookScript.contains("/usr/bin/perl -MJSON::PP -MEncode"))
        #expect(Snippets.genericFunction().contains("/usr/bin/perl -MEncode"))
    }
    @Test func screenshotHeadlinesMeetBrief() {
        #expect(SampleContent.headlines.count == 3)
        for headline in SampleContent.headlines { #expect((4...7).contains(headline.split(separator: " ").count)) }
    }
}

struct AuditRegressionTests {
    @Test @MainActor func unresolvedLinksUseLocalDocuments() {
        for raw in ["https://{DOMAIN}/relaynook/privacy/", "https://", "", "http://example.com", "file:///tmp/test"] {
            #expect(AppLinks.configuredURL("link", fallback: "https://{DOMAIN}/", info: ["link": raw]) == nil)
        }
        #expect(AppLinks.configuredURL("link", fallback: "https://{DOMAIN}/", info: [:]) == nil)
        #expect(AppLinks.localPrivacy.contains("200 events"))
        #expect(AppLinks.localSupport.contains("No account"))
        #expect(!AppLinks.localPrivacy.contains("{DOMAIN}"))
    }
    @Test @MainActor func sampleRestoresLiveHistoryWithoutSaving() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(token: SampleContent.token, historyURL: path)
        model.setSampleMode(true)
        #expect(model.history.events.count == 10)
        model.clear(); model.sendTest()
        await model.flushHistory()
        #expect(!FileManager.default.fileExists(atPath: path.path))
        model.setSampleMode(false)
        #expect(model.history.events.isEmpty)
        #expect(!model.isSample)
    }
}
