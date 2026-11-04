import Foundation

public enum BookmarkError: Error, Equatable, LocalizedError {
    case missing
    case unresolvable(String)
    public var errorDescription: String? {
        switch self {
        case .missing: return "Missing file. Restore the original or remove this item."
        case .unresolvable: return "File permission unavailable. Remove this item and drop the original again."
        }
    }
}
/// Owns a security scope for the complete preview, sharing, or drag operation.
public final class BookmarkAccess {
    public let url: URL
    public let isDirectory: Bool
    public let refreshedBookmark: Data?
    private let scoped: Bool
    public init(url: URL, stale: Bool = false) throws {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw BookmarkError.missing
        }
        isDirectory = directory.boolValue
        do { refreshedBookmark = stale ? try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) : nil }
        catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw BookmarkError.unresolvable(error.localizedDescription)
        }
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}
public enum BookmarkResolver {
    public static func access(_ bookmark: Data) -> Result<BookmarkAccess, BookmarkError> {
        guard !bookmark.isEmpty else { return .failure(.unresolvable("Empty reference")) }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            return .success(try BookmarkAccess(url: url, stale: stale))
        } catch let error as BookmarkError { return .failure(error) }
        catch { return .failure(.unresolvable(error.localizedDescription)) }
    }
    public static func resolve(_ bookmark: Data) -> Result<(URL, String, Bool), BookmarkError> {
        access(bookmark).map { ($0.url, $0.url.lastPathComponent, $0.isDirectory) }
    }
    public static func make(for url: URL, readOnly: Bool = false) -> Result<Data, BookmarkError> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.missing) }
            let options: URL.BookmarkCreationOptions = readOnly ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess] : [.withSecurityScope]
            return .success(try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil))
        } catch { return .failure(.unresolvable(error.localizedDescription)) }
    }
}
public enum ShelfOrdering {
    public static func newestFirst(_ items: [ShelfItem]) -> [ShelfItem] { items.sorted { $0.addedAt > $1.addedAt } }
    public static func byName(_ items: [ShelfItem]) -> [ShelfItem] { items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    public static func matching(_ items: [ShelfItem], query: String) -> [ShelfItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
public enum SampleShelf {
    public static let sampleNames = ["Quarterly-notes.txt", "Design-tokens.json", "Team-photo.png", "Project-brief.md", "Invoices-2026.csv"]
    public static func items(now: Date = Date()) -> [ShelfItem] {
        sampleNames.enumerated().map { index, name in
            ShelfItem(bookmark: Data(), name: name, isDirectory: false, isText: true, addedAt: now.addingTimeInterval(TimeInterval(-60 * (index + 1))), text: "Sample: " + name)
        }
    }
}
