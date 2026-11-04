import Foundation

public enum LedgerStoreError: Error, Equatable { case writesPaused, notLoaded }

public enum LedgerLoad: Equatable, Sendable {
    case loaded([AppLedger])
    /// The file exists but cannot be decoded. Its bytes are untouched and ordinary writes are paused.
    case corrupt
}

private struct LedgerEnvelope: Codable { var schema: Int; var ledgers: [AppLedger] }

/// Atomic persistence for ledgers.json. It never overwrites unreadable data on an ordinary save.
public final class LedgerStore: @unchecked Sendable {
    public static let schema = 2
    public static let fileName = "ledgers.json"
    private let lock = NSLock()
    private let file: URL
    private var loaded = false
    private var paused = false
    public init(directory: URL) { file = directory.appendingPathComponent(Self.fileName) }
    public var writesPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    public var fileURL: URL { file }

    public func load() -> LedgerLoad {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: file.path) else { loaded = true; paused = false; return .loaded([]) }
        do {
            let envelope = try LedgerCoding.decoder().decode(LedgerEnvelope.self, from: Data(contentsOf: file))
            guard envelope.schema == Self.schema,
                  Set(envelope.ledgers.map(\.id)).count == envelope.ledgers.count else { throw CocoaError(.fileReadCorruptFile) }
            loaded = true; paused = false
            return .loaded(envelope.ledgers)
        } catch {
            loaded = false; paused = true
            return .corrupt
        }
    }
    /// Non-destructive retry. Writes resume only if the file is now valid.
    public func retry() -> LedgerLoad { load() }

    public func save(_ ledgers: [AppLedger]) throws {
        lock.lock(); defer { lock.unlock() }
        guard !paused else { throw LedgerStoreError.writesPaused }
        guard loaded else { throw LedgerStoreError.notLoaded }
        try writeLocked(ledgers)
    }
    private func writeLocked(_ ledgers: [AppLedger]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LedgerCoding.encoder().encode(LedgerEnvelope(schema: Self.schema, ledgers: ledgers)).write(to: file, options: .atomic)
    }
    /// Explicit recovery. The unreadable bytes are copied to a new file first, then an empty store is written.
    @discardableResult
    public func recoverByStartingFresh() throws -> URL? {
        lock.lock(); defer { lock.unlock() }
        var preserved: URL?
        if FileManager.default.fileExists(atPath: file.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let copy = file.deletingLastPathComponent().appendingPathComponent("ledgers.corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).json")
            try FileManager.default.copyItem(at: file, to: copy)
            preserved = copy
        }
        try writeLocked([])
        loaded = true; paused = false
        return preserved
    }
}
