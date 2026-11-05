import Foundation
import Testing
@testable import EnvTrellisCore
@testable import EnvTrellis

@Test func emptyDocument() { #expect(DotenvParser.parse("").keys.isEmpty) }
@Test func commentsIgnored() { #expect(DotenvParser.parse("# note\n  # second").issues.isEmpty) }
@Test func presenceWithoutValue() { #expect(DotenvParser.parse("TOKEN=invented").keys["TOKEN"]?.presence == .present) }
@Test func emptyValue() { #expect(DotenvParser.parse("TOKEN= ").keys["TOKEN"]?.presence == .empty) }
@Test func exportPrefix() { #expect(DotenvParser.parse("export TOKEN=x").keys["TOKEN"] != nil) }
@Test func exportTabPrefix() { #expect(DotenvParser.parse("export\tTOKEN=x").keys["TOKEN"] != nil) }
@Test func quotedComment() { #expect(DotenvParser.parse("TOKEN=\"#inside\"").keys["TOKEN"]?.presence == .present) }
@Test func emptySingleQuote() { #expect(DotenvParser.parse("TOKEN='' # note").keys["TOKEN"]?.presence == .empty) }
@Test func quotedWhitespaceIsPresent() { #expect(DotenvParser.parse("TOKEN=' '").keys["TOKEN"]?.presence == .present) }
@Test func inlineComment() { #expect(DotenvParser.parse("TOKEN= # absent").keys["TOKEN"]?.presence == .empty) }
@Test func duplicatesShowLines() {
    let result = DotenvParser.parse("TOKEN=a\n# comment\nTOKEN=b")
    #expect(result.keys["TOKEN"]?.lines == [1, 3]); #expect(result.issues == [ParseIssue(3, "Duplicate key TOKEN")])
}
@Test func windowsLines() { #expect(DotenvParser.parse("A=one\r\nA=two\r\n").keys["A"]?.lines == [1, 2]) }
@Test func utf8BOM() { #expect(DotenvParser.parse("\u{feff}A=x").keys["A"] != nil) }
@Test func invalidKeyDoesNotEchoValue() {
    let result = DotenvParser.parse("bad-secret-key=fixture_secret")
    #expect(result.keys.isEmpty); #expect(result.issues == [ParseIssue(1, "Invalid key syntax")])
}
@Test func missingEqualIsUnsupported() { #expect(DotenvParser.parse("fixture_secret").issues == [ParseIssue(1, "Unsupported syntax")]) }
@Test func multilineUnsupported() { #expect(!DotenvParser.parse("TOKEN=\"multi\nline\"").issues.isEmpty) }
@Test func expansionUnsupported() { #expect(!DotenvParser.parse("TOKEN=${OTHER}").issues.isEmpty) }
@Test func backticksUnsupported() { #expect(!DotenvParser.parse("TOKEN=`command`").issues.isEmpty) }
@Test func trailingContinuationUnsupported() { #expect(!DotenvParser.parse("TOKEN=value\\").issues.isEmpty) }
@Test func escapedQuoteSupported() { #expect(DotenvParser.parse("TOKEN=\"a\\\"b\"").issues.isEmpty) }
@Test func quotedTailUnsupported() { #expect(!DotenvParser.parse("TOKEN=\"a\"tail").issues.isEmpty) }
@Test func safeKeyNames() { #expect(DotenvParser.validKey("_A2")); #expect(!DotenvParser.validKey("2A")); #expect(!DotenvParser.validKey("A B")) }

func configured(_ text: String, rules: [String: Rule]) -> Project {
    var project = Project(label: "Test")
    var template = InputFile(label: "Template"); template.parsed = DotenvParser.parse("A=\n")
    project.template = template
    var environment = InputFile(label: "Environment"); environment.parsed = DotenvParser.parse(text)
    project.environments = [environment]; project.rules = [environment.id: rules]; project.lastScan = Date()
    return project
}
@Test func requiredAbsentFails() { let p = configured("", rules: ["A": .required]); #expect(p.outcome(key: "A", environment: p.environments[0]) == "Missing required"); #expect(p.readiness == .findings) }
@Test func requiredEmptyFails() { let p = configured("A=", rules: ["A": .required]); #expect(p.outcome(key: "A", environment: p.environments[0]) == "Empty required") }
@Test func requiredPresentPasses() { #expect(configured("A=x", rules: ["A": .required]).readiness == .ready) }
@Test func optionalAbsentPasses() { #expect(configured("", rules: ["A": .optional]).readiness == .ready) }
@Test func forbiddenPresentFails() { let p = configured("A=", rules: ["A": .forbidden]); #expect(p.outcome(key: "A", environment: p.environments[0]) == "Forbidden present") }
@Test func forbiddenAbsentPasses() { #expect(configured("", rules: ["A": .forbidden]).readiness == .ready) }
@Test func undecidedBlocksReady() { #expect(configured("A=x", rules: [:]).readiness == .findings) }
@Test func unsupportedBlocksReady() { #expect(configured("A=${VALUE}", rules: ["A": .optional]).readiness == .findings) }
@Test func duplicateBlocksReady() { #expect(configured("A=x\nA=y", rules: ["A": .optional]).readiness == .findings) }
@Test func templateSyntaxBlocksReady() { var p = configured("A=x", rules: ["A": .required]); p.template?.parsed = DotenvParser.parse("A=\"multiline"); #expect(p.readiness == .findings) }
@Test func unavailableNeverReady() { var p = configured("A=x", rules: ["A": .required]); p.environments[0].unavailable = true; #expect(p.readiness == .unknown) }
@Test func missingTemplateNeverReady() { var p = configured("A=x", rules: ["A": .required]); p.template = nil; #expect(p.readiness == .noInputs) }
@Test func staleNeverReady() { var p = configured("A=x", rules: ["A": .required]); p.stale = true; #expect(p.readiness == .stale) }
@Test func newTemplateKeyNeedsDecision() {
    var p = configured("A=x", rules: ["A": .required]); p.template?.parsed = DotenvParser.parse("A=\nB=")
    #expect(p.rules[p.environments[0].id]?["A"] == .required); #expect(p.keys == ["A", "B"]); #expect(p.readiness == .findings)
}
@Test func reportsContainNoSecrets() {
    let p = configured("A=fixture_secret_937\nHIDDEN='second_secret'", rules: ["A": .required, "HIDDEN": .optional])
    let report = p.report(sample: true)
    #expect(report.hasPrefix("Sample")); #expect(!report.contains("fixture_secret_937")); #expect(!report.contains("second_secret")); #expect(report.contains("Present"))
}
@Test func persistenceContainsNoValues() throws {
    let p = configured("A=fixture_secret_937", rules: ["A": .required])
    let data = try SavedState(projects: [p], pinned: p.id).encoded()
    #expect(!String(decoding: data, as: UTF8.self).contains("fixture_secret_937"))
    let restored = try SavedState.decode(data); #expect(restored.projects[0].readiness == .ready); #expect(restored.pinned == p.id)
}
@Test func corruptStateThrows() { #expect(throws: (any Error).self) { try SavedState.decode(Data("garbage".utf8)) } }
@Test func sampleHasRequiredFindings() { let report = SampleFixtures.project().report(sample: true); #expect(report.contains("Missing required")); #expect(report.contains("Forbidden present")); #expect(report.contains("Duplicate key MODE")) }
@Test func ruleChangeAffectsOnlyOneEnvironment() {
    var p = SampleFixtures.project(); let env = p.environments.first(where: { $0.label == "Staging" })!
    p.rules[env.id]?["DATABASE_URL"] = .optional
    #expect(p.outcome(key: "DATABASE_URL", environment: env) == "Pass")
    #expect(p.rules[p.environments.first(where: { $0.label == "Production" })!.id]?["DEBUG"] == .forbidden)
}
@Test func maskedReportOmitsLabels() { var p = configured("A=x", rules: ["A": .required]); p.label = "Sensitive Project"; p.environments[0].label = "Private Production"; let report = p.report(sample: false, maskLabels: true); #expect(!report.contains("Sensitive Project")); #expect(!report.contains("Private Production")) }
@Test @MainActor func liveSampleIsolationAndProjectRemoval() throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(stateURL: directory.appendingPathComponent("state.json"))
    model.addProject(); let liveID = model.project!.id
    model.toggleSample(true); #expect(model.project!.id != liveID)
    model.toggleSample(false); #expect(model.project!.id == liveID)
    model.removeProject(); #expect(model.live.projects.isEmpty)
    let restored = AppModel(stateURL: model.stateURL); #expect(restored.live.projects.isEmpty)
}
@Test @MainActor func corruptStateShowsRecovery() throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.json"); try Data("invalid".utf8).write(to: url)
    let model = AppModel(stateURL: url); #expect(!model.notice.isEmpty); #expect(model.state == .noInputs)
}
@Test func unavailableReportExplainsRecovery() { var p = configured("A=x", rules: ["A": .required]); p.environments[0].unavailable = true; #expect(p.report(sample: false).contains("Unknown choose again")) }

@Test @MainActor func cancellationInvalidatesPriorSuccess() {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(stateURL: directory.appendingPathComponent("state.json"))
    let project = configured("A=x", rules: ["A": .required])
    model.live = SavedState(projects: [project], pinned: project.id)
    #expect(model.state == .ready)
    model.selectionCancelled()
    #expect(model.state == .stale); #expect(model.badge != "✓"); #expect(!model.notice.isEmpty)
}
