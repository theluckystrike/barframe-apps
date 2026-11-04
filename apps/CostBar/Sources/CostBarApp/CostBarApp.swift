import SwiftUI
import AppKit
import MASKit
import CostBarCore
import UserNotifications

@main
struct CostBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel
    private let mode: LaunchMode
    init() {
        mode = LaunchMode.current()
        _model = StateObject(wrappedValue: AppModel.shared)
    }
    var body: some Scene {
        MenuBarExtra(isInserted: .constant(mode == .normal && !AccountsLaunch.sampleRequested())) {
                PopoverView(model: model)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chart.bar.fill").renderingMode(.template).font(.system(size: 16))
                    if model.sample { Text("Sample") }
                    else if let snapshot = model.snapshot { Text(Money.short(snapshot.monthlyUSD)) }
                }.accessibilityLabel("CostBar, \(model.sample ? "Sample, " : "")\(model.snapshot.map { Money.string($0.monthlyUSD) + " this month" } ?? model.state)")
            }.menuBarExtraStyle(.window)
                .commands {
                    CommandGroup(replacing: .appSettings) {
                        Button("CostBar Settings…") { model.openSettings() }.keyboardShortcut(",", modifiers: .command)
                        Button("Accounts & Credits…") { AccountsModel.shared.openWindow() }.keyboardShortcut("a", modifiers: [.command, .shift])
                    }
                }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated static var foregroundOptions: UNNotificationPresentationOptions { [.banner, .sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Self.foregroundOptions)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        let mode = LaunchMode.current()
        switch mode {
        case .normal:
            if AccountsLaunch.handle(open: { NSApp.setActivationPolicy(.regular); AccountsModel.shared.openWindow() }) { break }
            AppModel.shared.start(); AccountsModel.shared.start()
        case .smoke:
            Task { await Verification.smoke() }
        case .screenshots:
            do { try Verification.screenshots(); exit(0) }
            catch { fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.stop(); AccountsModel.shared.stop() }
}
