import Foundation
import Testing
import RevPulseCore

@MainActor
struct AppModelTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func sampleWhenNoKey() {
        let model = AppModel(defaults: makeDefaults(), keyStore: KeyStore(service: "test.revpulse.\(UUID().uuidString)"), start: false, loginStatus: false)
        #expect(model.sampleMode)
        #expect(model.snapshot?.today.netCents == 2295)
    }
    @Test func rejectsPublishableKey() {
        let model = AppModel(defaults: makeDefaults(), keyStore: KeyStore(service: "test.revpulse.\(UUID().uuidString)"), start: false, loginStatus: false)
        #expect(throws: Error.self) { try model.setKey("pk_live_abc") }
        #expect(model.sampleMode)
    }
    @Test func rejectsLiveSecretKey() {
        let model = AppModel(defaults: makeDefaults(), keyStore: KeyStore(service: "test.revpulse.\(UUID().uuidString)"), start: false, loginStatus: false)
        #expect(throws: Error.self) { try model.setKey("sk_live_abc") }
    }
    @Test func settingsRoundTrip() {
        let d = makeDefaults()
        let ks = KeyStore(service: "test.revpulse.\(UUID().uuidString)")
        let model = AppModel(defaults: d, keyStore: ks, start: false, loginStatus: false, loginAction: { _ in })
        model.goalCents = 25_000
        model.refreshInterval = 900
        model.setLaunchAtLogin(true)
        model.persistSettings()
        let model2 = AppModel(defaults: d, keyStore: ks, start: false, loginStatus: false, loginAction: { _ in })
        #expect(model2.goalCents == 25_000)
        #expect(model2.refreshInterval == 900)
        #expect(d.bool(forKey: AppModel.loginKey))
        #expect(!model2.launchAtLogin)
    }
    @Test func monthStartUnix() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23))!
        let start = AppModel.monthStartUnix(now: now)
        let start2 = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        #expect(start == Int(start2.timeIntervalSince1970))
    }
    @Test func removeKeyBackToSample() {
        let ks = KeyStore(service: "test.revpulse.\(UUID().uuidString)")
        let model = AppModel(defaults: makeDefaults(), keyStore: ks, start: false, loginStatus: false, loginAction: { _ in })
        try? model.setKey("rk_test_abc123456789")
        model.removeKey()
        #expect(model.sampleMode)
        #expect(!model.hasKey())
    }
}
