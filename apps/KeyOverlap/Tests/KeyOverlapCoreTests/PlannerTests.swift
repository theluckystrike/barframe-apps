import Foundation
import Testing
@testable import KeyOverlapCore

func row(_ scope: String? = "Editor", _ context: String? = nil, key: String = "k", mods: [String] = ["command"], name: String = "Action") throws -> ShortcutRecord {
    try ShortcutRecord(command: name, key: key, modifiers: mods, scope: scope, context: context)
}
func pair(_ first: String?, _ second: String?, _ ac: String? = nil, _ bc: String? = nil, contexts: [ExclusiveContexts] = []) throws -> Overlap? {
    OverlapEngine.compare(try row(first, ac), try row(second, bc), contexts: contexts)
}

@Test func modifierOrderAndCaseNormalize() throws {
    let a = try Chord(key: " K ", modifiers: ["COMMAND", "shift", "option", "control"])
    #expect(a.key == "k")
    #expect(a.modifiers == ["control","option","shift","command"])
}
@Test func chordEqualityIgnoresOrder() throws { #expect(try Chord(key: "k", modifiers: ["shift","command"]) == Chord(key: "K", modifiers: ["command","shift"])) }
@Test func aliasesNormalize() throws { #expect(try Chord(key: "enter", modifiers: []) == Chord(key: "return", modifiers: [])); #expect(try Chord(key: "esc", modifiers: []).key == "escape") }
@Test func duplicateModifiersRejected() { #expect(throws: PlanError.self) { try Chord(key: "k", modifiers: ["command","COMMAND"]) } }
@Test func unknownModifierRejected() { #expect(throws: PlanError.self) { try Chord(key: "k", modifiers: ["meta"]) } }
@Test func multikeyStringRejected() { #expect(throws: PlanError.self) { try Chord(key: "k then j", modifiers: ["command"]) } }
@Test func blankKeyRejected() { #expect(throws: PlanError.self) { try Chord(key: " ", modifiers: []) } }
@Test func functionKeyBounds() { #expect(throws: Never.self) { try Chord(key: "F20", modifiers: []) }; #expect(throws: PlanError.self) { try Chord(key: "f21", modifiers: []) } }
@Test func blankCommandRejected() { #expect(throws: PlanError.self) { try row(name: " \n ") } }
@Test func commandAndScopesTrim() throws { let r = try row(" Editor ", " Edit ", name: " Open "); #expect(r.command == "Open"); #expect(r.scope == "Editor"); #expect(r.context == "Edit") }
@Test func globalContextRejected() { #expect(throws: PlanError.self) { try row("*", "Edit") } }
@Test func unknownContextRejected() { #expect(throws: PlanError.self) { try row(nil, "Edit") } }
@Test func globalOverlapsEveryApp() throws { #expect(try pair("*", "Editor")?.kind == .definite); #expect(try pair("Canvas", "*")?.kind == .definite) }
@Test func globalWithUnknownStillOverlaps() throws { #expect(try pair("*", nil)?.kind == .definite) }
@Test func differentAppsAreSeparate() throws { #expect(try pair("Editor", "Canvas")?.kind == .separate) }
@Test func sameAppCaseInsensitive() throws { #expect(try pair("EDITOR", "Editor")?.kind == .definite) }
@Test func missingScopeIsPossible() throws { #expect(try pair(nil, "Editor")?.kind == .possible); #expect(try pair(nil, nil)?.kind == .possible) }
@Test func blankScopeIsUnknown() throws { #expect(try row("  ").scope == nil) }
@Test func contextNamesAloneDoNotSeparate() throws { #expect(try pair("Editor", "Editor", "Edit", "Debug")?.kind == .definite) }
@Test func declaredExclusiveContextsSeparate() throws {
    let rule = try ExclusiveContexts(app: "Editor", first: "Edit", second: "Debug")
    let result = try pair("Editor", "editor", "EDIT", "debug", contexts: [rule])
    #expect(result?.kind == .separate); #expect(result?.exclusive == true)
}
@Test func exclusiveRuleWorksInBothDirections() throws {
    let rule = try ExclusiveContexts(app: "Editor", first: "Edit", second: "Debug")
    #expect(try pair("Editor", "Editor", "Debug", "Edit", contexts: [rule])?.kind == .separate)
}
@Test func exclusiveRuleDoesNotApplyToOtherApp() throws {
    let rule = try ExclusiveContexts(app: "Editor", first: "Edit", second: "Debug")
    #expect(try pair("Canvas", "Canvas", "Edit", "Debug", contexts: [rule])?.kind == .definite)
}
@Test func exclusiveRuleDoesNotSeparateUnspecifiedContext() throws {
    let rule = try ExclusiveContexts(app: "Editor", first: "Edit", second: "Debug")
    #expect(try pair("Editor", "Editor", "Edit", nil, contexts: [rule])?.kind == .definite)
}
@Test func exclusiveRulesAreNotTransitivelyInferred() throws {
    let rules = [try ExclusiveContexts(app: "Editor", first: "Edit", second: "Debug"), try ExclusiveContexts(app: "Editor", first: "Debug", second: "Preview")]
    #expect(try pair("Editor", "Editor", "Edit", "Preview", contexts: rules)?.kind == .definite)
}
@Test func invalidExclusivePairRejected() { #expect(throws: PlanError.self) { try ExclusiveContexts(app: "*", first: "Edit", second: "Debug") }; #expect(throws: PlanError.self) { try ExclusiveContexts(app: "Editor", first: "Edit", second: "edit") } }
@Test func differentChordHasNoComparison() throws { #expect(OverlapEngine.compare(try row(key: "k"), try row(key: "j")) == nil) }
@Test func overlapPairsDoNotRepeatOrCompareSelf() throws { #expect(OverlapEngine.overlaps([try row(), try row(), try row()]).count == 3) }
@Test func documentedTemplateImports() throws { let rows = try PlanImport.decode(Data(PlanImport.template.utf8)); #expect(rows.count == 2); #expect(rows[1].scope == "*") }
@Test func strictSchemaRejectsUnknownFields() { #expect(throws: PlanError.self) { try PlanImport.decode(Data("[{\"command\":\"Open\",\"key\":\"k\",\"modifiers\":[],\"scope\":null,\"context\":null,\"extra\":1}]".utf8)) } }
@Test func strictSchemaRejectsMissingFields() { #expect(throws: PlanError.self) { try PlanImport.decode(Data("[{\"command\":\"Open\",\"key\":\"k\",\"modifiers\":[],\"scope\":null}]".utf8)) } }
@Test func strictSchemaRejectsWrongTypes() { #expect(throws: PlanError.self) { try PlanImport.decode(Data("[{\"command\":7,\"key\":\"k\",\"modifiers\":[],\"scope\":null,\"context\":null}]".utf8)) } }
@Test func nonArrayRootRejected() { #expect(throws: PlanError.self) { try PlanImport.decode(Data("{}".utf8)) } }
@Test func invalidJSONRejected() { #expect(throws: PlanError.self) { try PlanImport.decode(Data("[{".utf8)) } }
@Test func failureReportsZeroBasedRowAndIsAtomic() throws {
    let baseline = ShortcutPlan.sample(); let snapshot = baseline
    let rows = try JSONSerialization.jsonObject(with: Data(PlanImport.template.utf8)) as! [[String: Any]]
    var invalid = rows[0]; invalid["key"] = "nonsense"
    let data = try JSONSerialization.data(withJSONObject: [rows[0], invalid])
    do { _ = try PlanImport.importing(data, into: baseline); Issue.record("Invalid import succeeded") }
    catch { #expect(error.localizedDescription.contains("Row index 1")) }
    #expect(baseline == snapshot)
}
@Test func validImportClearsStagingRetainsAssumptions() throws {
    let baseline = ShortcutPlan.sample(); let imported = try PlanImport.importing(Data(PlanImport.template.utf8), into: baseline)
    #expect(imported.records.count == 2); #expect(imported.replacements.isEmpty); #expect(imported.contexts == baseline.contexts)
}
@Test func candidateCheckDoesNotMutateBaseline() throws {
    let baseline = ShortcutPlan.sample(); let snapshot = baseline
    let result = OverlapEngine.candidate(try row("Orbit Editor", key: "5", mods: ["command","shift"]), in: baseline.records, contexts: baseline.contexts)
    #expect(result.filter { $0.kind == .definite }.count == 2); #expect(baseline == snapshot)
}
@Test func clearCandidateOnlyMeansClearInPlan() throws { #expect(OverlapEngine.candidate(try row(key: "z"), in: ShortcutPlan.sample().records).isEmpty) }
@Test func replacementsPreserveBaseline() throws {
    let plan = ShortcutPlan.sample(); #expect(plan.records[0].chord.key == "5"); #expect(plan.proposedRecords[0].chord.key == "6")
    #expect(OverlapEngine.overlaps(plan.proposedRecords, contexts: plan.contexts).filter { $0.kind == .definite }.isEmpty)
}
@Test func applyingPlanPreservesIdentityAndClearsProposals() {
    var plan = ShortcutPlan.sample(); let id = plan.records[0].id; let count = plan.records.count
    plan.apply(); #expect(plan.records[0].id == id); #expect(plan.records[0].chord.key == "6"); #expect(plan.replacements.isEmpty); #expect(plan.records.count == count)
}
@Test func stageReplacesPriorProposal() throws {
    var plan = ShortcutPlan.sample(); try plan.stage(id: plan.records[0].id, chord: Chord(key: "7", modifiers: ["command"]))
    #expect(plan.replacements.count == 1); #expect(plan.proposedRecords[0].chord.key == "7")
}
@Test func stagingOriginalChordRemovesProposal() throws { var plan = ShortcutPlan.sample(); try plan.stage(id: plan.records[0].id, chord: plan.records[0].chord); #expect(plan.replacements.isEmpty) }
@Test func stagingMissingRecordRejected() { var plan = ShortcutPlan(); #expect(throws: PlanError.self) { try plan.stage(id: UUID(), chord: Chord(key: "k", modifiers: [])) } }
@Test func deletingRecordRemovesItsProposal() { var plan = ShortcutPlan.sample(); plan.remove(id: plan.records[0].id); #expect(plan.records.count == 7); #expect(plan.replacements.isEmpty) }
@Test func searchFindsCommandAppAndChord() {
    let plan = ShortcutPlan.sample()
    #expect(OverlapEngine.search(plan.records, query: "CAPTURE").count == 1)
    #expect(OverlapEngine.search(plan.records, query: "mosaic").count == 1)
    #expect(OverlapEngine.search(plan.records, query: "command+shift+5").count == 2)
    #expect(OverlapEngine.search(plan.records, query: " ").count == plan.records.count)
}
@Test func sampleCoversEveryClassification() { let p = ShortcutPlan.sample(); let pairs = OverlapEngine.overlaps(p.records, contexts: p.contexts); #expect(pairs.filter { $0.kind == .definite }.count == 1); #expect(pairs.filter { $0.kind == .possible }.count == 1); #expect(pairs.filter { $0.kind == .separate }.count == 2) }
@Test func persistenceRoundTripIncludesPendingChanges() throws { let p = ShortcutPlan.sample(); let decoded = try JSONDecoder().decode(ShortcutPlan.self, from: JSONEncoder().encode(p)).validated(); #expect(decoded == p) }
@Test func persistedInvalidRecordIsRejected() throws {
    let invalid = "{\"records\":[{\"id\":\"00000000-0000-0000-0000-000000000000\",\"command\":\"\",\"chord\":{\"key\":\"k\",\"modifiers\":[]}}],\"contexts\":[],\"replacements\":[]}"
    let decoded = try JSONDecoder().decode(ShortcutPlan.self, from: Data(invalid.utf8))
    #expect(throws: PlanError.self) { try decoded.validated() }
}
@Test func manualChecklistContainsBeforeAndAfter() { let p = ShortcutPlan.sample(); #expect(p.checklist.contains("Capture panel")); #expect(p.checklist.contains("⌘")); #expect(p.checklist.contains(p.records[0].chord.display + " → " + p.proposedRecords[0].chord.display)) }
@Test func plusKeyRoundTripsThroughText() throws { let chord = try Chord(key: "+", modifiers: ["command"]); #expect(try Chord.parse(chord.text) == chord) }


@Test func hiddenPossiblePairsCannotProduceClearClaim() throws {
    let pairs = OverlapEngine.overlaps([try row(nil), try row("Editor")])
    let comparison = PlanComparison(pairs: pairs, showPossible: false)
    #expect(comparison.visible.isEmpty)
    #expect(!comparison.isClear)
    #expect(comparison.hasHiddenPossible)
    #expect(PlanComparison(pairs: pairs, showPossible: true).visible.count == 1)
}
@Test func separateScopesCanBeClearWhileVisible() throws {
    let pairs = OverlapEngine.overlaps([try row("Editor"), try row("Canvas")])
    #expect(PlanComparison(pairs: pairs, showPossible: false).isClear)
    #expect(!PlanComparison(pairs: pairs, showPossible: false).hasHiddenPossible)
}
@Test func defaultScopeAppliesOnlyToNewRecords() throws {
    #expect(RecordDefaults.scope(for: nil, defaultScope: "Canvas") == "Canvas")
    #expect(RecordDefaults.scope(for: try row("Editor"), defaultScope: "Canvas") == "Editor")
    let unknown = try row(nil)
    let editorScope = RecordDefaults.scope(for: unknown, defaultScope: "Canvas")
    let saved = try ShortcutRecord(id: unknown.id, command: unknown.command, key: unknown.chord.key, modifiers: unknown.chord.modifiers, scope: editorScope, context: unknown.context)
    #expect(saved.scope == nil)
    #expect(OverlapEngine.compare(saved, try row("Editor"))?.kind == .possible)
}
@Test func unresolvedPolicyUsesLocalContent() {
    #expect(PolicyDestination.webURL("https://{DOMAIN}/apps/keyoverlap/privacy/") == nil)
    #expect(PolicyDestination.webURL(nil) == nil)
    #expect(PolicyDestination.webURL("http://barframe.com/apps/keyoverlap/support/") == nil)
    #expect(PolicyDestination.webURL("https://barframe.com/apps/keyoverlap/privacy/")?.host == "barframe.com")
}
@Test func spanishValidationMessagesAreTranslated() throws {
    let cases: [() throws -> Void] = [
        { _ = try Chord.parse("") }, { _ = try Chord.parse("command+multi") },
        { _ = try Chord.parse("meta+k") }, { _ = try row(name: "") },
        { _ = try row("*", "Edit") }, { _ = try row(nil, "Edit") },
        { _ = try ExclusiveContexts(app: "", first: "a", second: "b") },
        { _ = try PlanImport.decode(Data("{}".utf8)) },
        { _ = try PlanImport.decode(Data("[{".utf8)) },
        { _ = try PlanImport.decode(Data("[{}]".utf8)) }
    ]
    for operation in cases {
        do { try operation(); Issue.record("Expected invalid input") }
        catch {
            let text = PlanText.error(error, language: "es")
            #expect(text != error.localizedDescription)
            #expect(!text.contains("Row index"))
            #expect(PlanText.error(error, language: "en") == error.localizedDescription)
        }
    }
    do { _ = try PlanImport.decode(Data("[{}]".utf8)) }
    catch { #expect(PlanText.error(error, language: "es").contains("Índice de fila 0")) }
}
@Test func spanishChecklistAndNamedKeys() throws {
    let record = try row(nil, key: "space", name: "Acción")
    var plan = ShortcutPlan(records: [record])
    try plan.stage(id: record.id, chord: Chord(key: "forwarddelete", modifiers: ["command"]))
    let text = plan.checklist(language: "es")
    #expect(text.contains("Lista de cambios manuales"))
    #expect(text.contains("en Ámbito desconocido"))
    #expect(text.contains("⌘Espacio → ⌘Suprimir"))
    #expect(!text.contains("Unknown scope"))
    #expect(PlanText.translate("Sample", language: "es") == "Ejemplo")
    #expect(PlanText.translate("Candidate", language: "es") == "Candidato")
    #expect(try Chord(key: "pagedown", modifiers: []).display(language: "es") == "Página abajo")
}
