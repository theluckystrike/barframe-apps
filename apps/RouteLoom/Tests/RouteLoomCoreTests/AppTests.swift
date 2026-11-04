import AppKit
import SwiftUI
import Foundation
import Testing
import RouteLoomCore
@testable import RouteLoom

@MainActor
@Suite(.serialized)
struct AppTests {
    func model() -> AppModel { AppModel(defaults:UserDefaults(suiteName:UUID().uuidString)!,storage:nil,observeSystem:false) }
    @Test func firstLaunchNeverChecks() { let m = model();#expect(!m.running && !m.sample && m.sessions.isEmpty && m.referenceURL.isEmpty && m.workURL.isEmpty) }
    @Test func sampleNeverCallsNetwork() async {
        let m = model();var calls = 0
        m.probe = { _,_,_ in calls += 1;return Fixtures.session().checks[0] }
        m.toggleSample(true);m.start();await Task.yield()
        #expect(calls == 0 && m.sample && !m.running && m.selected?.sample == true)
    }
    @Test func sampleCannotPolluteLiveHistory() { let m = model();m.toggleSample(true);m.scenario = .tls;m.resetSample();#expect(m.live.isEmpty);m.toggleSample(false);#expect(m.sessions.isEmpty && !m.running) }
    @Test func stoppedIconAlwaysIdle() { let m = model();m.toggleSample(true);#expect(m.menuSymbol == "network" && m.menuLabel.contains("Stopped")) }
    @Test func healthyFailureAndStaleMenuStates() {
        let m = model();var s = Fixtures.session();s.sample = false;s.ended = nil;m.live = [s];m.running = true;m.now = s.checks.last!.at
        #expect(m.menuSymbol == "checkmark.circle")
        let t = m.now.addingTimeInterval(30);s.append(PairCheck(at:t,reference:Fixtures.observation(t),work:Fixtures.observation(t,.tls)));m.live = [s];m.now = t
        #expect(m.menuSymbol == "exclamationmark.triangle")
        m.now = t.addingTimeInterval(999);#expect(m.menuSymbol == "questionmark.circle")
        m.stop();#expect(m.menuSymbol == "network")
    }
    @Test func liveLoopChecksPairAndStopPreventsFurtherWrites() async {
        let m = model();m.pairName = "Pair";m.referenceURL = "https://reference.example";m.workURL = "https://work.example"
        m.probe = { _,_,_ in let t = Date();return PairCheck(at:t,reference:Fixtures.observation(t),work:Fixtures.observation(t,.timeout)) }
        m.start();for _ in 0..<10 { await Task.yield() }
        #expect(m.running && m.live.first?.checks.count == 1)
        m.stop();let count = m.live.first?.checks.count;await Task.yield();#expect(m.live.first?.checks.count == count && m.live.first?.ended != nil)
    }
    @Test func cancelledProbeResultIsDiscarded() async {
        let m = model();m.pairName = "Pair";m.referenceURL = "https://r.example";m.workURL = "https://w.example"
        m.probe = { _,_,_ in try? await Task.sleep(for:.seconds(1));return Fixtures.session().checks[0] }
        m.start();await Task.yield();m.toggleSample(true);for _ in 0..<10 { await Task.yield() }
        #expect(m.live.first?.checks.isEmpty == true && !m.running && m.samples.count == 2)
    }
    @Test func requestIsHeadWithoutCookies() throws {
        let r = Probe.request(try Endpoint.validate("https://work.example/check"),timeout:8)
        #expect(r.httpMethod == "HEAD" && !r.httpShouldHandleCookies && r.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(r.value(forHTTPHeaderField:"Cache-Control") == "no-cache, no-store")
    }
    @Test func ephemeralConfigurationHasNoStores() {
        let c = Probe.configuration(timeout:8);#expect(c.urlCache == nil && c.httpCookieStorage == nil && c.urlCredentialStorage == nil && !c.httpShouldSetCookies && c.timeoutIntervalForResource == 8)
    }
    @Test func spanishStringsRenderInMainAndSettings() {
        _ = NSApplication.shared;let m = model();m.spanish = true;m.toggleSample(true)
        let panel = NSHostingView(rootView:ContentView(model:m));let settings = NSHostingView(rootView:SettingsView(model:m))
        #expect(panel.fittingSize.width == 820 && settings.fittingSize.width == 600)
        #expect(m.tr("Work only failure") == "Fallo solo en trabajo")
    }
    @Test func clearLocalDataRemovesEndpointsAndLiveHistory() {
        let m = model();m.referenceURL = "https://r.example";m.workURL = "https://w.example";m.pairName = "Pair";m.live = [Fixtures.earlier];m.toggleSample(true);m.clearData()
        #expect(m.live.isEmpty && m.referenceURL.isEmpty && m.workURL.isEmpty && m.pairName.isEmpty && m.samples.count == 2)
    }
    @Test func startupClosesUnfinishedSessionWithUnknownGap() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("build/test-history-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        var s = Fixtures.earlier;s.sample = false;s.ended = nil;try JSONEncoder().encode([s]).write(to:url)
        defer { try? FileManager.default.removeItem(at:url) }
        let m = AppModel(defaults:UserDefaults(suiteName:UUID().uuidString)!,storage:url,observeSystem:false)
        #expect(!m.running && m.live[0].ended != nil && m.live[0].gaps.last?.reason.contains("shutdown") == true)
    }
    @Test func retentionPrunesWhenNewSessionStarts() {
        let m = model();m.retention = 5;m.pairName = "Pair";m.referenceURL = "https://r.example";m.workURL = "https://w.example"
        for _ in 0..<6 { m.start();m.stop() }
        #expect(m.live.count == 5)
    }
    @Test func invalidPairDoesNotStart() { let m = model();m.pairName = "Pair";m.referenceURL = "https://user:secret@r.example";m.workURL = "https://w.example";m.start();#expect(!m.running && m.live.isEmpty && m.error != nil) }
    @Test func provisionalAndMissingPolicyURLsUseLocalDocuments() {
        #expect(AppDocument.webURL("https://{DOMAIN}/apps/routeloom/privacy/") == nil)
        #expect(AppDocument.webURL(nil) == nil)
        #expect(AppDocument.webURL("") == nil)
        #expect(AppDocument.webURL("http://example.com/privacy/") == nil)
        #expect(AppDocument.webURL("https://user:password@example.com/privacy/") == nil)
        #expect(AppDocument.webURL("https://example.com:8080/privacy/") == nil)
        for doc in [AppDocument.privacy, .support] {
            #expect(!doc.text.isEmpty && !doc.text.contains("{DOMAIN}") && !doc.text.contains("{BRAND}"))
        }
    }
    @Test func finalizedPolicyURLsRemainReadyToOpen() {
        #expect(AppDocument.webURL("https://barframe.com/apps/routeloom/privacy/")?.absoluteString == "https://barframe.com/apps/routeloom/privacy/")
        #expect(AppDocument.webURL("https://example.com/apps/routeloom/support/")?.host == "example.com")
    }
    @Test func bundledPrivacyExplainsRetentionDeletionAndStopping() {
        let text = AppDocument.privacy.text
        #expect(text.contains("5, 20 or 50") && text.contains("default is 20"))
        #expect(text.contains("1000 checks") && text.contains("Clear local data") && text.contains("Stop session"))
        #expect(text.contains("Older sessions are removed") && text.contains("clipboard"))
    }
    @Test func spanishReportLocalizesPreviewAndClipboard() {
        let m = model();m.toggleSample(true);m.spanish = true
        let report = m.reportText
        #expect(report.contains("Informe de soporte de RouteLoom") && report.contains("Host de referencia"))
        #expect(report.contains("Fallo solo en trabajo") && report.contains("tiempo de espera agotado"))
        #expect(report.contains("respuesta recibida") && report.contains("Intervalo desconocido"))
        #expect(report.contains("Reposo · tiempo desconocido") && report.contains("Recuperado"))
        #expect(!report.contains("Unknown gap") && !report.contains("Work only failure"))
        m.copyReport()
        #expect(m.copied && NSPasteboard.general.string(forType:.string) == report)
        m.spanish = false
        #expect(m.reportText.contains("RouteLoom support report") && m.reportText.contains("Unknown gap"))
    }

}
