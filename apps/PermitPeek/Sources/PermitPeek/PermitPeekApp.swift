import SwiftUI
import Combine
import Darwin
import MASKit
import PermitPeekCore

@main
struct PermitPeekApp: App {
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
                    DispatchQueue.main.async {
                        AppModel.inboxWindow = NSApp.windows.first(where: { $0.title == "PermitPeek" })
                        AppModel.inboxWindow?.isReleasedWhenClosed = false
                    }
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
    var model: AppModel? { didSet { observeModel() } }
    private var modelObservation: AnyCancellable?
    private(set) var presentation = MenuPresentation(watches: [], sampleMode: false)
    private func observeModel() {
        modelObservation = nil
        guard let model else { updateTitle(MenuPresentation(watches: [], sampleMode: false)); return }
        modelObservation = model.$watches.combineLatest(model.$sampleMode).sink { [weak self] watches, sampleMode in
            self?.updateTitle(MenuPresentation(watches: watches, sampleMode: sampleMode))
        }
    }
    private(set) var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.target = self
        item.button?.action = #selector(toggleWindow)
        statusItem = item
        updateTitle(presentation)
    }

    func applicationDidBecomeActive(_ notification: Notification) { model?.becameActive() }

    @objc private func toggleWindow() {
        NSApp.activate(ignoringOtherApps: true)
        (AppModel.inboxWindow ?? NSApp.windows.first(where: { $0.canBecomeKey }))?.makeKeyAndOrderFront(nil)
    }

    @MainActor func updateTitle(_ state: MenuPresentation) {
        presentation = state
        let label: String
        switch state.symbol {
        case "questionmark.circle": label = L("PermitPeek inspection unknown", "PermitPeek inspección desconocida")
        case "shield": label = L("PermitPeek no watched apps", "PermitPeek sin aplicaciones")
        case "exclamationmark.shield": label = L("PermitPeek changes to review", "PermitPeek cambios por revisar")
        default: label = L("PermitPeek no unreviewed changes", "PermitPeek sin cambios pendientes")
        }
        statusItem?.button?.title = state.title
        statusItem?.button?.image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: label)
        statusItem?.button?.setAccessibilityLabel(label)
    }
}
