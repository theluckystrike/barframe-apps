import Foundation
import Darwin
import SwiftUI
import MASKit
import CostBarCore

@MainActor
enum Verification {
    nonisolated static func fixture(_ name: String) throws -> Data {
        // SwiftPM's generated accessor assumes a CLI layout. The signed app stores bundles in Contents/Resources.
        let bundleName = "CostBar_CostBarApp.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundleName)
        ].compactMap { $0 }
        guard let bundle = candidates.compactMap({ Bundle(url: $0) }).first,
              let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw SpendError.invalidResponse
        }
        return try Data(contentsOf: url)
    }
    static func smoke() async {
        var checks: [SmokeCheck] = []
        let vault = KeyStore(service: (Bundle.main.bundleIdentifier ?? "com.unfinalized.costbar") + ".smoke")
        let account = UUID().uuidString
        let token = "smoke-" + UUID().uuidString
        func check(_ name: String, _ block: () throws -> String) {
            do { checks.append(SmokeCheck(name: name, pass: true, detail: try block())) }
            catch { checks.append(SmokeCheck(name: name, pass: false, detail: error.localizedDescription)) }
        }
        check("Bundled privacy policy read") {
            let policy = try LocalPrivacyPolicy.load()
            guard policy.contains("Keys are stored only"), policy.count >= 300 else { throw SpendError.invalidResponse }
            return "Bundled local policy readable without a public domain; \(policy.count) characters"
        }
        check("Bundled Support read") {
            let support = try LocalSupport.load()
            guard support.contains("Fill sample key"), support.contains("Send Sample notification") else { throw SpendError.invalidResponse }
            return "Bundled Support readable without a configured public domain"
        }
        check("Keychain add and read") {
            try vault.save(token, account: account)
            guard try vault.read(account) == token else { throw SpendError.invalidResponse }
            return "SecItemAdd and SecItemCopyMatching succeeded; exact roundtrip"
        }
        check("Keychain update") {
            try vault.save(token + "-updated", account: account)
            guard try vault.read(account) == token + "-updated" else { throw SpendError.invalidResponse }
            return "SecItemUpdate succeeded; updated bytes match"
        }
        check("Keychain delete") {
            try vault.delete(account)
            guard try vault.read(account) == nil else { throw SpendError.invalidResponse }
            return "SecItemDelete succeeded; item no longer exists"
        }
        do {
            let result = try await ProviderClient(transport: SecureHTTPTransport(timeout: 10)).publicModelsCheck()
            checks.append(SmokeCheck(name: "Public HTTPS models", pass: result.status == 200 && result.modelCount > 0, detail: "HTTP \(result.status), \(result.modelCount) model IDs; no credential or inference call"))
        } catch { checks.append(SmokeCheck(name: "Public HTTPS models", pass: false, detail: error.localizedDescription)) }
        check("OpenRouter recorded fixture filesystem read") {
            let snapshot = try CostParser.openRouterKey(fixture("openrouter-key"), now: Date())
            let balance = try CostParser.openRouterCredits(fixture("openrouter-credits"))
            guard snapshot.monthlyUSD == Decimal(string: "25.5"), balance == Decimal(string: "74.75") else { throw SpendError.invalidResponse }
            return "Data(contentsOf:) read both bundled docs fixtures; key spend $25.50, credits $74.75"
        }
        check("Anthropic recorded fixture filesystem read") {
            let page = try CostParser.anthropic(fixture("anthropic"))
            guard page.buckets.count == 1, page.buckets[0].usd == Decimal(string: "1.2378912"), page.nextPage != nil else { throw SpendError.invalidResponse }
            return "Data(contentsOf:) read docs fixture; fractional cents normalized to $1.2378912"
        }
        check("OpenAI recorded fixture filesystem read") {
            let page = try CostParser.openAI(fixture("openai"))
            guard page.buckets.count == 1, page.buckets[0].usd == Decimal(string: "0.06"), page.nextPage == nil else { throw SpendError.invalidResponse }
            return "Data(contentsOf:) read docs fixture; $0.06, final page"
        }
        check("Projection from fixture filesystem read") {
            let now = try UTCClock.parse("2026-10-16T12:00:00Z")
            let snapshot = try CostParser.openRouterKey(fixture("openrouter-key"), now: now)
            guard snapshot.projectedUSD == 51, snapshot.hourlyUSD == Decimal(string: "2.125") else { throw SpendError.invalidResponse }
            return "Read fixture and extrapolated UTC month: $51.00; today's average $2.125/hour"
        }
        check("Sandbox denies real Desktop enumeration") {
            guard let record = getpwuid(getuid()), let path = record.pointee.pw_dir else { throw SpendError.invalidResponse }
            let desktop = URL(fileURLWithPath: String(cString: path)).appendingPathComponent("Desktop")
            do {
                _ = try FileManager.default.contentsOfDirectory(at: desktop, includingPropertiesForKeys: nil)
            } catch {
                let failure = error as NSError
                let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
                guard failure.code == NSFileReadNoPermissionError || (underlying?.code ?? -1) == Int(EACCES) || (underlying?.code ?? -1) == Int(EPERM) else { throw error }
                return "FileManager denied \(desktop.path), code \(failure.code), POSIX \(underlying?.code ?? -1)"
            }
            throw SpendError.invalidResponse
        }
        check("UI Sample mode bundled reports") {
            let model = AppModel()
            model.enterSample()
            guard model.sample, model.snapshots.count == Provider.allCases.count,
                  model.snapshots[.openRouter]?.remainingCredits == Decimal(string: "74.75") else { throw SpendError.invalidResponse }
            model.saveBudget("20", threshold: 80, provider: .openRouter)
            model.setAlerts(true)
            guard model.notificationMessage?.hasPrefix("Sample ·") == true,
                  model.preferences.deliveredAlertIDs.count == 1 else { throw SpendError.invalidResponse }
            model.saveBudget("10", threshold: 80, provider: .openRouter)
            guard model.preferences.deliveredAlertIDs.count == 1 else { throw SpendError.invalidResponse }
            return "Read real bundled files; all three provider screens and credits available; sample alert deduplicates after a budget edit"
        }
        do {
            let model = AppModel()
            model.enterSample()
            guard await model.saveKey(AppModel.sampleKey, provider: .openRouter),
                  await model.saveKey(AppModel.sampleKey, provider: .openRouter) else { throw SpendError.invalidResponse }
            model.refresh(.openRouter)
            guard model.snapshot?.remainingCredits != nil else { throw SpendError.invalidResponse }
            await model.removeKey(.openRouter)
            guard !model.connected.contains(.openRouter), model.snapshot == nil else { throw SpendError.invalidResponse }
            model.leaveSample()
            checks.append(SmokeCheck(name: "UI Sample connection Keychain lifecycle", pass: true, detail: "Supplied demo key added, read, updated, locally refreshed and deleted without a provider account or network"))
        } catch { checks.append(SmokeCheck(name: "UI Sample connection Keychain lifecycle", pass: false, detail: error.localizedDescription)) }
        let report = SmokeReport(app: "CostBar", bundleID: Bundle.main.bundleIdentifier ?? "com.unfinalized.costbar", version: "1.0.0", checks: checks)
        do { try report.write() }
        catch { fputs("Smoke report write failed: \(error.localizedDescription)\n", stderr); exit(1) }
        exit(report.pass ? 0 : 1)
    }
    static func screenshots() throws {
        let model = AppModel(sample: true)
        let now = try UTCClock.parse("2026-10-12T12:00:00Z")
        model.snapshots = try SampleData.load(now: now)
        let accent = Color(red: 1, green: 159.0 / 255, blue: 10.0 / 255)
        try CostBarScreenshotComposer.render(index: 1, headline: "Know what your APIs cost.", subheadline: "Sample data · daily spend, hourly pace and month-end forecast", accent: accent) {
            PopoverView(model: model)
        }
        model.preferences.budgets[Provider.openRouter.rawValue] = Budget(monthlyUSD: 30, thresholdPercent: 80)
        model.setAlerts(true)
        try CostBarScreenshotComposer.render(index: 2, headline: "See when budget thresholds are reached.", subheadline: "Sample data · provider budgets with a threshold alert preview", accent: accent) {
            PopoverView(model: model)
        }
        model.notificationMessage = nil
        model.setAlerts(false)
        model.notificationMessage = nil
        model.preferences.budgets[Provider.openRouter.rawValue] = Budget(monthlyUSD: 100, thresholdPercent: 80)
        model.focusCredits = true
        try CostBarScreenshotComposer.render(index: 3, headline: "Check your remaining account credits.", subheadline: "Sample data · OpenRouter account credits beside saved-key spend", accent: accent) {
            PopoverView(model: model)
        }

        // Use a fresh isolated store and a refusing credential implementation. These views contain
        // only the built-in synthetic workspace; they cannot read a saved key or fetch a report.
        let suiteName = "costbar.screenshots." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw SpendError.invalidResponse }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let accounts = AccountsModel(store: AccountStore(defaults: defaults),
                                     keys: AsyncKeyStore(store: ScreenshotCredentials()), clock: { now },
                                     fetch: { _, _, _ in throw SpendError.invalidResponse })
        accounts.enterSample()
        try CostBarScreenshotComposer.renderAccounts(index: 4, headline: "Match credit to the work you run.",
            subheadline: "Illustrative sample · $140 eligible for Agent SDK · expired grants stay separate", accent: accent) {
            AccountsView(model: accounts)
        }
        accounts.setWorkload(.claudeCode, for: AccountSample.activeID)
        try CostBarScreenshotComposer.renderAccounts(index: 5, headline: "Check what each grant can fund.",
            subheadline: "Illustrative sample · $0 for ordinary Claude Code · Max API promotions are excluded", accent: accent) {
            AccountsView(model: accounts)
        }
        accounts.select(AccountSample.unavailableID)
        try CostBarScreenshotComposer.renderAccounts(index: 6, headline: "Keep history when a key fails.",
            subheadline: "Illustrative sample · unavailable account · dated history retained and labelled", accent: accent) {
            AccountsView(model: accounts)
        }
    }
}

/// Screenshot mode must never access the owner's saved credentials.
private struct ScreenshotCredentials: CredentialStore {
    func read(_ account: String) throws -> String? { throw SpendError.invalidResponse }
    func save(_ value: String, account: String) throws { throw SpendError.invalidResponse }
    func delete(_ account: String) throws { throw SpendError.invalidResponse }
}
