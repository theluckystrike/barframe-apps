import Foundation

/// Serial work preserves hardware order. Cancellation invalidates queued work and results.
final class AudioWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CallReady.audio", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    func cancel() { lock.lock(); generation += 1; lock.unlock() }
    private func current() -> Int { lock.lock(); defer { lock.unlock() }; return generation }
    func submit<Value>(_ operation: @escaping () throws -> Value,
                       completion: @escaping (Result<Value, Error>) -> Void) {
        let token = current()
        queue.async { [self] in
            guard current() == token else { return }
            let result = Result { try operation() }
            DispatchQueue.main.async { [self] in
                guard current() == token else { return }
                completion(result)
            }
        }
    }
}
