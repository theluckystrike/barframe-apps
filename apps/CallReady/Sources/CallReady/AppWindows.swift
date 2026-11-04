import AppKit
import SwiftUI
import CallCore

/// The Settings window and the menu-in-a-window. Both work when macOS hides the menu bar item,
/// for example on a full menu bar next to the camera housing.
@MainActor enum AppWindows {
    private static var settings: NSWindow?
    private static var menu: NSWindow?

    static func showSettings(_ given: CallCoordinator? = nil) {
        let app = given ?? .live
        let window = settings ?? make(title: "CallReady Settings",
            view: CallSettingsView(app: app, calendar: app.calendar, microphone: app.microphone, mute: app.mute))
        settings = window
        present(window)
    }

    /// The same content as the menu bar window, in a normal window.
    static func showMenuWindow(_ given: CallCoordinator? = nil) {
        let app = given ?? .live
        let window = menu ?? make(title: "CallReady",
            view: CallMenuView(app: app, calendar: app.calendar, microphone: app.microphone, mute: app.mute))
        menu = window
        present(window)
    }

    /// Closes and forgets both windows.
    static func closeAll() {
        settings?.close(); menu?.close()
        settings = nil; menu = nil
    }

    static var settingsWindow: NSWindow? { settings }
    static var menuWindow: NSWindow? { menu }

    private static func make<V: View>(title: String, view: V) -> NSWindow {
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private static func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// One running copy per user. A second copy hands over to the first and quits, so only one copy owns
/// the mute shortcut and shows the mute state.
enum SingleInstance {
    struct Copy: Equatable { let pid: Int32; let launched: Date? }

    /// True when another copy started earlier (or at the same time with a lower process id).
    static func shouldYield(me: Copy, others: [Copy]) -> Bool {
        others.contains { other in
            guard other.pid != me.pid else { return false }
            switch (other.launched, me.launched) {
            case let (o?, m?): return o < m || (o == m && other.pid < me.pid)
            default: return other.pid < me.pid
            }
        }
    }

    /// Activates the earlier copy and returns true when this copy must quit.
    @MainActor static func yieldToRunningCopy() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let mine = NSRunningApplication.current
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
        let me = Copy(pid: mine.processIdentifier, launched: mine.launchDate)
        let others = running.map { Copy(pid: $0.processIdentifier, launched: $0.launchDate) }
        guard shouldYield(me: me, others: others),
              let first = running.first(where: { $0.processIdentifier != me.pid }) else { return false }
        // Opening the running copy again makes it show Settings (applicationShouldHandleReopen).
        if let url = first.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            first.activate()
        }
        return true
    }
}
