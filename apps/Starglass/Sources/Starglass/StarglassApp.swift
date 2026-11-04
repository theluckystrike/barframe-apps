import SwiftUI
import StarglassCore

@main
struct StarglassApp: App {
    @StateObject private var model: AppModel
    @AppStorage("showScore") private var showScore = true

    init() {
        let args = CommandLine.arguments
        if args.contains("--selftest") || args.contains("--smoke") { exit(SelfTest.run(writeSmoke: args.contains("--smoke"))) }
        if args.contains("--verify-grants") { exit(SelfTest.verifyGrants()) }
        if args.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let index = args.firstIndex(of: "--render-screenshots"), index + 1 < args.count {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: args[index + 1])); exit(0) }
            catch { fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            HStack {
                Image(systemName: "moon.stars")
                if showScore, let score = model.tonightScore, !model.sampleMode || model.tonightScore != nil {
                    Text(model.sampleMode ? "\(score)" : "\(score)")
                }
            }.accessibilityLabel("Starglass tonight's stargazing score \(model.tonightScore ?? 0) of 100")
        }.menuBarExtraStyle(.window)
        Settings { SettingsView(model: model) }
            .commands { CommandGroup(replacing: .appSettings) {
                SettingsLink { Text("Settings…") }.keyboardShortcut(",", modifiers: .command)
            } }
    }
}
