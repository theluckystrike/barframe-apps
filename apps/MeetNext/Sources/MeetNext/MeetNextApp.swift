import SwiftUI
import Darwin
import MASKit
import MeetNextCore

@main
struct MeetNextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model: AppModel

    init() {
        let args = CommandLine.arguments
        if args.contains("--smoke") { exit(SelfTest.run(writeSmoke: true)) }
        if args.contains("--screenshots") {
            do {
                try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots"))
                exit(0)
            } catch {
                fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        if let index = args.firstIndex(of: "--render-screenshots"), index + 1 < args.count {
            do {
                try ScreenshotRenderer.render(to: URL(fileURLWithPath: args[index + 1]))
                exit(0)
            } catch {
                fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    appDelegate.model = model
                }
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel? { didSet { updateTitle() } }
    private(set) var statusItem: NSStatusItem?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.target = self
        item.button?.action = #selector(toggleWindow)
        statusItem = item
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        updateTitle()
    }

    func applicationDidBecomeActive(_ notification: Notification) { model?.becameActive() }

    @objc private func toggleWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @MainActor func updateTitle() {
        statusItem?.button?.title = model?.menuBarTitle ?? "MeetNext"
    }
}
