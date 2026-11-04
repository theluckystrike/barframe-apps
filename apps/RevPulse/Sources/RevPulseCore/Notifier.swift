import Foundation
import UserNotifications

/// Delivers the first-sale and failed-payment notifications.
public enum Notifier {
    @MainActor
    public static func post(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .notDetermined else { return }
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "revpulse.\(UUID().uuidString)", content: content, trigger: nil)
        try? await center.add(request)
    }
}
