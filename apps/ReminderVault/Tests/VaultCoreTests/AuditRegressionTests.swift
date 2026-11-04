import Foundation
import Testing
@testable import VaultCore

@Test func literalDueTokenWithoutDateRoundtrips() throws {
    let value = TaskValue("Discuss 📅 2026-10-20")
    let text = try TaskText.appended("", value: value, id: "probe")
    #expect(TaskText.parse(text).first?.value == value)
    #expect(text.contains(#"\📅 2026-10-20"#))
}
@Test func literalDueTokenWithRealDueRoundtrips() throws {
    let value = TaskValue("Discuss 📅 2026-10-20 and 📅 2026-10-21", completed: true, due: "2026-11-01")
    #expect(TaskText.parse(try TaskText.appended("", value: value, id: "dated")).first?.value == value)
}
@Test func reservedTitleReplacementPreservesOtherBytes() throws {
    let original = "# Keep\r\n- [ ] Before <!-- rv:a -->\r\nUnrelated \\📅 2026-10-20\r\n"
    let value = TaskValue(#"Discuss \📅 2026-10-20 in C:\notes\"#, due: "2026-11-01")
    let updated = try TaskText.replacing(original, line: 1, value: value, id: "a")
    #expect(TaskText.parse(updated).first?.value == value)
    #expect(updated.hasPrefix("# Keep\r\n"))
    #expect(updated.hasSuffix("\r\nUnrelated \\📅 2026-10-20\r\n"))
    #expect(try TaskText.replacing(updated, line: 1, value: value, id: "a") == updated)
}
@Test func importedDateTokenNeverBecomesDueOnLaterCompletion() throws {
    var value = TaskValue("📅 2026-10-20")
    let text = try TaskText.appended("", value: value, id: "literal")
    value.completed = true
    let updated = try TaskText.replacing(text, line: 0, value: value, id: "literal")
    #expect(TaskText.parse(updated).first?.value == value)
    #expect(TaskText.parse(updated).first?.value.due == nil)
}
@Test func previewShowsRemoteRenameCompletionAndDue() {
    let old = TaskValue("Old", due: "2026-10-20")
    let new = TaskValue("Renamed", completed: true, due: "2026-11-01")
    let review = TaskReview(file: "Nested/Tasks.md", list: "Work [list-id]", taskID: "task-id", vaultBefore: old, reminderBefore: new, proposed: new)
    #expect(review.lines == ["File Nested/Tasks.md", "List Work [list-id] · Task task-id",
        "Vault before · Title Old · Pending · Due 2026-10-20",
        "Reminders before · Title Renamed · Completed · Due 2026-11-01",
        "Proposed · Title Renamed · Completed · Due 2026-11-01"])
}
@Test func previewShowsRemovedDueAndMissingSide() {
    let review = TaskReview(file: "Inbox.md", list: "Personal", taskID: "a", vaultBefore: nil, reminderBefore: TaskValue("A", due: "2026-10-20"), proposed: TaskValue("A"))
    #expect(review.lines.contains("Vault before · Not present"))
    #expect(review.lines.last == "Proposed · Title A · Pending · Due None")
}
@Test func previewFailureRevokesAutomaticSyncUntilReviewedApply() {
    var state = SyncApproval()
    state.previewSucceeded(); state.applySucceeded()
    #expect(state.approved)
    state.beginPreview(); state.previewFailed()
    #expect(!state.approved); #expect(!state.previewReady)
    // Recovery preview must not let the timer resume automatically.
    state.previewSucceeded()
    #expect(state.previewReady); #expect(!state.approved)
    state.applySucceeded()
    #expect(state.approved); #expect(!state.previewReady)
}
@Test func applyWithoutSuccessfulPreviewCannotApprove() {
    var state = SyncApproval(); state.applySucceeded(); #expect(!state.approved)
    state.previewSucceeded(); state.applyFailed(); state.applySucceeded()
    #expect(!state.approved); #expect(!state.previewReady)
}
@Test func successfulAutomaticPreviewKeepsExistingApproval() {
    var state = SyncApproval(); state.previewSucceeded(); state.applySucceeded()
    state.beginPreview(); #expect(state.approved); #expect(!state.previewReady)
    state.previewSucceeded(); state.applySucceeded(); #expect(state.approved)
    state.invalidate(); #expect(!state.approved)
}
private var appRoot: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
@Test func timestampReasonsInBothSourceManifests() throws {
    for path in ["PrivacyInfo.xcprivacy", "Resources/PrivacyInfo.xcprivacy"] {
        let data = try Data(contentsOf: appRoot.appendingPathComponent(path))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let categories = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let timestamp = try #require(categories.first { ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryFileTimestamp" })
        #expect(Set(timestamp["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []) == Set(["3B52.1", "C617.1"]))
    }
}
@Test func bundledPolicyMatchesStoreAndExplainsDeletion() throws {
    let bundled = try String(contentsOf: appRoot.appendingPathComponent("Sources/ReminderVault/Resources/privacy.md"))
    #expect(bundled == (try String(contentsOf: appRoot.appendingPathComponent("store/privacy.md"))))
    for required in ["sync-state.json", "bookmark", "task-to-reminder", "conflict", "200", "Delete", "Revoke Reminders", "independently", "container", "Michael Lip"] {
        #expect(bundled.contains(required))
    }
    #expect(!bundled.contains("{DOMAIN}")); #expect(!bundled.contains("{BRAND}"))
}
@Test func provisionalHelpURLsUseBundledFallback() {
    #expect(HelpLink.webURL("https://{DOMAIN}/remindervault/privacy/") == nil)
    #expect(HelpLink.webURL("https://{BRAND}/support/") == nil)
    #expect(HelpLink.webURL(nil) == nil)
    #expect(HelpLink.webURL("file:///tmp/support") == nil)
    #expect(HelpLink.webURL("https://barframe.com/apps/remindervault/support/") != nil)
}

@Test func ordinaryMarkdownBackslashesRemainLiteral() throws {
    let title = #"Find \\server\notes and \📅 2026-10-20"#
    let original = "- [ ] " + title
    #expect(TaskText.parse(original).first?.value == TaskValue(title))
    let updated = try TaskText.replacing(original, line: 0, value: TaskValue(title, completed: true), id: "paths")
    #expect(TaskText.parse(updated).first?.value == TaskValue(title, completed: true))
    #expect(updated.contains("<!-- rv-escaped -->"))
}
@Test func changingEscapedTitleIdentityPreservesCodec() throws {
    let value = TaskValue(#"Discuss \📅 2026-10-20"#)
    let original = try TaskText.appended("", value: value, id: "old")
    let updated = try TaskText.replacing(original, line: 0, value: value, id: "new")
    #expect(TaskText.parse(updated).first?.value == value)
    #expect(TaskText.parse(updated).first?.id == "new")
}
@Test func reservedEscapeMarkerIsRejectedBeforeWriting() {
    #expect(throws: VaultError.self) { try TaskText.appended("", value: TaskValue("Title <!-- rv-escaped -->"), id: "marker") }
}

@Test func linkingUnchangedMarkdownDoesNotApplyTitleCodec() throws {
    let title = #"Find \\server\notes and \📅 2026-10-20"#
    let original = "- [ ] " + title
    let updated = try TaskText.replacing(original, line: 0, value: TaskValue(title), id: "link")
    #expect(updated == original + " <!-- rv:link -->")
    #expect(TaskText.parse(updated).first?.value == TaskValue(title))
}
