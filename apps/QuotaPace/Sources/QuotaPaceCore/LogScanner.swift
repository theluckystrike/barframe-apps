import Foundation

public struct ScanResult: Sendable {
    public let samples: [TokenSample]
    public let files: Int
    public let malformedLines: Int
    public let warnings: [String]
}
private struct FileCursor {
    var identity: String
    var modifiedAt: Date?
    var offset: UInt64 = 0
    var tail = Data()
    var droppingLine = false
    var oversizedLines = 0
    var parser: JSONLParser
}
/// Incremental file reader: no whole-file loads, no subprocesses, no symlink traversal.
public final class LogScanner {
    private var cursors: [String: FileCursor] = [:]
    public init() {}
    public func scan(folder: URL, provider: Provider, minimumDate: Date? = nil) throws -> ScanResult {
        let manager = FileManager.default
        let folderValues = try folder.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard folderValues.isDirectory == true else { throw UsageError.notDirectory }
        var warnings: [String] = []
        guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .fileResourceIdentifierKey, .contentModificationDateKey], options: [.skipsPackageDescendants], errorHandler: { url, error in
            warnings.append("\(url.lastPathComponent): \(error.localizedDescription)"); return true
        }) else { throw CocoaError(.fileReadNoPermission) }
        var seen = Set<String>()
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            let values: URLResourceValues
            do { values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .fileResourceIdentifierKey, .contentModificationDateKey]) }
            catch { warnings.append("\(file.lastPathComponent): \(error.localizedDescription)"); continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true, file.pathExtension.lowercased() == "jsonl" else { continue }
            if seen.count >= 20000 { warnings.append("The folder contains more than 20,000 log files; choose a smaller folder."); break }
            let key = "\(provider.rawValue):\(file.path)"
            seen.insert(key)
            let identity = String(describing: values.fileResourceIdentifier)
            var cursor = cursors[key] ?? FileCursor(identity: identity, modifiedAt: values.contentModificationDate, parser: JSONLParser(provider: provider, sourceID: file.path, minimumDate: minimumDate))
            if cursor.identity != identity || cursor.modifiedAt != values.contentModificationDate || UInt64(values.fileSize ?? 0) < cursor.offset {
                cursor = FileCursor(identity: identity, modifiedAt: values.contentModificationDate, parser: JSONLParser(provider: provider, sourceID: file.path, minimumDate: minimumDate))
            }
            cursor.parser.retainUsage(since: minimumDate)
            do {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                try handle.seek(toOffset: cursor.offset)
                while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                    try Task.checkCancellation()
                    cursor.offset += UInt64(chunk.count)
                    for byte in chunk {
                        if byte == 10 {
                            if !cursor.droppingLine { cursor.parser.ingest(cursor.tail) }
                            cursor.tail.removeAll(keepingCapacity: true)
                            cursor.droppingLine = false
                        } else if !cursor.droppingLine {
                            cursor.tail.append(byte)
                            if cursor.tail.count > 4 * 1024 * 1024 {
                                cursor.tail.removeAll(keepingCapacity: false)
                                cursor.droppingLine = true
                                cursor.oversizedLines += 1
                            }
                        }
                    }
                }
                cursors[key] = cursor
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("\(file.lastPathComponent): \(error.localizedDescription)") }
        }
        // Removed logs stop contributing. Each provider has its own scanner instance.
        cursors = cursors.filter { seen.contains($0.key) }
        var deduplicated: [String: TokenSample] = [:]
        var malformed = 0
        for cursor in cursors.values {
            var parser = cursor.parser
            // A valid final JSON object without a newline contributes provisionally.
            // Keep the real cursor unchanged so a later append is parsed exactly once.
            if !cursor.tail.isEmpty, !cursor.droppingLine,
               (try? JSONSerialization.jsonObject(with: cursor.tail)) != nil {
                parser.ingest(cursor.tail)
            }
            malformed += parser.malformedLines + cursor.oversizedLines
            for (id, sample) in parser.samples {
                if let old = deduplicated[id] {
                    deduplicated[id] = TokenSample(id: id, date: min(old.date, sample.date), tokens: max(old.tokens, sample.tokens))
                } else { deduplicated[id] = sample }
            }
        }
        return ScanResult(samples: Array(deduplicated.values), files: seen.count, malformedLines: malformed, warnings: Array(warnings.prefix(5)))
    }
}

public struct FolderGrant: Codable, Equatable, Sendable {
    public let bookmark: Data
    public let name: String
    public init(url: URL) throws {
        bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        name = url.lastPathComponent
    }
    public func resolve() throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
}
public actor ScanService {
    private var scanners: [Provider: LogScanner] = [.claude: LogScanner(), .codex: LogScanner()]
    public init() {}
    public func clear(provider: Provider) { scanners[provider] = LogScanner() }
    public func scan(grant: FolderGrant, provider: Provider, now: Date = Date()) throws -> (ScanResult, FolderGrant?) {
        let resolved = try grant.resolve()
        let accessing = resolved.url.startAccessingSecurityScopedResource()
        defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }
        // Container folders already have access and can return false here.
        // Filesystem reads below enforce permission and throw if the grant is unusable.
        let refreshed = resolved.stale ? try FolderGrant(url: resolved.url) : nil
        return (try scanners[provider]!.scan(folder: resolved.url, provider: provider, minimumDate: now.addingTimeInterval(-7 * 86400)), refreshed)
    }
}
