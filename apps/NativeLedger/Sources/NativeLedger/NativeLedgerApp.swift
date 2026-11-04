import SwiftUI
import AppKit
import Darwin
import LedgerCore

@main
struct NativeLedgerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state: AppState

    init() {
        let args = CommandLine.arguments
        if args.contains("--selftest") || args.contains("--smoke") {
            exit(SelfTest.run(writeSmoke: args.contains("--smoke")))
        }
        if args.contains("--screenshots") {
            exit(ScreenshotRenderer.renderOrReport(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")))
        }
        if let index = args.firstIndex(of: "--render-screenshots"), index + 1 < args.count {
            exit(ScreenshotRenderer.renderOrReport(to: URL(fileURLWithPath: args[index + 1])))
        }
        _state = StateObject(wrappedValue: AppState.launch(arguments: args))
    }

    var body: some Scene {
        WindowGroup("NativeLedger") {
            ContentView(state: state)
                .frame(minWidth: 940, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { LedgerCommands(state: state) }
        Settings { SettingsView(state: state, alerts: state.alerts) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // A regular windowed app with a Dock icon and a main menu.
        NSApp.setActivationPolicy(.regular)
    }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Holds the saved ledgers, the alert setting and, while it is open, the memory-only Sample.
@MainActor
final class AppState: ObservableObject {
    let live: LedgerModel
    let alerts: AlertController
    @Published private(set) var sample: LedgerModel?
    /// Started with --ledger-sample. The saved ledgers are never opened.
    let sampleOnly: Bool

    init(live: LedgerModel, sampleOnly: Bool = false, alerts: AlertController? = nil) {
        self.live = live
        self.sampleOnly = sampleOnly
        let alerts = alerts ?? AlertController(poster: SystemNotifier())
        self.alerts = alerts
        // Only automatic entries of the saved ledgers reach the alerts. The Sample has no automatic entries.
        live.onAutomaticEntries = { [weak alerts] entries in alerts?.handle(entries) }
        if sampleOnly { sample = LedgerModel.sample() }
    }
    var current: LedgerModel { sample ?? live }
    var showingSample: Bool { sample != nil }

    func openSample() { if sample == nil { sample = LedgerModel.sample() } }
    func leaveSample() { guard !sampleOnly else { return }; sample = nil }

    static func launch(arguments: [String]) -> AppState {
        if arguments.contains("--ledger-sample") {
            return AppState(live: LedgerModel(store: nil), sampleOnly: true)
        }
        let state = AppState(live: LedgerModel(store: LedgerStore(directory: LedgerModel.defaultDirectory)))
        // Records what changed while NativeLedger was closed, then watches for changes.
        state.live.startWatching()
        return state
    }
}

struct LedgerCommands: Commands {
    @ObservedObject var state: AppState
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Watch a Folder…") { state.current.chooseFolders() }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(!state.current.canWatchFolders)
            Button("Add App…") { state.current.chooseApps() }
                .keyboardShortcut("o")
                .disabled(!state.current.canAddApps)
            Divider()
            Button("Export Ledger…") { state.current.chooseExport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!state.current.canExport)
            Button("Compare with Ledger File…") { state.current.chooseCompare() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            if state.showingSample {
                Button("Leave Sample") { state.leaveSample() }.disabled(state.sampleOnly)
            } else {
                Button("Open Sample") { state.openSample() }
            }
        }
        CommandGroup(replacing: .appInfo) {
            Button("About NativeLedger") { showAbout() }
        }
        CommandGroup(replacing: .help) {
            if let privacy = AppLinks.privacyURL { Link("NativeLedger Privacy Policy", destination: privacy) }
            if let support = AppLinks.supportURL { Link("NativeLedger Support", destination: support) }
        }
    }
}
