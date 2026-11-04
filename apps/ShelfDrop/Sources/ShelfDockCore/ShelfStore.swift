import Foundation
import Combine

public struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var bookmark: Data
    public let name: String
    public let isDirectory: Bool
    public let isText: Bool
    public let addedAt: Date
    public var groupID: UUID?
    public let text: String?
    public let imageData: Data?
    public let imageType: String?
    public init(id: UUID = UUID(), bookmark: Data, name: String, isDirectory: Bool, isText: Bool, addedAt: Date = Date(), groupID: UUID? = nil, text: String? = nil, imageData: Data? = nil, imageType: String? = nil) {
        self.id = id; self.bookmark = bookmark; self.name = name
        self.isDirectory = isDirectory; self.isText = isText; self.addedAt = addedAt
        self.groupID = groupID; self.text = text; self.imageData = imageData; self.imageType = imageType
    }
}
public struct ShelfGroup: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}
public enum ShelfLimits {
    public static let maxItems = 40
    public static let maxNameLength = 120
}
public struct DropCandidate: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case fileURL(String), text(String) }
    public let kind: Kind
    public init(_ kind: Kind) { self.kind = kind }
}
public enum ShelfAcceptor {
    public static func classify(_ candidate: DropCandidate) -> String? {
        switch candidate.kind {
        case .fileURL(let path):
            guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? nil : String(name.prefix(ShelfLimits.maxNameLength))
        case .text(let text):
            let title = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return title.isEmpty ? nil : String(title.prefix(ShelfLimits.maxNameLength))
        }
    }
}
private struct ShelfSnapshot: Codable {
    var items: [ShelfItem]
    var groups: [ShelfGroup]
    var cleared: [ShelfItem]
}
@MainActor
public final class ShelfStore: ObservableObject {
    @Published public private(set) var items: [ShelfItem] = []
    @Published public private(set) var groups: [ShelfGroup] = [ShelfGroup(name: "All")]
    @Published public private(set) var lastError: String?
    @Published public var clearAfterDragOut: Bool {
        didSet { defaults?.set(clearAfterDragOut, forKey: "clearAfterDragOut") }
    }
    @Published public private(set) var recentlyClearedIDs: [UUID] = []
    private var cleared: [ShelfItem] = []
    private let defaults: UserDefaults?
    public init(defaults: UserDefaults? = .standard, clearAfterDragOut: Bool? = nil) {
        self.defaults = defaults
        self.clearAfterDragOut = clearAfterDragOut ?? (defaults?.object(forKey: "clearAfterDragOut") as? Bool) ?? false
        if let data = defaults?.data(forKey: "shelfSnapshot"), let saved = try? JSONDecoder().decode(ShelfSnapshot.self, from: data), !saved.groups.isEmpty {
            items = saved.items; groups = saved.groups; cleared = saved.cleared
            recentlyClearedIDs = cleared.map(\.id)
        }
        defaults?.set(self.clearAfterDragOut, forKey: "clearAfterDragOut")
    }
    private func persist() {
        guard let defaults else { return }
        do { defaults.set(try JSONEncoder().encode(ShelfSnapshot(items: items, groups: groups, cleared: cleared)), forKey: "shelfSnapshot") }
        catch { lastError = "Could not save shelf: \(error.localizedDescription)" }
    }
    public var isDefaultGroup: Bool { groups.count <= 1 }
    public func items(in group: ShelfGroup) -> [ShelfItem] { group.id == groups[0].id ? items : items.filter { $0.groupID == group.id } }
    public func group(named name: String) -> ShelfGroup? { groups.first { $0.name == name } }
    private func validGroup(_ id: UUID?) -> UUID? { id.flatMap { id in groups.dropFirst().first(where: { $0.id == id })?.id } }
    @discardableResult public func add(_ candidate: DropCandidate, bookmark: Data = Data(), isDirectory: Bool = false, isText: Bool = false, groupID: UUID? = nil) -> String? {
        guard let name = ShelfAcceptor.classify(candidate) else { return reject("Nothing usable in that drop.") }
        var text: String?
        switch candidate.kind {
        case .text(let value): text = value
        case .fileURL:
            guard !isText, !bookmark.isEmpty else { return reject("File permission could not be saved. Drop the original file again.") }
        }
        let item = ShelfItem(bookmark: bookmark, name: name, isDirectory: isDirectory, isText: text != nil, groupID: validGroup(groupID), text: text)
        return append(item)
    }
    private func append(_ item: ShelfItem) -> String? {
        guard items.count < ShelfLimits.maxItems else { return reject("The shelf is full (\(ShelfLimits.maxItems) items). Remove something first.") }
        guard !items.contains(where: { $0.bookmark == item.bookmark && $0.text == item.text && $0.imageData == item.imageData && $0.name == item.name }) else { return reject("Already on the shelf.") }
        items.append(item); lastError = nil; persist(); return nil
    }
    @discardableResult public func addText(_ text: String, groupID: UUID? = nil) -> String? { add(.init(.text(text)), isText: true, groupID: groupID) }
    @discardableResult public func addFile(path: String, bookmark: Data, isDirectory: Bool, groupID: UUID? = nil) -> String? { add(.init(.fileURL(path)), bookmark: bookmark, isDirectory: isDirectory, groupID: groupID) }
    @discardableResult public func addImage(_ data: Data, type: String, groupID: UUID? = nil) -> String? {
        guard !data.isEmpty else { return reject("That image could not be read.") }
        return append(ShelfItem(bookmark: Data(), name: "Image", isDirectory: false, isText: false, groupID: validGroup(groupID), imageData: data, imageType: type))
    }
    private func reject(_ message: String) -> String { lastError = message; return message }
    public func fail(_ message: String) { lastError = message }
    public func remove(id: UUID) { items.removeAll { $0.id == id }; cleared.removeAll { $0.id == id }; recentlyClearedIDs = cleared.map(\.id); lastError = nil; persist() }
    public func moveToGroup(id: UUID, group: ShelfGroup?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].groupID = validGroup(group?.id); persist()
    }
    public func refreshBookmark(id: UUID, data: Data) {
        guard !data.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].bookmark = data; persist()
    }
    @discardableResult public func createGroup(named name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return reject("Group name is empty.") }
        guard name.count <= 40 else { return reject("Group name is too long.") }
        guard !groups.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return reject("A group with that name already exists.") }
        groups.append(ShelfGroup(name: name)); lastError = nil; persist(); return nil
    }
    public func deleteGroup(_ group: ShelfGroup) {
        guard group.id != groups[0].id else { fail("The default group cannot be deleted."); return }
        for index in items.indices where items[index].groupID == group.id { items[index].groupID = nil }
        groups.removeAll { $0.id == group.id }; lastError = nil; persist()
    }
    /// Only the native dragging-session completion callback calls this method.
    public func dragOutEnded(id: UUID, accepted: Bool) { if accepted { dragOutCompleted(id: id) } }
    public func dragOutCompleted(id: UUID) {
        if clearAfterDragOut, let item = items.first(where: { $0.id == id }) {
            cleared.append(item); recentlyClearedIDs = cleared.map(\.id); items.removeAll { $0.id == id }; persist()
        }
        lastError = nil
    }
    public func restoreRecentlyCleared() {
        let room = max(0, ShelfLimits.maxItems - items.count)
        let restored = Array(cleared.suffix(room))
        items.append(contentsOf: restored); let ids = Set(restored.map(\.id)); cleared.removeAll { ids.contains($0.id) }
        recentlyClearedIDs = cleared.map(\.id); lastError = nil; persist()
    }
    public func clearAll(in group: ShelfGroup? = nil) {
        if let group, group.id != groups[0].id { items.removeAll { $0.groupID == group.id } } else { items.removeAll() }
        cleared.removeAll(); recentlyClearedIDs.removeAll(); lastError = nil; persist()
    }
    public var emptyStateMessage: String { lastError ?? "Drop files, folders, text, or images onto this open shelf window." }
}
