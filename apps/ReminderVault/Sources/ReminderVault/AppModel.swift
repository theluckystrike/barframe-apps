import AppKit
import SwiftUI
import EventKit
import VaultCore

struct Row: Identifiable { let id: String; let file: URL; let line: Int; let value: TaskValue }
struct Action: Identifiable {
    let id: String
    let file: URL
    let line: Int?
    let value: TaskValue
    let reminderID: String?
    let writeRemote: Bool
    let summary: String
    let conflict: Bool
    let review: TaskReview
}
struct Snapshot: Codable { var values: [String: TaskValue] = [:] }
@MainActor final class AppModel: ObservableObject {
    @Published var sample = false
    @Published var rows: [Row] = []
    @Published var actions: [Action] = []
    @Published var calendars: [EKCalendar] = []
    @Published var selected: Set<String> = []
    @Published var status = "Choose a vault and connect Reminders, or explore Sample mode."
    @Published var lastSync = "Never"
    @Published var busy = false
    @Published var approval = SyncApproval()
    var previewReady: Bool { approval.previewReady }
    @Published var conflictLog: [String] = []
    @Published var folderName = "No vault selected"
    @Published var interval = 5 { didSet { UserDefaults.standard.set(interval, forKey: "interval") } }
    let store = EKEventStore()
    private var folder: URL?
    private var scoped = false
    private var timer: Timer?
    private var baseline = Snapshot()
    private var documents: [URL: String] = [:]
    private var remoteSnapshot: [String: TaskValue] = [:]
    private var reminders: [EKReminder] = []
    private var pendingLinks: [String: String] = [:]
    private var approved: Bool { approval.approved }
    private var sampleRoot: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("SampleVault") }
    private var stateURL: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("sync-state.json") }
    var pending: Int { rows.filter { !$0.value.completed }.count }
    var today: [Row] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let date = sample ? "2026-10-14" : f.string(from: Date())
        return rows.filter { !$0.value.completed && ($0.value.due == nil || $0.value.due! <= date) }
    }
    init(start: Bool = true) {
        guard start else { return }
        interval = max(1, UserDefaults.standard.integer(forKey: "interval") == 0 ? 5 : UserDefaults.standard.integer(forKey: "interval"))
        pendingLinks = UserDefaults.standard.dictionary(forKey: "pendingLinks") as? [String: String] ?? [:]
        selected = Set(UserDefaults.standard.stringArray(forKey: "lists") ?? [])
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) { baseline = saved }
        conflictLog = UserDefaults.standard.stringArray(forKey: "conflicts") ?? []
        if let bookmark = UserDefaults.standard.data(forKey: "vault") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                scoped = url.startAccessingSecurityScopedResource(); folder = url; folderName = url.lastPathComponent
                if stale { UserDefaults.standard.set(try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "vault") }
            } catch { status = "Vault access expired. Select the folder again. \(error.localizedDescription)" }
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess { calendars = store.calendars(for: .reminder).filter(\.allowsContentModifications) }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.approved, !self.sample, !self.busy else { return }
                let previous = UserDefaults.standard.object(forKey: "lastDate") as? Date ?? .distantPast
                if Date().timeIntervalSince(previous) >= Double(self.interval * 60) { await self.preview(); if self.previewReady { await self.apply() } }
            }
        }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Select the Obsidian vault folder whose Markdown tasks you want to sync."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            if scoped { folder?.stopAccessingSecurityScopedResource() }
            folder = url; scoped = url.startAccessingSecurityScopedResource(); folderName = url.lastPathComponent
            UserDefaults.standard.set(bookmark, forKey: "vault"); sample = false; resetPreview(); rows = []
            status = "Vault selected. Connect Reminders and preview the first sync."
        } catch { status = error.localizedDescription }
    }
    func resetPreview() { approval.invalidate(); actions = [] }
    func select(_ id: String, on: Bool) {
        if on { selected.insert(id) } else { selected.remove(id) }
        UserDefaults.standard.set(Array(selected).sorted(), forKey: "lists"); resetPreview()
    }
    func connect() async {
        do {
            guard try await store.requestFullAccessToReminders() else { throw VaultError.denied }
            calendars = store.calendars(for: .reminder).filter(\.allowsContentModifications)
            status = calendars.isEmpty ? "Create a writable list in Reminders, then reconnect." : "Choose lists in Settings. New vault tasks use the first selected list alphabetically."
        } catch { status = error.localizedDescription }
    }
    func setSample(_ on: Bool) {
        sample = on; resetPreview(); rows = []; lastSync = "Never"
        if on {
            do {
                try FileManager.default.createDirectory(at: sampleRoot, withIntermediateDirectories: true)
                let bundled = SampleVault.url!
                let target = sampleRoot.appendingPathComponent("Today.md")
                if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: bundled, to: target) }
                folderName = "Sample vault"
                Task { await preview() }
            } catch { status = error.localizedDescription }
        } else { folderName = folder?.lastPathComponent ?? "No vault selected"; status = "Live mode. Preview to review changes before syncing." }
    }
    private func fetch() async throws -> [EKReminder] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw VaultError.denied }
        calendars = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        let lists = calendars.filter { selected.contains($0.calendarIdentifier) }
        guard !lists.isEmpty else { throw VaultError.noList }
        let predicate = store.predicateForReminders(in: lists)
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { items in
                if let items { continuation.resume(returning: items) }
                else { continuation.resume(throwing: VaultError.denied) }
            }
        }
    }
    private func value(_ r: EKReminder) -> TaskValue {
        var due: String?
        if let dc = r.dueDateComponents, let y = dc.year, let m = dc.month, let d = dc.day { due = String(format: "%04d-%02d-%02d", y, m, d) }
        return TaskValue(r.title ?? "Untitled reminder", completed: r.isCompleted, due: due)
    }
    private func marker(_ r: EKReminder) -> String? {
        let re = try! NSRegularExpression(pattern: #"<!-- rv:([A-Za-z0-9-]+) -->"#)
        let notes = r.notes ?? ""
        guard let m = re.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)) else { return nil }
        return (notes as NSString).substring(with: m.range(at: 1))
    }
    private func readVault(_ root: URL) throws -> [URL: String] {
        var files: [URL: String] = [:]; var failure: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { _, error in failure = error; return false }) else { throw VaultError.noFolder }
        for case let url as URL in enumerator {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if info.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if url.pathExtension.lowercased() == "md", info.isRegularFile == true { files[url] = try String(contentsOf: url, encoding: .utf8) }
        }
        if let failure { throw failure }
        return files
    }
    func preview() async {
        guard !busy else { return }; busy = true; approval.beginPreview()
        defer { busy = false }
        do {
            guard let root = sample ? sampleRoot : folder else { throw VaultError.noFolder }
            let docs = try readVault(root)
            let remote = sample ? [] : try await fetch()
            let firstList = calendars.filter { selected.contains($0.calendarIdentifier) }.sorted { $0.title < $1.title }.first
            func review(_ file: URL, _ id: String, _ local: TaskValue?, _ remote: EKReminder?, _ result: TaskValue) -> TaskReview {
                let path = file.path.hasPrefix(root.path + "/") ? String(file.path.dropFirst(root.path.count + 1)) : file.lastPathComponent
                let list = sample ? "Sample (no live list)" : (remote?.calendar.title ?? firstList?.title ?? "No selected list")
                let listID = sample ? "local" : (remote?.calendar.calendarIdentifier ?? firstList?.calendarIdentifier ?? "unknown")
                return TaskReview(file: path, list: list + " [" + listID + "]", taskID: id, vaultBefore: local, reminderBefore: remote.map(value), proposed: result)
            }
            var proposed: [Action] = []; var display: [Row] = []; var ids: Set<String> = []; var usedRemote: Set<String> = []
            var byMarker: [String: EKReminder] = [:]
            for r in remote { if let id = marker(r) ?? pendingLinks[r.calendarItemIdentifier] { guard byMarker[id] == nil else { throw VaultError.duplicate }; byMarker[id] = r } }
            for url in docs.keys.sorted(by: { $0.path < $1.path }) {
                let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                for task in TaskText.parse(docs[url]!) {
                    let id = task.id ?? UUID().uuidString
                    guard ids.insert(id).inserted else { throw VaultError.duplicate }
                    display.append(Row(id: id, file: url, line: task.line, value: task.value))
                    if let r = byMarker[id] {
                        usedRemote.insert(r.calendarItemIdentifier)
                        let resolution = Reconcile.resolve(local: task.value, remote: value(r), baseline: baseline.values[id], localDate: modified, remoteDate: r.lastModifiedDate ?? .distantPast)
                        if resolution.winner != .equal || marker(r) == nil {
                            proposed.append(Action(id: id, file: url, line: task.line, value: resolution.winner == .reminder ? value(r) : task.value, reminderID: r.calendarItemIdentifier, writeRemote: resolution.winner != .reminder || marker(r) == nil, summary: "\(resolution.winner == .markdown ? "Vault → Reminders" : "Reminders → Vault"): \(task.value.title)", conflict: resolution.conflict, review: review(url, id, task.value, r, resolution.winner == .reminder ? value(r) : task.value)))
                        }
                    } else if task.id != nil && baseline.values[id] != nil && !sample {
                        // A removed/moved reminder is never recreated silently.
                        proposed.append(Action(id: id, file: url, line: task.line, value: task.value, reminderID: nil, writeRemote: false, summary: "Manual review: counterpart missing for \(task.value.title)", conflict: true, review: review(url, id, task.value, nil, task.value)))
                    } else {
                        proposed.append(Action(id: id, file: url, line: task.line, value: task.value, reminderID: nil, writeRemote: !sample, summary: "\(sample ? "Sample link" : "Create reminder"): \(task.value.title)", conflict: false, review: review(url, id, task.value, nil, task.value)))
                    }
                }
            }
            for r in remote where !usedRemote.contains(r.calendarItemIdentifier) {
                let id = marker(r) ?? pendingLinks[r.calendarItemIdentifier] ?? UUID().uuidString
                if baseline.values[id] != nil {
                    proposed.append(Action(id: id, file: root.appendingPathComponent("ReminderVault Inbox.md"), line: nil, value: value(r), reminderID: r.calendarItemIdentifier, writeRemote: false, summary: "Manual review: Markdown task missing for \(r.title ?? "task")", conflict: true, review: review(root.appendingPathComponent("ReminderVault Inbox.md"), id, nil, r, value(r))))
                    continue
                }
                guard ids.insert(id).inserted else { throw VaultError.duplicate }
                proposed.append(Action(id: id, file: root.appendingPathComponent("ReminderVault Inbox.md"), line: nil, value: value(r), reminderID: r.calendarItemIdentifier, writeRemote: true, summary: "Import reminder: \(r.title ?? "task")", conflict: false, review: review(root.appendingPathComponent("ReminderVault Inbox.md"), id, nil, r, value(r))))
            }
            documents = docs; reminders = remote; remoteSnapshot = Dictionary(uniqueKeysWithValues: remote.map { ($0.calendarItemIdentifier, value($0)) })
            rows = display; actions = proposed; approval.previewSucceeded()
            status = "\(sample ? "Sample · " : "")Preview: \(proposed.count) changes. Nothing has been written."
        } catch { approval.previewFailed(); status = "Automatic sync paused: \(error.localizedDescription) Preview and apply again to resume."; actions = [] }
    }
    func apply() async {
        guard previewReady, !busy else { return }; busy = true
        defer { busy = false; approval.beginPreview() }
        do {
            guard let root = sample ? sampleRoot : folder else { throw VaultError.noFolder }
            guard try readVault(root) == documents else { throw VaultError.changed }
            let current = sample ? [] : try await fetch()
            guard Dictionary(uniqueKeysWithValues: current.map { ($0.calendarItemIdentifier, value($0)) }) == remoteSnapshot else { throw VaultError.changed }
            var updated = documents
            for action in actions where !action.summary.hasPrefix("Manual review:") {
                let text = updated[action.file] ?? ""
                if let line = action.line { updated[action.file] = try TaskText.replacing(text, line: line, value: action.value, id: action.id) }
                else { updated[action.file] = try TaskText.appended(text, value: action.value, id: action.id) }
            }
            if !sample {
                for action in actions where !action.summary.hasPrefix("Manual review:") {
                    if let rid = action.reminderID { pendingLinks[rid] = action.id }
                }
                UserDefaults.standard.set(pendingLinks, forKey: "pendingLinks")
            }
            // Save identified Markdown first. The remote marker makes retries idempotent.
            for url in updated.keys.sorted(by: { $0.path < $1.path }) where updated[url] != documents[url] {
                let existing = try? String(contentsOf: url, encoding: .utf8)
                guard existing == documents[url] else { throw VaultError.changed }
                try updated[url]!.write(to: url, atomically: true, encoding: .utf8)
            }
            for action in actions {
                if action.conflict {
                    conflictLog.insert("\(Date().formatted()): \(action.summary)\(action.summary.hasPrefix("Manual review:") ? " · deletion not propagated" : " · newest edit wins (file time versus reminder time)")", at: 0)
                    UserDefaults.standard.set(Array(conflictLog.prefix(200)), forKey: "conflicts")
                }
                if action.summary.hasPrefix("Manual review:") { continue }
                if action.writeRemote && !sample {
                    let r: EKReminder
                    if let rid = action.reminderID, let existing = current.first(where: { $0.calendarItemIdentifier == rid }) { r = existing }
                    else {
                        r = EKReminder(eventStore: store)
                        guard let list = calendars.filter({ selected.contains($0.calendarIdentifier) }).sorted(by: { $0.title < $1.title }).first else { throw VaultError.noList }
                        r.calendar = list
                    }
                    r.title = action.value.title; r.isCompleted = action.value.completed
                    if value(r).due != action.value.due {
                    r.dueDateComponents = action.value.due.flatMap { s in
                        let parts = s.split(separator: "-").compactMap { Int($0) }
                        return parts.count == 3 ? DateComponents(calendar: Calendar(identifier: .gregorian), year: parts[0], month: parts[1], day: parts[2]) : nil
                    }
                    }
                    if marker(r) == nil { r.notes = (r.notes ?? "") + "\n<!-- rv:\(action.id) -->" }
                    try store.save(r, commit: true)
                }
                if !sample { baseline.values[action.id] = action.value; try JSONEncoder().encode(baseline).write(to: stateURL, options: .atomic) }
            }
            for r in rows where !sample && !actions.contains(where: { $0.id == r.id && $0.conflict }) { baseline.values[r.id] = actions.first(where: { $0.id == r.id })?.value ?? r.value }
            if !sample { try JSONEncoder().encode(baseline).write(to: stateURL, options: .atomic) }
            rows = updated.keys.sorted(by: { $0.path < $1.path }).flatMap { url in TaskText.parse(updated[url]!).map { Row(id: $0.id ?? UUID().uuidString, file: url, line: $0.line, value: $0.value) } }
            lastSync = Date().formatted(date: .omitted, time: .shortened); UserDefaults.standard.set(Date(), forKey: "lastDate")
            approval.applySucceeded(); status = "\(sample ? "Sample · " : "")Synced at \(lastSync). \(pending) pending tasks."; actions = []
        } catch { approval.applyFailed(); status = "Sync stopped: \(error.localizedDescription) Completed writes remain; preview again to retry safely." }
    }
    func complete(_ row: Row) async {
        guard !busy else { return }
        guard sample || approved else { status = "Preview and apply the first sync before checking off tasks."; return }
        do {
            let text = try String(contentsOf: row.file, encoding: .utf8)
            guard let task = TaskText.parse(text).first(where: { $0.id == row.id }), task.value == row.value else { throw VaultError.changed }
            var v = row.value; v.completed = true
            try TaskText.replacing(text, line: task.line, value: v, id: row.id).write(to: row.file, atomically: true, encoding: .utf8)
            await preview(); if previewReady { await apply() }
        } catch { approval.applyFailed(); status = error.localizedDescription }
    }
}
