import SwiftUI
import ColumnLatchCore
import MASKit

@main struct ColumnLatchApp: App {
    @StateObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    init() {
        if CommandLine.arguments.contains("--smoke") { exit(SelfTest.run()) }
        if CommandLine.arguments.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
        _model = StateObject(wrappedValue: AppModel())
    }
    var body: some Scene {
        WindowGroup("ColumnLatch", id: "main") {
            ContentView(model: model).onAppear { model.registerShortcut(); AppModel.openPanel = { openWindow(id: "main") } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.becameActive() }
        }.defaultSize(width: 800, height: 700)
        .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.sampleMode ? "Sample · ColumnLatch" : "ColumnLatch").font(.headline)
                Text(L(model.menuStatus)).font(.title2)
                Text(model.menuMessage).font(.caption)
                if let result = model.menuResult { Text(result.timestamp.formatted()).font(.caption) }
                Button("Open contract and results") { model.openPinned() }
                Button("Check again") { model.checkPinned() }
                SettingsLink { Text("Settings") }
                PolicySupportLinks()
                Button("Quit") { NSApp.terminate(nil) }
            }.padding().frame(width: 320)
        } label: { HStack(spacing: 3) {
                Image(systemName: "tablecells")
                if model.busy { ProgressView().controlSize(.mini) }
                else if model.menuSymbol != "tablecells" { Image(systemName: model.menuSymbol).font(.system(size: 10)) }
                Text(model.statusTitle)
            }.help(model.statusTitle + " · " + (model.menuResult?.timestamp.formatted() ?? "No completed check"))
             .accessibilityLabel(model.statusTitle + " · " + (model.menuResult?.timestamp.formatted() ?? "No completed check")) }.menuBarExtraStyle(.window)
        Settings { SettingsView(model: model) }
    }
}
@MainActor enum SelfTest {
    static func run() -> Int32 {
        do {
            let contract = Contract.sample
            let result = try Validator.run(Validator.sampleData, contract: contract)
            let root = URL(fileURLWithPath: NSHomeDirectory())
            let fixture = root.appendingPathComponent("columnlatch-smoke.csv")
            try Data("item_id,quantity\n001,2\n".utf8).write(to: fixture)
            defer { try? FileManager.default.removeItem(at: fixture); try? FileManager.default.removeItem(at: root.appendingPathComponent("columnlatch-smoke-state.json")) }
            let live = try Validator.run(InputReader.read(fixture), contract: contract)
            var state = SavedState(); state.contracts = [contract]; state.commit(result, contract: contract)
            let url = root.appendingPathComponent("columnlatch-smoke-state.json")
            try StateStore.save(state, at: url)
            let reopened = try StateStore.load(at: url)
            let checks = [SmokeCheck(name: "Sample validation", pass: result.findings.count == 2 && result.optionalAbsent == ["status"], detail: "Duplicate group and invalid quantity detected"), SmokeCheck(name: "Local CSV file read", pass: live.complete && !live.failed, detail: "Sandbox fixture read and validated"), SmokeCheck(name: "Reopen persisted state", pass: reopened.baselines[contract.id.uuidString] == result, detail: "Rules and redacted summary survived reopening"), SmokeCheck(name: "Redacted report", pass: !result.report(contract: contract, sample: true).contains("many"), detail: "No source cell values retained")]
            let report = SmokeReport(app: "ColumnLatch", bundleID: "com.michaellip.columnlatch", version: "1.0.0", checks: checks)
            try report.write(); return report.pass ? 0 : 1
        } catch { fputs("\(error)\n", stderr); return 1 }
    }
}
