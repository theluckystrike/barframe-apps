import Foundation
import AppKit
import ServiceManagement
import Testing
import Vision
import SwiftUI
@testable import QuotaPaceCore
@testable import QuotaPaceApp

private var appRoot: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
private func source(_ file: String) throws -> String {
    try String(contentsOf: appRoot.appendingPathComponent(file), encoding: .utf8)
}
private func json(_ file: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: appRoot.appendingPathComponent(file))) as? [String: Any])
}

@Test func Q01PrivacyLinksRemainReachableInAboutAndFooter() throws {
    #expect(try source("Sources/QuotaPaceApp/SettingsView.swift").contains("AppLinksView()"))
    #expect(try source("Sources/QuotaPaceApp/PopoverView.swift").contains("AppPolicyButton(page: .privacy)"))
}
@Test func Q02SubmissionLinksMatchConfiguredBrandRoutes() throws {
    let manifest = try json("mas.json"), listing = try json("store/listing.json")
    let base = "https://barframe.com/apps/quotapace/"
    for (key, listingKey, suffix) in [("privacy_url", "privacy_policy", "privacy/"), ("support_url", "support", "support/")] {
        #expect(manifest[key] as? String == base + suffix)
        #expect(listing[listingKey] as? String == base + suffix)
    }
    #expect(!(listing["review_notes"] as? String ?? "").contains("Tests/"))
}

@Test @MainActor func Q03SampleModeUsesBundledCurrentUsageAndRestoresLiveSettings() throws {
    let suite = "QuotaPace-sample-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = Preferences(defaults: defaults)
    preferences.selected = .codex
    preferences.setLimits(Limits(fiveHours: 123, sevenDays: 456), for: .claude)
    let model = AppModel(preferences: preferences)
    model.setSampleMode(true)
    #expect(model.sampleMode)
    #expect(model.errors.isEmpty)
    #expect(model.grants.isEmpty)
    #expect(model.summary(.fiveHours, provider: .claude).used == 8_000_000)
    #expect(model.summary(.sevenDays, provider: .claude).used == 33_000_000)
    #expect(model.summary(.fiveHours, provider: .codex).used == 12_500_000)
    for provider in Provider.allCases {
        #expect(model.limits[provider]?.fiveHours == 45_000_000)
        #expect(model.caches[provider]?.scannedAt == model.clock)
    }
    model.saveLimits(Limits(fiveHours: 15_000_000, sevenDays: 90_000_000), for: .codex)
    model.refresh()
    #expect(model.limits[.codex]?.fiveHours == 15_000_000)
    #expect(model.summary(.fiveHours, provider: .codex).secondsToLimit != nil)
    #expect(preferences.limits(for: .codex).fiveHours == 0)
    model.selected = .claude
    model.setSampleMode(false)
    #expect(!model.sampleMode)
    #expect(model.selected == .codex)
    #expect(model.limits[.claude]?.fiveHours == 123)
    #expect(model.caches.isEmpty)
}
@Test func Q04CachedIDsExcludePathsAndLegacyCacheIsRemoved() throws {
    let path = "/Users/private-person/projects/secret/session.jsonl"
    for provider in Provider.allCases {
        var parser = JSONLParser(provider: provider, sourceID: path)
        let fixture = appRoot.appendingPathComponent("Tests/QuotaPaceCoreTests/Fixtures/\(provider.rawValue).jsonl")
        for line in try Data(contentsOf: fixture).split(separator: 10) { parser.ingest(Data(line)) }
        #expect(!parser.samples.isEmpty)
        let cache = CachedUsage(samples: Array(parser.samples.values), scannedAt: Date(), files: 1)
        let encoded = String(decoding: try JSONEncoder().encode(cache), as: UTF8.self)
        #expect(!encoded.contains("private-person"))
        #expect(!encoded.contains("session.jsonl"))
        #expect(!encoded.contains("msg-a"))
        let suite = "QuotaPace-cache-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(path.utf8), forKey: "cache.\(provider.rawValue)")
        let preferences = Preferences(defaults: defaults)
        #expect(defaults.data(forKey: "cache.\(provider.rawValue)") == nil)
        preferences.setCache(cache, for: provider)
        #expect(preferences.cache(for: provider)?.samples == cache.samples)
        #expect(!String(decoding: try #require(defaults.data(forKey: "cache.v2.\(provider.rawValue)")), as: UTF8.self).contains(path))
    }
}
@Test func Q05SameSizeInPlaceRewriteReplacesTheCachedCount() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("session.jsonl")
    let row = "{\"timestamp\":\"2026-10-12T09:00:00Z\",\"message\":{\"id\":\"a\",\"usage\":{\"input_tokens\":100}}}\n"
    try Data(row.utf8).write(to: file)
    let scanner = LogScanner()
    #expect(try scanner.scan(folder: folder, provider: .claude).samples.first?.tokens == 100)
    let oldSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
    let handle = try FileHandle(forWritingTo: file)
    try handle.write(contentsOf: Data(row.replacingOccurrences(of: "100", with: "200").utf8)); try handle.close()
    #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == oldSize)
    #expect(try scanner.scan(folder: folder, provider: .claude).samples.first?.tokens == 200)
    #expect(try scanner.scan(folder: folder, provider: .claude).samples.count == 1)
}
@Test func Q06MixedInvalidFieldsRejectTheWholeRowWithoutAdvancingCodexBaseline() {
    for bad in ["-10", "true", "1.5", "null", "\"12\""] {
        var claude = JSONLParser(provider: .claude, sourceID: "bad")
        let row = "{\"timestamp\":\"2026-10-12T09:00:00Z\",\"message\":{\"usage\":{\"input_tokens\":100,\"output_tokens\":\(bad)}}}"
        claude.ingest(Data(row.utf8))
        #expect(claude.samples.isEmpty)
        #expect(claude.malformedLines == 1)
        #expect(claude.recognizedLines == 0)
        var codex = JSONLParser(provider: .codex, sourceID: "bad")
        let invalid = "{\"timestamp\":\"2026-10-12T09:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":100,\"output_tokens\":\(bad)}}}}"
        codex.ingest(Data(invalid.utf8))
        #expect(codex.samples.isEmpty)
        #expect(codex.malformedLines == 1)
        let valid = invalid.replacingOccurrences(of: "\"output_tokens\":\(bad)", with: "\"output_tokens\":10")
        codex.ingest(Data(valid.utf8))
        #expect(codex.samples.values.reduce(0) { $0 + $1.tokens } == 100)
    }
    var codex = JSONLParser(provider: .codex, sourceID: "last")
    let invalidLast = "{\"timestamp\":\"2026-10-12T09:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":100},\"last_token_usage\":{\"input_tokens\":100,\"output_tokens\":-10}}}}"
    codex.ingest(Data(invalidLast.utf8))
    #expect(codex.malformedLines == 1)
    #expect(codex.samples.isEmpty)
}
@Test @MainActor func Q07StoppingAndReleasingRefreshOwnerInvalidateRepeatingTimers() {
    var count = 0
    var owner: RefreshTimer? = RefreshTimer()
    owner?.start(interval: 0.001) { count += 1 }
    #expect(owner?.isRunning == true)
    owner?.stop()
    #expect(owner?.isRunning == false)
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    #expect(count == 0)
    owner?.start(interval: 0.001) { count += 1 }
    owner = nil
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    #expect(count == 0)
}
@Test @MainActor func Q07ModelStopCancelsRefreshSession() {
    let model = AppModel(sampleMode: true)
    model.start()
    #expect(model.refreshTimer.isRunning)
    model.stop()
    #expect(!model.refreshTimer.isRunning)
    #expect(!model.isRefreshing)
}
@Test func Q08PendingLoginRegistrationIsOnAndCanBeCancelled() {
    #expect(LoginState(.enabled).isRegistered)
    #expect(LoginState(.requiresApproval).isRegistered)
    #expect(LoginState(.requiresApproval).needsApproval)
    #expect(!LoginState(.notRegistered).isRegistered)
    #expect(!LoginState(.notFound).isRegistered)
}

@Test @MainActor func settingsScreenshotContainsActualEditableSampleBudgets() async throws {
    let model = AppModel(sampleMode: true)
    try model.loadSampleData()
    let snapshot = try await SettingsSnapshot.image(model: model)
    let image = try #require(snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(image.width == 960)
    #expect(image.height == 1060)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    #expect(text.contains("Sample"))
    #expect(text.contains("45000000"))
    #expect(text.contains("200000000"))
    #expect(text.contains("Save"))
}

@Test func Q01ProvisionalPrivacyAndSupportPagesAreReadableWithoutHosting() throws {
    let privacy = try #require(AppLinks.privacyPolicy())
    let support = try #require(AppLinks.support())
    #expect(privacy.isFileURL)
    #expect(support.isFileURL)
    #expect(try String(contentsOf: privacy, encoding: .utf8).contains("privacy policy"))
    #expect(try String(contentsOf: privacy, encoding: .utf8).contains("Conversation text is not retained"))
    #expect(try String(contentsOf: support, encoding: .utf8).contains("Try Sample mode"))
}

@Test func A6PlaceholderAndInvalidDestinationsFallBackButFinalHTTPSIsPreserved() throws {
    let fallback = try #require(AppLinks.policyURL(nil, path: AppLinks.privacyPath, resource: "privacy"))
    #expect(fallback.isFileURL)
    for raw in ["https://{DOMAIN}/token-pace-meter/privacy/", "http://example.org/token-pace-meter/privacy/",
                "https://example.org/incorrect/", "https://person:secret@example.org/token-pace-meter/privacy/"] {
        #expect(AppLinks.policyURL(URL(string: raw), path: AppLinks.privacyPath, resource: "privacy") == fallback)
    }
    for (resource, path) in [("privacy", AppLinks.privacyPath), ("support", AppLinks.supportPath)] {
        let final = try #require(URL(string: "https://example.org" + path))
        #expect(AppLinks.policyURL(final, path: path, resource: resource) == final)
    }
}

@Test func A6BundledPagesAreCompleteAndContainNoProvisionalUIStrings() throws {
    for page in PolicyPage.allCases {
        let text = try page.text()
        #expect(text.count > 500)
        #expect(!text.contains("{DOMAIN}"))
        #expect(!text.contains("{BRAND}"))
        #expect(text.contains("Michael Lip"))
        #expect(text.contains("Disconnect"))
    }
    #expect(try PolicyPage.privacy.text().contains("Conversation text is not retained"))
    #expect(try PolicyPage.support.text().contains("Try Sample mode"))
}

@Test func A6CopyrightMatchesSellerAndSmokeCountMatchesActualChecks() throws {
    for file in ["mas.json", "store/listing.json"] {
        #expect(try json(file)["copyright"] as? String == (file == "store/listing.json" ? "2026 Michael Lip" : "© 2026 Michael Lip"))
    }
    #expect(try source("Sources/QuotaPaceApp/SettingsView.swift").contains("© 2026 Michael Lip"))
    let count = try source("Sources/QuotaPaceApp/SmokeRunner.swift").components(separatedBy: "        check(\"").count - 1
    #expect(count == 7)
    #expect(try source("README.md").contains("runs seven real checks"))
}

@Test @MainActor func A6LocalButtonsOpenReadableNativePolicyWindows() throws {
    for page in PolicyPage.allCases {
        PolicyWindow.open(page)
        let window = try #require(NSApp.windows.first { $0.title == "QuotaPace \(page.title)" })
        #expect(window.isVisible)
        #expect(window.contentView is NSHostingView<LocalPolicyView>)
        window.close()
    }
}

@Test @MainActor func A6NativePolicyButtonsExposeDistinctAccessibleTitlesAndActions() async throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: AppLinksView())
    host.frame = NSRect(x: 0, y: 0, width: 480, height: 100)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    try await Task.sleep(nanoseconds: 100_000_000)
    host.layoutSubtreeIfNeeded()
    func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
    }
    let controls = buttons(host)
    #expect(controls.count == 2)
    #expect(Set(controls.compactMap { $0.accessibilityTitle() }) == Set(["Privacy Policy", "Support"]))
    #expect(Set(controls.compactMap { $0.accessibilityLabel() }) == Set(["Privacy Policy", "Support"]))
    for control in controls {
        #expect(control.isEnabled)
        #expect(control.target != nil)
        #expect(control.action != nil)
        #expect(control.accessibilityHelp()?.contains("bundled") == true)
    }
}
