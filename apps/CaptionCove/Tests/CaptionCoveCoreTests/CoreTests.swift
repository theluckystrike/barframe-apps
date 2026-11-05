import Foundation
import Testing
@testable import CaptionCoveCore

func cue(_ id:Int=1,_ start:Int=1000,_ end:Int=3000,_ text:String="Hello")->Cue { Cue(id:id,start:start,end:end,text:text) }
func parsed(_ cues:[Cue])->ParsedSRT { ParsedSRT(cues:cues) }
func scan(_ a:[Cue],_ b:[Cue],_ rules:Rules=Rules())->ScanResult { Comparator.scan(reference:parsed(a),languages:[("Spanish",parsed(b))],rules:rules) }
@Test func parsesSample() { #expect(SRTParser.parse(Samples.reference).cues.count == 3) }
@Test func acceptsUTF8BOM() { #expect(SRTParser.parse("\u{feff}"+Samples.reference).complete) }
@Test func acceptsCRLF() { #expect(SRTParser.parse(Samples.reference.replacingOccurrences(of:"\n",with:"\r\n")).cues.count == 3) }
@Test func acceptsCR() { #expect(SRTParser.parse(Samples.reference.replacingOccurrences(of:"\n",with:"\r")).complete) }
@Test func rejectsBadUTF8() { #expect(!SRTParser.parse(data:Data([0xff,0xfe])).complete) }
@Test func rejectsMinuteOverflow() { #expect(SRTParser.timestamp("00:60:01,000") == nil) }
@Test func rejectsSecondOverflow() { #expect(SRTParser.timestamp("00:00:60,000") == nil) }
@Test func rejectsMissingMilliseconds() { #expect(SRTParser.timestamp("00:00:01") == nil) }
@Test func rejectsInvalidMillisecondLength() { #expect(SRTParser.timestamp("00:00:01,00") == nil) }
@Test func parsesTimestampPrecisely() { #expect(SRTParser.timestamp("01:02:03,456") == 3723456) }
@Test func rejectsDuplicateIDs() { let p=SRTParser.parse(Samples.reference+"\n"+Samples.reference); #expect(!p.complete); #expect(p.errors.contains{$0.contains("Duplicate")}) }
@Test func rejectsMalformedTimecode() { #expect(!SRTParser.parse("1\n00:00:x1,000 --> 00:00:03,000\nHi").complete) }
@Test func rejectsZeroDuration() { #expect(!SRTParser.parse("1\n00:00:01,000 --> 00:00:01,000\nHi").complete) }
@Test func rejectsReversedDuration() { #expect(!SRTParser.parse("1\n00:00:03,000 --> 00:00:01,000\nHi").complete) }
@Test func rejectsNoInputs() { #expect(SRTParser.parse("").errors == ["No subtitle cues found"]) }
@Test func rejectsNonNumericIDs() { #expect(!SRTParser.parse("abc\n00:00:01,000 --> 00:00:03,000\nHi").complete) }
@Test func missingCueIsParityFailure() { let r=scan([cue(),cue(2)], [cue()]); #expect(r.rows[1].count(.missing) == 1); #expect(r.state == .issues) }
@Test func extraCueIsDistinct() { #expect(scan([cue()],[cue(),cue(2)]).rows[1].count(.extra) == 1) }
@Test func renumberingIsIncomplete() { let r=scan([cue(1),cue(2)],[cue(101),cue(102)]); #expect(r.state == .incomplete); #expect(r.rows[1].count(.identity) == 1) }
@Test func neverMatchesByPosition() { let r=scan([cue(1)],[cue(99,1000,3500)]); #expect(r.rows[1].count(.drift) == 0); #expect(r.rows[1].count(.missing) == 1) }
@Test func toleranceBoundaryPasses() { #expect(scan([cue()],[cue(1,1100,3100)]).rows[1].count(.drift) == 0) }
@Test func toleranceBeyondBoundaryWarns() { #expect(scan([cue()],[cue(1,1101,3100)]).rows[1].count(.drift) == 1) }
@Test func driftIsSigned() { let f=scan([cue()],[cue(1,800,3500)]).rows[1].findings.first{$0.kind == .drift}; #expect(f?.startDrift == -200); #expect(f?.endDrift == 500) }
@Test func stripsSupportedSimpleTags() { #expect(cue(1,0,1000,"<b>A</b><i>B</i><u>C</u><font color=\"red\">D</font>").visibleText == "ABCD") }
@Test func keepsUnsupportedTagsVisible() { #expect(cue(1,0,1000,"<ruby>A</ruby>").visibleText == "<ruby>A</ruby>") }
@Test func countsGraphemesAndSpaces() { #expect(cue(1,0,1000,"e\u{301} 👨‍👩‍👧‍👦\nA").visibleCharacters == 4) }
@Test func cpsUsesDuration() { #expect(cue(1,0,2000,"ABCD").cps == 2) }
@Test func zeroDurationHasNoCPS() { #expect(cue(1,1000,1000).cps == nil) }
@Test func emptyTextWarns() { #expect(Comparator.local(parsed([cue(1,0,1000,"<i></i>")]),rules:Rules()).contains{$0.kind == .text && $0.reason == "Empty visible text"}) }
@Test func userSpeedRuleWarns() { #expect(Comparator.local(parsed([cue(1,0,1000,"ABCDE")]),rules:Rules(maxCPS:4)).contains{$0.kind == .text}) }
@Test func speedBoundaryPasses() { #expect(!Comparator.local(parsed([cue(1,0,1000,"ABCD")]),rules:Rules(maxCPS:4)).contains{$0.kind == .text}) }
@Test func temporalOverlapWarns() { #expect(Comparator.local(parsed([cue(1,1000,4000),cue(2,3000,5000)]),rules:Rules()).filter{$0.kind == .overlap}.count == 1) }
@Test func nestedOverlapsAllDetected() { #expect(Comparator.local(parsed([cue(1,0,10000),cue(2,1000,2000),cue(3,3000,4000)]),rules:Rules()).filter{$0.kind == .overlap}.count == 2) }
@Test func touchingCuesDoNotOverlap() { #expect(!Comparator.local(parsed([cue(1,1000,2000),cue(2,2000,3000)]),rules:Rules()).contains{$0.kind == .overlap}) }
@Test func overlapPolicyCanBeDisabled() { #expect(!Comparator.local(parsed([cue(1,0,3000),cue(2,1000,4000)]),rules:Rules(warnOverlap:false)).contains{$0.kind == .overlap}) }
@Test func cleanDeliveryReady() { #expect(scan([cue()],[cue()]).state == .ready) }
@Test func malformedReferenceCannotClaimParity() { let r=Comparator.scan(reference:ParsedSRT(cues:[cue()],errors:["Malformed"]),languages:[("Spanish",parsed([cue()]))]); #expect(r.state == .incomplete); #expect(!r.rows[1].complete) }
@Test func noLanguagesIncomplete() { #expect(Comparator.scan(reference:parsed([cue()]),languages:[]).state == .incomplete) }
@Test func staleResultIncomplete() { var r=scan([cue()],[cue()]); r.stale=true; #expect(r.state == .incomplete) }
@Test func reportOmitsDialogueByDefault() { let r=scan([cue()],[cue(1,1000,3000,"SECRET DIALOGUE")],Rules(maxCPS:1)); #expect(!r.report().contains("SECRET DIALOGUE")); #expect(r.report().contains("Spanish")); #expect(r.report().contains("cue 1")) }
@Test func reportDialogueRequiresOptIn() { let p=parsed([cue(1,1000,3000,"SECRET DIALOGUE")]); let r=scan([cue()],p.cues,Rules(maxCPS:1)); #expect(r.report(dialogue:["Spanish":p]).contains("SECRET DIALOGUE")) }
@Test func sampleReportIsLabeled() { #expect(Comparator.scan(reference:parsed([cue()]),languages:[],sample:true).report().contains("Sample")) }
@Test func formatTimeRoundtrip() { #expect(SRTParser.timestamp(formatTime(3723456)) == 3723456) }
@Test func persistsRulesBookmarksAndSummary() throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:url) }
    let p=Project(reference:InputReference(label:"Reference",bookmark:Data([1,2,3]),filename:"test.srt"),languages:[InputReference(label:"Spanish",bookmark:Data([4]),filename:"es.srt")],rules:Rules(toleranceMS:250,maxCPS:25,warnOverlap:false),result:scan([cue()],[cue()]))
    try Persistence.save(p,to:url); #expect(try Persistence.load(from:url) == p)
}
@Test func corruptStateThrows() throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:url) }; try Data("not json".utf8).write(to:url)
    #expect(throws:(any Error).self) { try Persistence.load(from:url) }
}
@Test func sampleCannotPersistAsLiveEvidence() throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:url) }
    var r=scan([cue()],[cue()]); r.sample=true; try Persistence.save(Project(result:r),to:url)
    #expect(throws:(any Error).self) { try Persistence.load(from:url) }
}
@Test func duplicateLanguageLabelsRejected() throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:url) }
    let input=InputReference(label:"Spanish",bookmark:Data(),filename:"es.srt"); try Persistence.save(Project(languages:[input,input]),to:url)
    #expect(throws:(any Error).self) { try Persistence.load(from:url) }
}
@Test func invalidStoredRulesRejected() throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:url) }
    var rules=Rules(); rules.toleranceMS = -1; try Persistence.save(Project(rules:rules),to:url)
    #expect(throws:(any Error).self) { try Persistence.load(from:url) }
}

@Test func pathologicalOverlapSetCannotClaimComplete() {
    let cues=(1...110).map{cue($0,1000,3000,"A")}
    let r=scan(cues,cues)
    #expect(r.state == .incomplete)
    #expect(!r.rows[0].complete)
    #expect(r.rows[0].findings.count == Comparator.findingLimit+1)
    #expect(r.rows[0].findings.last?.kind == .invalid)
}

@Test func timingWhitespaceAndPositionCoordinatesAccepted() {
    let text="1\n  0:00:01.000\t-->\t00:00:03,000 X1:40 X2:600 Y1:20 Y2:50   \nHello"
    let result=SRTParser.parse(text)
    #expect(result.complete)
    #expect(result.cues.first?.start == 1000)
    #expect(result.cues.first?.end == 3000)
}
@Test func timingWithoutArrowSpacesAccepted() {
    #expect(SRTParser.parse("1\n00:00:01,000-->00:00:03,000   \nHello").complete)
}
@Test func mixedDeletionAndRenumberingIsUnsuitable() {
    let r=scan([cue(1,1000,3000),cue(2,4000,6000),cue(3,7000,9000)],[cue(1,1000,3000),cue(20,4000,6000)])
    #expect(r.rows[1].count(.identity) == 1)
    #expect(!r.rows[1].complete)
    #expect(r.rows[1].count(.missing) == 2)
    #expect(r.rows[1].count(.extra) == 1)
}
@Test func mergedAndShiftedCueIDsDoNotProduceFalseDrift() {
    let reference=(1...10).map { cue($0,$0*3000,$0*3000+2000) }
    let translated=[reference[0],cue(2,6000,11000)]+(3...9).map { cue($0,($0+1)*3000,($0+1)*3000+2000) }
    let r=scan(reference,translated)
    #expect(r.rows[1].count(.identity) == 1)
    #expect(r.rows[1].count(.drift) == 0)
    #expect(r.state == .incomplete)
}
@Test func ordinaryMissingCueWithIndependentDriftStillReportsTiming() {
    let r=scan([cue(1,1000,3000),cue(2,4000,6000),cue(3,7000,9000)],[cue(1,1450,3450),cue(3,7000,9000)])
    #expect(r.rows[1].count(.identity) == 0)
    #expect(r.rows[1].count(.drift) == 1)
}
@Test func warningOnlyParityRemainsReadyWithSeparateCount() {
    let cues=[cue(1,1000,5000,""),cue(2,4000,6000,"Extremely fast subtitle")]
    let result=scan(cues,cues,Rules(maxCPS:2))
    #expect(result.state == .ready)
    #expect(result.warningCount == 6)
    #expect(result.report().contains("Local warnings 6"))
}
