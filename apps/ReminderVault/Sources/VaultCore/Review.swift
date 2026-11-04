import Foundation

/// A successful preview alone must never restart automatic synchronization.
public struct SyncApproval {
    public private(set) var approved = false
    public private(set) var previewReady = false
    public init() {}
    public mutating func beginPreview() { previewReady = false }
    public mutating func previewSucceeded() { previewReady = true }
    public mutating func invalidate() { approved = false; previewReady = false }
    public mutating func previewFailed() { invalidate() }
    public mutating func applySucceeded() { if previewReady { approved = true }; previewReady = false }
    public mutating func applyFailed() { invalidate() }
}

/// The complete mapped values on both sides and the proposed result are reviewable.
public struct TaskReview {
    public let file: String
    public let list: String
    public let taskID: String
    public let vaultBefore: TaskValue?
    public let reminderBefore: TaskValue?
    public let proposed: TaskValue
    public init(file: String, list: String, taskID: String, vaultBefore: TaskValue?, reminderBefore: TaskValue?, proposed: TaskValue) {
        self.file = file; self.list = list; self.taskID = taskID
        self.vaultBefore = vaultBefore; self.reminderBefore = reminderBefore; self.proposed = proposed
    }
    public static func describe(_ value: TaskValue?) -> String {
        guard let value else { return "Not present" }
        return "Title \(value.title) · \(value.completed ? "Completed" : "Pending") · Due \(value.due ?? "None")"
    }
    public var lines: [String] {
        ["File \(file)", "List \(list) · Task \(taskID)",
         "Vault before · " + Self.describe(vaultBefore), "Reminders before · " + Self.describe(reminderBefore),
         "Proposed · " + Self.describe(proposed)]
    }
}

public enum HelpLink {
    public static func webURL(_ raw: String?) -> URL? {
        guard let raw, !raw.contains("{"), !raw.contains("}"), let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
