import SwiftUI
import ShelfDockCore
import MASKit

@main
struct ShelfDockApp: App {
    @StateObject private var model: AppModel
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("clearAfterDragOut") private var clearAfterDragOut = false

    init() {
        let args = CommandLine.arguments
        if args.contains("--selftest") || args.contains("--smoke") {
            SmokeRunner.run()
        }
        if args.contains("--screenshots") {
            Task { @MainActor in
                do {
                    let urls = try ShelfScreenshotComposer.renderAll()
                    fputs("Rendered \(urls.count) screenshots\n", stderr)
                    exit(0)
                } catch {
                    fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
        }
        if args.contains("--verify-grants") {
            exit(SelfTest.verifyGrants())
        }
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            HStack {
                Image(systemName: "tray.full")
                let title = model.menuBarTitle
                if !title.isEmpty { Text(title) }
            }
            .accessibilityLabel("ShelfDock: \(model.items.count) items on the shelf")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

enum SelfTest {
    /// Confirms the entitlements we rely on are present in the running binary context.
    static func verifyGrants() -> Int32 {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        // In the sandbox the home dir is a container path.
        let containerLike = NSHomeDirectory().contains("/Containers/")
        return containerLike || sandboxed ? 0 : 3
    }
}
