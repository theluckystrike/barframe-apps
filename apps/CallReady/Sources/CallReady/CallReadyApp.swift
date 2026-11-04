import SwiftUI
import CallCore

@main struct CallReadyApp: App {
    @NSApplicationDelegateAdaptor(CallReadyDelegate.self) private var delegate
    @StateObject private var app = CallCoordinator.live

    var body: some Scene {
        MenuBarExtra {
            CallMenuView(app: app, calendar: app.calendar, microphone: app.microphone, mute: app.mute)
        } label: {
            MenuBarLabel(app: app, mute: app.mute)
        }.menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var app: CallCoordinator
    @ObservedObject var mute: MuteModel
    var body: some View {
        let muted = mute.muteState() == true && !mute.pttActive
        HStack(spacing: 4) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
            if !app.menuBarText.isEmpty { Text(app.menuBarText) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CallReady: \(app.status)")
        .task { if !CallReadyDelegate.yielding { app.start() } }
    }
}

@MainActor final class CallReadyDelegate: NSObject, NSApplicationDelegate {
    /// True when another copy is already running. This copy hands over and quits.
    static private(set) var yielding = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.yielding = SingleInstance.yieldToRunningCopy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.yielding { NSApp.terminate(nil); return }
        var showWelcome = !UserDefaults.standard.bool(forKey: "welcomeShown")
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(CalendarModel.demoArgument) { CallCoordinator.live.calendar.useDemoEvent() }
        if arguments.contains(GuardModel.skipIntroArgument) {
            CallCoordinator.live.microphone.hideIntroductionForDemo()
            showWelcome = false
        }
        if arguments.contains(GuardModel.hideContinuityArgument) { GuardModel.hideContinuityForDemo = true }
        #endif
        CallCoordinator.live.start()
        if showWelcome {
            // The menu bar item can be hidden on a full menu bar. The first launch always shows a window.
            UserDefaults.standard.set(true, forKey: "welcomeShown")
            AppWindows.showSettings()
        }
    }

    /// Opening CallReady again (Finder, Launchpad, Spotlight) shows Settings, so the app is never invisible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Self.yielding { AppWindows.showSettings() }
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !Self.yielding { CallCoordinator.live.calendar.becameActive() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !Self.yielding { CallCoordinator.live.stop() }
    }
}
