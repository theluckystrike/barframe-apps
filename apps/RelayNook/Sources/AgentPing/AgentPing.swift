import SwiftUI
import UserNotifications

@main struct AgentPingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    init() {
        if CommandLine.arguments.contains("--verification-reset-history") { AppModel.shared.clear() }
        if CommandLine.arguments.contains("--screenshots") { Runtime.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")) }
        if CommandLine.arguments.contains("--smoke") { Runtime.selftest() }
        if CommandLine.arguments.contains("--selftest") { Runtime.selftest() }
        if let index = CommandLine.arguments.firstIndex(of: "--render-screenshots"), CommandLine.arguments.count > index + 1 {
            Runtime.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        }
    }
    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.history.waitingCount == 0 ? "waveform.path" : "hourglass")
                if model.history.waitingCount > 0 { Text("\(model.history.waitingCount)").monospacedDigit() }
            }.accessibilityLabel("RelayNook: \(model.history.waitingCount) waiting")
        }.menuBarExtraStyle(.window)
        Settings { SettingsView(model: model) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        AppModel.shared.refreshNotificationStatus()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.beginShutdown()
        Task {
            await AppModel.shared.flushHistory()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.setSampleMode(false)
        for url in urls { AppModel.shared.receive(url) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
