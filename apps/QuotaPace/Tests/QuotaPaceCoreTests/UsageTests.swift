import Foundation
import Testing
@testable import QuotaPaceCore

private let now = JSONLParser.date("2026-10-12T10:00:00Z")!
private func fixture(_ name: String) throws -> URL { try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")) }
private func parse(_ provider: Provider) throws -> JSONLParser {
    var parser = JSONLParser(provider: provider, sourceID: "fixture")
    for line in try Data(contentsOf: fixture(provider.rawValue)).split(separator: 10) { parser.ingest(Data(line)) }
    return parser
}
private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaPace-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
@Test func claudeDeduplicatesStreamingMessagesAndIncludesCache() throws {
    let parsed = try parse(.claude)
    #expect(parsed.samples.count == 3)
    #expect(parsed.samples["claude:\(JSONLParser.opaqueID("msg-a"))"]?.tokens == 2200)
    #expect(parsed.samples.values.reduce(0) { $0 + $1.tokens } == 13200)
}
@Test func codexCountsCumulativeDeltasWithoutDoubleCountingCachedInput() throws {
    let parsed = try parse(.codex)
    #expect(parsed.recognizedLines == 4)
    #expect(parsed.samples.count == 3)
    #expect(parsed.samples.values.reduce(0) { $0 + $1.tokens } == 5000)
}
@Test func rollingWindowsExcludeOldUsageAndFutureRecords() throws {
    var samples = Array(try parse(.claude).samples.values)
    samples.append(TokenSample(id: "future", date: now.addingTimeInterval(1), tokens: 4000))
    samples.append(TokenSample(id: "boundary", date: now.addingTimeInterval(-5 * 3600), tokens: 999))
    #expect(WindowSummary.calculate(samples: samples, window: .fiveHours, limit: 10000, now: now).used == 3200)
    #expect(WindowSummary.calculate(samples: Array(try parse(.claude).samples.values), window: .sevenDays, limit: 20000, now: now).used == 13200)
}
@Test func computesPaceAndTimeToLimit() throws {
    let summary = WindowSummary.calculate(samples: Array(try parse(.claude).samples.values), window: .fiveHours, limit: 5000, now: now)
    #expect(summary.tokensPerHour == 1600)
    #expect(summary.projected == 8000)
    #expect(summary.secondsToLimit == 4050)
    #expect(summary.fraction == 0.64)
}
@Test func rollingForecastAccountsForExpiringEvents() {
    let samples = [TokenSample(id: "a", date: now.addingTimeInterval(-4 * 3600), tokens: 4000)]
    let summary = WindowSummary.calculate(samples: samples, window: .fiveHours, limit: 6000, now: now)
    #expect(summary.tokensPerHour == 1000)
    #expect(summary.secondsToLimit == nil)
}
@Test func emptyAndUnconfiguredLimitsHaveNoForecast() {
    let empty = WindowSummary.calculate(samples: [], window: .fiveHours, limit: 1000, now: now)
    #expect(empty.used == 0)
    #expect(empty.secondsToLimit == nil)
    let recent = WindowSummary.calculate(samples: [TokenSample(id: "a", date: now, tokens: 5)], window: .fiveHours, limit: 0, now: now)
    #expect(recent.fraction == nil)
    #expect(recent.tokensPerHour == 0)
}
@Test func reachedLimitForecastIsImmediate() {
    let summary = WindowSummary.calculate(samples: [TokenSample(id: "a", date: now.addingTimeInterval(-100), tokens: 100)], window: .fiveHours, limit: 100, now: now)
    #expect(summary.isOverLimit)
    #expect(summary.secondsToLimit == 0)
}
@Test func malformedNegativeAndBooleanCountsAreRejected() throws {
    var parser = JSONLParser(provider: .claude, sourceID: "bad")
    for line in try Data(contentsOf: fixture("malformed")).split(separator: 10) { parser.ingest(Data(line)) }
    #expect(parser.malformedLines == 2)
    #expect(parser.samples.isEmpty)
}
@Test func scannerHandlesPartialAppendTruncationAndRemoval() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("session.jsonl")
    let data = try Data(contentsOf: fixture("claude"))
    let scanner = LogScanner()
    try data.dropLast(10).write(to: file)
    let first = try scanner.scan(folder: folder, provider: .claude)
    #expect(first.samples.count == 2)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd(); try handle.write(contentsOf: data.suffix(10)); try handle.close()
    #expect(try scanner.scan(folder: folder, provider: .claude).samples.count == 3)
    #expect(try scanner.scan(folder: folder, provider: .claude).samples.count == 3)
    try Data().write(to: file)
    #expect(try scanner.scan(folder: folder, provider: .claude).samples.isEmpty)
    try FileManager.default.removeItem(at: file)
    #expect(try scanner.scan(folder: folder, provider: .claude).files == 0)
}
@Test func scannerDoesNotFollowSymlinksOrDuplicateClaudeMessages() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.copyItem(at: fixture("claude"), to: folder.appendingPathComponent("a.jsonl"))
    try FileManager.default.copyItem(at: fixture("claude"), to: folder.appendingPathComponent("b.jsonl"))
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.jsonl"), withDestinationURL: fixture("claude"))
    let result = try LogScanner().scan(folder: folder, provider: .claude)
    #expect(result.files == 2)
    #expect(result.samples.count == 3)
}
@Test func codexCounterResetUsesLastTurn() throws {
    var parser = try parse(.codex)
    let row = "{\"timestamp\":\"2026-10-12T09:40:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":200},\"last_token_usage\":{\"total_tokens\":50}}}}"
    parser.ingest(Data(row.utf8))
    #expect(parser.samples.values.reduce(0) { $0 + $1.tokens } == 5050)
}
@Test func preferencesPersistLimitsAndRemoveCache() throws {
    let suite = "QuotaPace-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.limits(for: .claude).fiveHours == 0)
    preferences.setLimits(Limits(fiveHours: 100, sevenDays: 900), for: .codex)
    #expect(Preferences(defaults: defaults).limits(for: .codex).sevenDays == 900)
    preferences.setCache(CachedUsage(samples: [], scannedAt: now, files: 3), for: .codex)
    #expect(preferences.cache(for: .codex)?.files == 3)
    preferences.setCache(nil, for: .codex)
    #expect(preferences.cache(for: .codex) == nil)
}
@Test func scannerIncludesValidFinalLineWithoutNewlineOnce() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.jsonl")
    let data = try Data(contentsOf: fixture("codex"))
    try data.dropLast().write(to: file)
    let scanner = LogScanner()
    #expect(try scanner.scan(folder: folder, provider: .codex).samples.reduce(0) { $0 + $1.tokens } == 5000)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
    #expect(try scanner.scan(folder: folder, provider: .codex).samples.reduce(0) { $0 + $1.tokens } == 5000)
}
@Test func limitEntryValidatesUserBudgets() throws {
    #expect(try Limits.entered(fiveHours: " 10000 ", sevenDays: "").fiveHours == 10000)
    #expect(try Limits.entered(fiveHours: "0", sevenDays: "1000000000000").sevenDays == 1_000_000_000_000)
    #expect(throws: LimitEntryError.self) { _ = try Limits.entered(fiveHours: "-1", sevenDays: "20") }
    #expect(throws: LimitEntryError.self) { _ = try Limits.entered(fiveHours: "1.5", sevenDays: "20") }
    #expect(throws: LimitEntryError.self) { _ = try Limits.entered(fiveHours: "1", sevenDays: "1000000000001") }
}
@Test func bookmarkRoundTripAndScanServiceReadRealFiles() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.copyItem(at: fixture("claude"), to: folder.appendingPathComponent("a.jsonl"))
    let grant = try FolderGrant(url: folder)
    let resolved = try grant.resolve()
    #expect(try Data(contentsOf: resolved.url.appendingPathComponent("a.jsonl")) == Data(contentsOf: fixture("claude")))
    let (result, _) = try await ScanService().scan(grant: grant, provider: .claude, now: now)
    #expect(result.samples.count == 3)
    #expect(result.samples.reduce(0) { $0 + $1.tokens } == 13200)
}
@Test func oversizedLinesAreSkippedWithoutDroppingTheNextRecord() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.jsonl")
    var data = Data(repeating: 32, count: 4 * 1024 * 1024 + 1)
    data.append(10)
    data.append(try Data(contentsOf: fixture("claude")))
    try data.write(to: file)
    let result = try LogScanner().scan(folder: folder, provider: .claude)
    #expect(result.malformedLines == 1)
    #expect(result.samples.count == 3)
}
@Test func incrementalRetentionDropsExpiredUsageAndKeepsCodexBaseline() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.jsonl")
    try FileManager.default.copyItem(at: fixture("codex"), to: file)
    let scanner = LogScanner()
    let first = try scanner.scan(folder: folder, provider: .codex, minimumDate: now.addingTimeInterval(-3600))
    #expect(first.samples.reduce(0) { $0 + $1.tokens } == 500)
    let row = "{\"timestamp\":\"2026-10-12T10:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":5500}}}}\n"
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd(); try handle.write(contentsOf: Data(row.utf8)); try handle.close()
    let next = try scanner.scan(folder: folder, provider: .codex, minimumDate: now.addingTimeInterval(-100))
    #expect(next.samples.count == 1)
    #expect(next.samples.first?.tokens == 500)
}
