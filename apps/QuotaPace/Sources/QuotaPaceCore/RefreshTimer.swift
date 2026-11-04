import Foundation

/// Owns the run-loop timer so it cannot outlive the refresh session.
public final class RefreshTimer {
    private var timer: Timer?
    public init() {}
    public var isRunning: Bool { timer?.isValid == true }
    public func start(interval: TimeInterval = 30, action: @escaping () -> Void) {
        guard !isRunning else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in action() }
    }
    public func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
