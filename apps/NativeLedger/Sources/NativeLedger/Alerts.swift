import Foundation
import UserNotifications
import LedgerCore

enum AlertAuthorization: Equatable, Sendable {
    case granted
    case denied
    /// This copy cannot use notifications, for example a bare executable outside an app bundle.
    case unavailable
}

/// The seam over UNUserNotificationCenter. Tests use a fake.
protocol NotificationPosting: Sendable {
    func requestAuthorization() async -> AlertAuthorization
    func post(identifier: String, title: String, body: String)
}

/// One local notification for an automatic entry.
struct AlertNote: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

/// The Settings toggle "Alert me about high-severity changes" and the notifications it allows. Off by default.
@MainActor
final class AlertController: ObservableObject {
    static let enabledKey = "NativeLedger.alertsEnabled"
    static let deniedMessage = "Notifications are not allowed for NativeLedger, so the alert setting was turned off. Open System Settings, choose Notifications, select NativeLedger and turn on Allow notifications."
    static let unavailableMessage = "Notifications are not available in this copy of NativeLedger, so the alert setting was turned off."

    @Published private(set) var enabled: Bool
    @Published private(set) var message = ""
    @Published private(set) var requesting = false
    private let poster: NotificationPosting
    private let defaults: UserDefaults

    init(poster: NotificationPosting, defaults: UserDefaults = .standard) {
        self.poster = poster; self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Turning the toggle on asks for notification permission. A refusal turns it off again and says why.
    func setEnabled(_ on: Bool) async {
        guard on else {
            enabled = false; message = ""
            defaults.set(false, forKey: Self.enabledKey)
            return
        }
        requesting = true
        enabled = true
        let answer = await poster.requestAuthorization()
        requesting = false
        switch answer {
        case .granted:
            enabled = true; message = ""
        case .denied:
            enabled = false; message = Self.deniedMessage
        case .unavailable:
            enabled = false; message = Self.unavailableMessage
        }
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    /// The notification for one entry, or nil when it has no high-severity anomaly. The text names the app and
    /// the anomaly and holds no path.
    nonisolated static func note(for recorded: RecordedEntry) -> AlertNote? {
        let high = Anomaly.bySeverity(recorded.entry.anomalies).filter(\.isHighSeverity)
        guard !high.isEmpty else { return nil }
        let name = PathScreen.looksLikePath(recorded.displayName) ? "An app" : recorded.displayName
        let labels = ListFormatter.localizedString(byJoining: high.map(\.label))
        return AlertNote(identifier: "nativeledger.\(recorded.ledgerID.uuidString).\(recorded.entry.seq)",
                         title: name,
                         body: "\(labels) in entry \(recorded.entry.seq). Open NativeLedger to review the change.")
    }

    /// Posts one notification per automatic entry with a high-severity anomaly, only while the toggle is on.
    @discardableResult
    func handle(_ entries: [RecordedEntry]) -> [AlertNote] {
        guard enabled else { return [] }
        let notes = entries.compactMap(Self.note(for:))
        for note in notes { poster.post(identifier: note.identifier, title: note.title, body: note.body) }
        return notes
    }
}

/// UNUserNotificationCenter. It is used only inside an app bundle, where the center is available.
final class SystemNotifier: NSObject, NotificationPosting, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static var isSupported: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    private func center() -> UNUserNotificationCenter? {
        guard Self.isSupported else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }
    func requestAuthorization() async -> AlertAuthorization {
        guard let center = center() else { return .unavailable }
        do { return try await center.requestAuthorization(options: [.alert, .sound]) ? .granted : .denied }
        catch { return .denied }
    }
    func post(identifier: String, title: String, body: String) {
        guard let center = center() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
    /// Shows the banner while NativeLedger is the active app too.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
