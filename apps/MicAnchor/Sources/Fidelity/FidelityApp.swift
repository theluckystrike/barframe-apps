import SwiftUI

@main struct FidelityApp: App {
    @NSApplicationDelegateAdaptor(FidelityDelegate.self) private var delegate
    @StateObject private var model = GuardModel.shared

    init() {
        if CommandLine.arguments.contains("--selftest") || CommandLine.arguments.contains("--smoke") {
            exit(runSelftest())
        }
        if CommandLine.arguments.contains("--screenshots") {
            do { try renderScreenshots(to: NSHomeDirectory() + "/screenshots"); exit(0) }
            catch { exit(1) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-screenshots") {
            guard CommandLine.arguments.count > index + 1 else { exit(2) }
            do {
                try renderScreenshots(to: CommandLine.arguments[index + 1])
                exit(0)
            } catch {
                fputs("Screenshot error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            GuardPopover(model: model).task { model.start() }
        } label: {
            Image(systemName: model.glyph).accessibilityLabel("MicAnchor: \(model.status)")
                .task { model.start() }
        }.menuBarExtraStyle(.window)
        Settings { GuardSettingsView(model: model) }
            .commands {
                CommandGroup(replacing: .appInfo) { Button("About MicAnchor") { showAbout() } }
                CommandGroup(replacing: .appTermination) { Button("Quit MicAnchor") { NSApp.terminate(nil) }.keyboardShortcut("q") }
            }
    }
}

@MainActor final class FidelityDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GuardModel.shared.start()
    }
}
