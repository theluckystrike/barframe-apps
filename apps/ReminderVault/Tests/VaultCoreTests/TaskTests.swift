import Foundation
import Testing
@testable import VaultCore
@Test func unchecked() { #expect(TaskText.parse("- [ ] Task").first?.value == TaskValue("Task")) }
@Test func checked() { #expect(TaskText.parse("- [x] Task").first?.value.completed == true) }
@Test func uppercase() { #expect(TaskText.parse("- [X] Task").first?.value.completed == true) }
@Test func indentation() { #expect(TaskText.parse("  - [ ] Nested").count == 1) }
@Test func ordinaryList() { #expect(TaskText.parse("- Something\nprose [ ]").isEmpty) }
@Test func dueDate() { #expect(TaskText.parse("- [ ] Task 📅 2026-10-20").first?.value.due == "2026-10-20") }
@Test func invalidDatePreserved() { #expect(TaskText.parse("- [ ] Task 📅 2026-02-30").first?.value.title == "Task 📅 2026-02-30") }
@Test func fencedCode() { #expect(TaskText.parse("```md\n- [ ] No\n```\n- [ ] Yes").count == 1) }
@Test func tildeFence() { #expect(TaskText.parse("~~~\n- [ ] No\n~~~").isEmpty) }
@Test func identity() { #expect(TaskText.parse("- [ ] Task <!-- rv:abc-123 -->").first?.id == "abc-123") }
@Test func unchangedRoundtrip() throws { let s = "# Heading\r\n  - [X] Task <!-- rv:abc -->\r\nOther\r\n"; #expect(try TaskText.replacing(s, line: 1, value: TaskValue("Task", completed: true), id: "abc") == s) }
@Test func preservesProse() throws { let s = "# Heading\n- [ ] Task\n\nDo not change!\n"; let v = try TaskText.replacing(s, line: 1, value: TaskValue("Task", completed: true), id: "a"); #expect(v.hasPrefix("# Heading\n")); #expect(v.hasSuffix("\n\nDo not change!\n")) }
@Test func preservesCRLF() throws { let s = "# Heading\r\n- [ ] Task\r\nEnd\r\n"; let v = try TaskText.replacing(s, line: 1, value: TaskValue("Task", completed: true), id: "a"); #expect(v.components(separatedBy: "\r\n").count == 4) }
@Test func noTrailingNewline() throws { let v = try TaskText.replacing("- [ ] Task", line: 0, value: TaskValue("Task"), id: "a"); #expect(!v.hasSuffix("\n")) }
@Test func appendSeparator() throws { #expect(try TaskText.appended("Prose", value: TaskValue("New"), id: "b") == "Prose\n- [ ] New <!-- rv:b -->\n") }
@Test func rejectNonTask() { #expect(throws: VaultError.self) { try TaskText.replacing("Prose", line: 0, value: TaskValue("New"), id: "b") } }
@Test func rejectMultiline() { #expect(throws: VaultError.self) { try TaskText.replacing("- [ ] Task", line: 0, value: TaskValue("Bad\nTitle"), id: "b") } }
@Test func localOnly() { let a = TaskValue("A"), b = TaskValue("B"); #expect(Reconcile.resolve(local: b, remote: a, baseline: a, localDate: .distantPast, remoteDate: .distantFuture).winner == .markdown) }
@Test func remoteOnly() { let a = TaskValue("A"), b = TaskValue("B"); #expect(Reconcile.resolve(local: a, remote: b, baseline: a, localDate: .distantFuture, remoteDate: .distantPast).winner == .reminder) }
@Test func newestConflict() { let r = Reconcile.resolve(local: TaskValue("L"), remote: TaskValue("R"), baseline: TaskValue("B"), localDate: .distantPast, remoteDate: .distantFuture); #expect(r.conflict); #expect(r.winner == .reminder) }
@Test func equalNoConflict() { let a = TaskValue("A"); let r = Reconcile.resolve(local: a, remote: a, baseline: nil, localDate: .now, remoteDate: .now); #expect(r.winner == .equal); #expect(!r.conflict) }
@Test func timestampTie() { let d = Date(); #expect(Reconcile.resolve(local: TaskValue("L"), remote: TaskValue("R"), baseline: nil, localDate: d, remoteDate: d).winner == .markdown) }
@Test func leapDate() { #expect(TaskText.validDate("2028-02-29")); #expect(!TaskText.validDate("2026-02-29")) }
@Test func unicodeRoundtrip() throws { let v = TaskValue("日本語 🌿", due: "2026-10-20"); let s = try TaskText.appended("", value: v, id: "unicode"); #expect(TaskText.parse(s).first?.value == v) }

@Test func changingID() throws { let s = try TaskText.replacing("- [ ] Task <!-- rv:old -->", line: 0, value: TaskValue("Task"), id: "new"); #expect(s == "- [ ] Task <!-- rv:new -->") }
@Test func rejectMarkerTitle() { #expect(throws: VaultError.self) { try TaskText.appended("", value: TaskValue("Bad <!-- rv:abc -->"), id: "b") } }
