import Foundation

/// Keep one pending snapshot. Serialize encoding and atomic writes on a private queue.
public final class HistoryPersistence: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "RelayNook.history", qos: .utility)
    private let url: URL
    private let writer: @Sendable (History, URL) throws -> Void
    private var pending: History?
    private var scheduled: UUID?
    public var onError: (@Sendable (String) -> Void)?

    public init(url: URL, writer: @escaping @Sendable (History, URL) throws -> Void = { try $0.save(to: $1) }) {
        self.url = url
        self.writer = writer
    }
    public func submit(_ snapshot: History) {
        lock.lock(); defer { lock.unlock() }
        pending = snapshot
        scheduleLocked()
    }
    private func scheduleLocked() {
        guard pending != nil, scheduled == nil else { return }
        let identifier = UUID()
        scheduled = identifier
        // Use a fixed interval so a continuous burst cannot postpone persistence indefinitely.
        queue.asyncAfter(deadline: .now() + 0.5) { self.drain(expected: identifier) }
    }
    private func drain(expected: UUID?, throughPending: Bool = false) {
        lock.lock()
        if let expected, scheduled != expected { lock.unlock(); return }
        while let snapshot = pending {
            pending = nil
            lock.unlock()
            do { try writer(snapshot, url) }
            catch { onError?(error.localizedDescription) }
            lock.lock()
            if !throughPending { break }
        }
        scheduled = nil
        scheduleLocked()
        lock.unlock()
    }
    public func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { self.drain(expected: nil, throughPending: true); continuation.resume() }
        }
    }
}
