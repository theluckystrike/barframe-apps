import Testing
import Foundation
@testable import PermitPeekCore

func base() -> Snapshot { Snapshot(identity:"example",version:"1",team:"A",declarations:["com.apple.security.app-sandbox":"true"]) }
@Test func dictionaryOrder() { #expect(Compare.normalize(["b":2,"a":1]) == Compare.normalize(["a":1,"b":2])) }
@Test func arrayOrder() { #expect(Compare.normalize(["b","a"]) == Compare.normalize(["a","b"])) }
@Test func booleanTrue() { #expect(Compare.normalize(true) == "true") }
@Test func booleanFalse() { #expect(Compare.normalize(false) == "false") }
@Test func integerDistinctFromBool() { #expect(Compare.normalize(1) == "1") }
@Test func nestedOrder() { #expect(Compare.normalize(["x":["b","a"]]) == "{\"x\"=[\"a\", \"b\"]}") }
@Test func emptyArray() { #expect(Compare.normalize([String]()) == "[]") }
@Test func added() { var b=base(); b.declarations["new"]="true"; #expect(Compare.changes(base(),b).first?.kind == "Added") }
@Test func removed() { var b=base(); b.declarations=[:]; #expect(Compare.changes(base(),b).first?.kind == "Removed") }
@Test func changed() { var b=base(); b.declarations["com.apple.security.app-sandbox"]="false"; #expect(Compare.changes(base(),b).first?.kind == "Changed") }
@Test func unchanged() { #expect(Compare.changes(base(),base()).isEmpty) }
@Test func teamChange() { var b=base(); b.team="B"; #expect(Compare.changes(base(),b).first?.key == "Signing team") }
@Test func versionChange() { var b=base(); b.version="2"; #expect(Compare.changes(base(),b).first?.key == "Version") }
@Test func identityChange() { var b=base(); b.identity="other"; #expect(Compare.changes(base(),b).first?.key == "Bundle identity") }
@Test func baselineNotAutomatic() { var w=Watch(id:"a",name:"A"); w.receive(base()); #expect(w.baseline == nil) }
@Test func acknowledgement() { var w=Watch(id:"a",name:"A"); w.receive(base()); w.acknowledge(); #expect(w.baseline == base()) }
@Test func unknownCannotAcknowledge() { var w=Watch(id:"a",name:"A",baseline:base()); var b=base(); b.team="B"; w.receive(b); w.fail("unknown"); w.acknowledge(); #expect(w.baseline == base()) }
@Test func errorPreservesCurrent() { var w=Watch(id:"a",name:"A",current:base()); w.fail("denied"); #expect(w.current == base()) }
@Test func recovery() { var w=Watch(id:"a",name:"A",error:"denied"); w.receive(base()); #expect(w.error == nil) }
@Test func unsandboxedUnknown() { var b=base(); b.declarations=[:]; #expect(b.networkExplanation.contains("unknown")); #expect(!b.networkExplanation.contains("blocked")) }
@Test func noClientNotDeclared() { #expect(base().networkExplanation.contains("not declared")) }
@Test func clientDeclared() { var b=base(); b.declarations["com.apple.security.network.client"]="true"; #expect(b.networkExplanation.contains("Outgoing network declared")) }
@Test func fixturesIsolated() { var a=Samples.watches; a[0].acknowledge(); #expect(!Samples.watches[0].changes.isEmpty); #expect(a[0].changes.isEmpty) }
@Test func unreadableFixture() { #expect(Samples.watches[1].error != nil); #expect(Samples.watches[1].baseline != nil) }
@Test func reportIncludesCoverage() { #expect(Samples.watches[0].report.contains("Main executable only")); #expect(Samples.watches[0].report.contains("Before")) }
@Test func persistence() throws { let w=Samples.watches[0]; let data=try JSONEncoder().encode(w); let r=try JSONDecoder().decode(Watch.self,from:data); #expect(r.baseline == w.baseline); #expect(r.changes == w.changes) }

@Test func booleanAndStringDiffer() { #expect(Compare.normalize(true) != Compare.normalize("true")) }
@Test func arrayDelimiterCollision() { #expect(Compare.normalize(["a, b"]) != Compare.normalize(["a", "b"])) }
