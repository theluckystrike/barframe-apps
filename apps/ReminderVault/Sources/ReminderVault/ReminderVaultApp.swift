import SwiftUI
import AppKit
import MASKit
import VaultCore
import ServiceManagement
import EventKit

@main struct ReminderVaultApp: App {
    @StateObject private var model: AppModel
    init() {
        if CommandLine.arguments.contains("--smoke") { exit(SelfTest.run()) }
        if CommandLine.arguments.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { print(error); exit(1) }
        }
        _model = StateObject(wrappedValue: AppModel())
    }
    var body: some Scene {
        MenuBarExtra { ContentView(model: model) } label: {
            Label("\(model.pending) · \(model.lastSync)", systemImage: "checklist")
        }.menuBarExtraStyle(.window)
        Settings { SettingsView(model: model) }
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checklist").font(.title).foregroundStyle(.mint)
                VStack(alignment: .leading) { Text("ReminderVault").font(.title2.bold()); Text("Markdown ↔ Reminders").foregroundStyle(.secondary) }
                Spacer()
                if model.sample { Text("Sample").font(.caption.bold()).padding(7).background(.mint.opacity(0.16), in: Capsule()) }
            }
            HStack { Text("\(model.pending) pending").font(.headline); Spacer(); Text("Last sync \(model.lastSync)").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack { Text(model.folderName).font(.headline); Spacer(); Toggle("Sample mode", isOn: Binding(get: { model.sample }, set: { model.setSample($0) })).toggleStyle(.switch).disabled(model.busy) }
            Text(model.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.previewReady {
                Text("Dry-run preview").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        if model.actions.isEmpty { Text("No changes needed.") }
                        ForEach(model.actions) { a in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(a.summary, systemImage: a.conflict ? "exclamationmark.triangle" : "arrow.left.arrow.right").font(.callout.bold())
                                ForEach(Array(a.review.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                                if a.summary.hasPrefix("Manual review:") { Text("No task write will be made.").font(.caption).foregroundStyle(.orange) }
                                Divider()
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 180)
                Button("Apply reviewed sync") { Task { await model.apply() } }.buttonStyle(.borderedProminent).tint(.mint).disabled(model.busy)
            } else {
                Text("Today & undated").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.today.isEmpty { Text(model.rows.isEmpty ? "No tasks loaded. Select a vault or try Sample mode." : "Nothing pending for today.").foregroundStyle(.secondary) }
                        ForEach(model.today) { row in
                            HStack(alignment: .top) {
                                Button { Task { await model.complete(row) } } label: { Image(systemName: "circle").font(.title3) }.buttonStyle(.plain).disabled(model.busy)
                                VStack(alignment: .leading, spacing: 3) { Text(row.value.title); Text(row.value.due ?? "No due date").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
            }
            HStack {
                Button("Preview sync") { Task { await model.preview() } }.disabled(model.busy)
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            HelpButtons().font(.caption)
        }.padding(24).frame(width: 520)
    }
}
enum AppLinks {
    // The builder derives these values from brand.env and the retained per-app URL overrides.
    static var privacy: URL? { HelpLink.webURL(Bundle.main.object(forInfoDictionaryKey: "MASPrivacyPolicyURL") as? String ?? "https://barframe.com/apps/remindervault/privacy/") }
    static var support: URL? { HelpLink.webURL(Bundle.main.object(forInfoDictionaryKey: "MASSupportURL") as? String ?? "https://barframe.com/apps/remindervault/support/") }
}
struct HelpButtons: View {
    @State private var document: HelpDocument?
    var body: some View {
        HStack {
            Button("Privacy Policy") { document = .privacy }
            Button("Support") {
                if let url = AppLinks.support { NSWorkspace.shared.open(url) }
                else { document = .support }
            }
        }.sheet(item: $document) { item in HelpDocumentView(document: item) }
    }
}
enum HelpDocument: String, Identifiable {
    case privacy, support
    var id: String { rawValue }
    var title: String { self == .privacy ? "Privacy Policy" : "Support" }
    var webURL: URL? { self == .privacy ? AppLinks.privacy : AppLinks.support }
    var text: String {
        let relative = "ReminderVault_ReminderVault.bundle/Resources/" + rawValue + ".md"
        let url = Bundle.main.resourceURL?.appendingPathComponent(relative)
        if let url, let text = try? String(contentsOf: url) { return text }
        if let url = Bundle.module.url(forResource: rawValue, withExtension: "md", subdirectory: "Resources"), let text = try? String(contentsOf: url) { return text }
        return "Contact Michael Lip at support@barframe.com for " + title.lowercased() + "."
    }
}
struct HelpDocumentView: View {
    let document: HelpDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(document.title).font(.title2.bold())
            ScrollView { Text(document.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                if let url = document.webURL { Link("Open public web page", destination: url) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620, height: 580)
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State var login = SMAppService.mainApp.status == .enabled
    @State var loginError = ""
    var body: some View {
        Form {
            Text("ReminderVault settings").font(.title2.bold())
            Button("Choose vault folder…") { model.chooseFolder() }.disabled(model.busy)
            Text(model.folderName)
            Button("Connect / refresh Reminders") { Task { await model.connect() } }.disabled(model.busy)
            Text("Selected lists sync in both directions. New vault tasks go to the first selected list alphabetically.").font(.caption)
            ForEach(model.calendars, id: \.calendarIdentifier) { list in
                Toggle(list.title, isOn: Binding(get: { model.selected.contains(list.calendarIdentifier) }, set: { model.select(list.calendarIdentifier, on: $0) })).disabled(model.busy)
            }
            Picker("Sync interval", selection: $model.interval) { Text("Every minute").tag(1); Text("Every 5 minutes").tag(5); Text("Every 15 minutes").tag(15); Text("Every hour").tag(60) }
            Text("Automatic sync starts after you apply a preview this session and pauses on failure until you review and apply again. Markdown file modification time represents its task edits. Equal timestamps favor the vault. Deletions are logged for manual review.").font(.caption)
            Toggle("Launch at login", isOn: Binding(get: { login }, set: { enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = SMAppService.mainApp.status == .requiresApproval ? "Approve in System Settings → General → Login Items." : "" }
                catch { loginError = error.localizedDescription }
                login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            }))
            if !loginError.isEmpty { Text(loginError).foregroundStyle(.orange) }
            Toggle("Sample mode (local example vault)", isOn: Binding(get: { model.sample }, set: { model.setSample($0) })).disabled(model.busy)
            Text("Conflict log").font(.headline)
            ScrollView { VStack(alignment: .leading) { if model.conflictLog.isEmpty { Text("No conflicts recorded.") }; ForEach(Array(model.conflictLog.prefix(200).enumerated()), id: \.offset) { _, s in Text(s).font(.caption).textSelection(.enabled) } } }.frame(height: 100)
            Text(model.status).font(.caption).textSelection(.enabled)
            HelpButtons()
        }.padding(24).frame(width: 570, height: 680)
    }
}
@MainActor enum SelfTest {
    static func run() -> Int32 {
        var checks: [SmokeCheck] = []
        do {
            let source = "# Sample\n- [ ] Write a note 📅 2026-10-20\nUnrelated prose\n"
            let updated = try TaskText.replacing(source, line: 1, value: TaskValue("Write a note", completed: true, due: "2026-10-20"), id: "sample")
            checks.append(SmokeCheck(name: "parser-writer", pass: TaskText.parse(updated).first?.value.completed == true && updated.hasSuffix("Unrelated prose\n"), detail: "Task checkbox changes while unrelated prose survives"))
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".md")
            defer { try? FileManager.default.removeItem(at: url) }
            try updated.write(to: url, atomically: true, encoding: .utf8)
            checks.append(SmokeCheck(name: "container-roundtrip", pass: try String(contentsOf: url) == updated, detail: "Atomic UTF-8 Markdown write and read"))
            let bundled = SampleVault.url
            let sample = try bundled.map { try String(contentsOf: $0) } ?? ""
            checks.append(SmokeCheck(name: "bundled-sample", pass: TaskText.parse(sample).count == 4, detail: "Bundled sample vault parses into four tasks"))
            checks.append(SmokeCheck(name: "event-store", pass: EKEventStore.authorizationStatus(for: .reminder).rawValue >= 0, detail: "Public EventKit authorization query; no private reminders requested"))
            try SmokeReport(app: "ReminderVault", bundleID: Bundle.main.bundleIdentifier ?? "", version: "1.0.0", checks: checks).write()
            return checks.allSatisfy(\.pass) ? 0 : 1
        } catch { print(error); return 1 }
    }
}
