import Foundation
import Testing
@testable import ColumnLatchCore

func rows(_ value: String, delimiter: Character = ",") throws -> [[String]] { var result: [[String]] = []; try CSV.read(Data(value.utf8), delimiter: delimiter) { row, _ in result.append(row) }; return result }
func run(_ csv: String, _ c: Contract = .sample) throws -> Summary { try Validator.run(Data(csv.utf8), contract: c) }
@Test func quotedDelimiter() throws { #expect(try rows("a,b\n\"x,y\",z") == [["a","b"],["x,y","z"]]) }
@Test func escapedQuote() throws { #expect(try rows("a\n\"x\"\"y\"")[1] == ["x\"y"]) }
@Test func embeddedNewline() throws { #expect(try rows("a\n\"x\ny\"")[1] == ["x\ny"]) }
@Test func bom() throws { #expect(try rows("\u{FEFF}a,b")[0] == ["a","b"]) }
@Test func crlf() throws { #expect(try rows("a,b\r\nx,y\r\n").count == 2) }
@Test func semicolon() throws { #expect(try rows("a;b\nx;y", delimiter: ";")[1] == ["x","y"]) }
@Test func tab() throws { #expect(try rows("a\tb", delimiter: "\t")[0] == ["a","b"]) }
@Test func unterminated() { #expect(throws: CSVError.malformed(2)) { try rows("a\n\"b") } }
@Test func misplacedQuote() { #expect(throws: CSVError.malformed(2)) { try rows("a\nx\"y") } }
@Test func trailingQuoteText() { #expect(throws: CSVError.malformed(2)) { try rows("a\n\"x\"z") } }
@Test func duplicateHeader() { #expect(throws: CSVError.duplicateHeader) { try run("item_id,item_id\na,b") } }
@Test func blankHeader() { #expect(throws: CSVError.duplicateHeader) { try run(",quantity\na,1") } }
@Test func absentOptional() throws { let s = try run("item_id,quantity\n001,2"); #expect(!s.failed && s.optionalAbsent == ["status"]) }
@Test func missingRequired() throws { #expect(try run("item_id\n001").findings.contains { $0.category == "Missing column" }) }
@Test func leadingZeroKeys() throws { #expect(try !run("item_id,quantity\n001,2\n1,2").failed) }
@Test func everyDuplicateGroup() throws { let s = try run("item_id,quantity\n1,2\n2,2\n1,3\n2,4"); #expect(s.findings.filter { $0.category == "Duplicate key" }.map(\.records) == [[2,4],[3,5]]) }
@Test func emptyKey() throws { #expect(try run("item_id,quantity\n,2").findings.contains { $0.category == "Empty key" }) }
@Test func invalidInteger() throws { #expect(try run("item_id,quantity\nx,2.0").failed) }
@Test func numericGrammar() { #expect(Rule("a", kind: .integer).accepts("-004")); #expect(!Rule("a", kind: .integer).accepts("1e3")); #expect(!Rule("a", kind: .decimal).accepts("1,5")); #expect(Rule("a", kind: .decimal).accepts("+1.5")) }
@Test func exactAllowed() { let r = Rule("a", kind: .allowed, allowed: ["Yes"]); #expect(r.accepts("Yes")); #expect(!r.accepts("yes")); #expect(!r.accepts(" Yes")) }
@Test func emptyPolicy() { #expect(Rule("a", allowEmpty: true).accepts("")); #expect(!Rule("a").accepts("")) }
@Test func unexpectedWarnFail() throws { var c = Contract.sample; #expect(try !run("item_id,quantity,extra\n1,2,x", c).failed); c.unexpectedFails = true; #expect(try run("item_id,quantity,extra\n1,2,x", c).failed) }
@Test func malformedWidth() throws { #expect(try run("item_id,quantity\n1").findings.first?.category == "Malformed width") }
@Test func comparison() throws { let c = try run("item_id,quantity\n1,2"); let s = try run("item_id,quantity\n1,x"); #expect(Validator.compare(s, previous: c).newCategories == ["Invalid value · quantity"]); #expect(Validator.compare(s, previous: s).newCategories.isEmpty) }
@Test func incompletePreservesBaseline() throws { let c = Contract.sample; var state = SavedState(); let previous = try run("item_id,quantity\n1,2", c); state.commit(previous, contract: c); state.commit(Summary(complete: false, rows: 0, findings: []), contract: c); #expect(state.baselines[c.id.uuidString] == previous) }
@Test func cancellation() { #expect(throws: CancellationError.self) { try Validator.run(Validator.sampleData, contract: .sample, cancelled: { true }) } }
@Test func redactedReport() throws { let c = Contract.sample; let s = try Validator.run(Validator.sampleData, contract: c); let report = s.report(contract: c, sample: true); #expect(report.contains("Sample")); #expect(!report.contains("many")); #expect(!report.contains("001")) }
@Test func persistence() throws { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: url) }; var s = SavedState(); let c = Contract.sample; s.contracts = [c]; s.commit(try Validator.run(Validator.sampleData, contract: c), contract: c); try StateStore.save(s, at: url); let restored = try StateStore.load(at: url); #expect(restored.contracts == s.contracts); #expect(restored.baselines == s.baselines) }
@Test func corruptPersistence() throws { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: url) }; try Data("broken".utf8).write(to: url); #expect(throws: (any Error).self) { try StateStore.load(at: url) } }
@Test func emptyFile() { #expect(throws: CSVError.empty) { try run("") } }
@Test func invalidEncoding() { #expect(throws: CSVError.encoding) { try Validator.run(Data([0xFF]), contract: .sample) } }
@Test func oversized() { #expect(throws: CSVError.tooLarge) { try Validator.run(Data(repeating: 65, count: CSV.limit + 1), contract: .sample) } }
@Test func headerOnlyNoInference() throws { #expect(try CSV.header(Data("a,b\n\"broken".utf8), delimiter: ",") == ["a","b"]) }
@Test func trailingEmptyField() throws { #expect(try rows("a,b\nx,")[1] == ["x",""]) }

@Test func reportUsesCompletedRules() throws { var c = Contract.sample; let s = try Validator.run(Validator.sampleData, contract: c); c.name = "Changed later"; #expect(!s.report(contract: c, sample: false).contains("Changed later")) }
@Test func absentOptionalUniqueKeyFails() throws { var c = Contract.sample; c.rules[0].required = false; #expect(try run("quantity\n1", c).findings.contains { $0.category == "Missing key column" }) }
@Test func malformedLogicalRecordAfterNewline() { #expect(throws: CSVError.malformed(3)) { try rows("a\n\"b\nc\"\n\"bad") } }

@Test func numericNewlineRejected() { #expect(!Rule("a", kind: .integer).accepts("12\n")); #expect(!Rule("a", kind: .decimal).accepts("1.2\r\n")) }

@Test func readsEveryChunk() throws { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: url) }; let data = Data(repeating: 65, count: 3 * 64 * 1024 + 17); try data.write(to: url); #expect(try InputReader.read(url) == data) }
@Test func fileReadCancellation() throws { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: url) }; try Data("a".utf8).write(to: url); #expect(throws: CancellationError.self) { try InputReader.read(url, cancelled: { true }) } }
