import SwiftUI
import AppKit
import MASKit
import PortSenseCore

@main
struct PortSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppState
    init() {
        // Resolve the launch mode before constructing any UI or sampling timers.
        let mode = LaunchMode.current()
        if mode == .smoke { SmokeRunner.run() }
        let state = AppState()
        if mode == .normal { state.start() }
        _model = StateObject(wrappedValue: state)
    }
    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .tint(Color(red: 100 / 255, green: 210 / 255, blue: 1))
                .accentColor(Color(red: 100 / 255, green: 210 / 255, blue: 1))
                .onAppear { model.start(); model.refresh() }
        } label: {
            Label {
                Text(model.menuText)
            } icon: {
                Image(systemName: model.verdict.isWarning ? "exclamationmark.triangle" : "cable.connector")
                .font(.system(size: 16))
                .symbolRenderingMode(.monochrome)
                .foregroundColor(model.verdict.isWarning ? .orange : nil)
            }
            .accessibilityLabel(model.statusAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if LaunchMode.current() == .screenshots {
            Task { @MainActor in
                do {
                    let model = AppState(usePreferences: false)
                    model.setSample(true)
                    let accent = Color(red: 100 / 255, green: 210 / 255, blue: 1)
                    model.selectedTab = .power
                    try PortScreenshotComposer.render(index: 1, headline: "Know your charger’s capacity", subheadline: "Sample charger rating and raw battery capacity.", accent: accent) {
                        PopoverView(model: model).tint(accent).accentColor(accent)
                    }
                    model.selectedTab = .connections
                    try PortScreenshotComposer.render(index: 2, headline: "See the link behind the cable", subheadline: "Sample USB link ceilings and current limits.", accent: accent) {
                        PopoverView(model: model).tint(accent).accentColor(accent)
                    }
                    model.selectedTab = .history
                    try PortScreenshotComposer.render(index: 3, headline: "Watch charger capacity change", subheadline: "Sample history shows capacity changes and failed reads.", accent: accent) {
                        PopoverView(model: model).tint(accent).accentColor(accent)
                    }
                    exit(0)
                } catch {
                    fputs("Screenshot rendering failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
        }
    }
}
