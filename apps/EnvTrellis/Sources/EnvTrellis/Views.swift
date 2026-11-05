import AppKit
import SwiftUI
import ServiceManagement
import EnvTrellisCore

struct PolicyLinks: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack {
            Link(model.t("Privacy Policy"), destination: URL(string: "https://barframe.com/apps/envtrellis/privacy/")!)
            Link(model.t("Support"), destination: URL(string: "https://barframe.com/apps/envtrellis/support/")!)
        }.font(.caption)
    }
}
struct ModePicker: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Toggle(model.t("Sample mode"), isOn: Binding(get: { model.sampleMode }, set: { on in model.toggleSample(on); if on { model.installSampleFixtures() } }))
            .toggleStyle(.switch).disabled(model.scanning).accessibilityIdentifier("sampleMode")
    }
}
struct SummaryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "leaf").foregroundStyle(.green)
                Text("EnvTrellis").font(.title2.bold())
                Spacer()
                if model.sampleMode { Text("Sample").font(.caption.bold()).padding(5).background(.green.opacity(0.16), in: Capsule()) }
            }
            Text(model.menuState).font(.title.bold())
            Text(model.project?.label ?? model.t("No pinned project")).foregroundStyle(.secondary)
            if let project = model.project {
                Text(model.t("Last scan") + " " + model.lastScanText).font(.caption).foregroundStyle(.secondary)
                Text(model.t(project.readiness == .ready ? "All decided rules pass. No syntax issues were found." : project.readiness == .stale ? "Inputs changed or access expired. Rescan before relying on this result." : project.readiness == .unknown ? "Some inputs are unavailable. Choose again in the matrix." : "Review missing keys, forbidden keys and undecided rules in the matrix."))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            } else { Text(model.t("See Sample, choose inputs, then review your result.")).font(.callout) }
            ModePicker(model: model)
            HStack {
                Button(model.t("Rescan all")) { model.scan() }.disabled(model.scanning || model.project == nil).accessibilityLabel(model.t("Rescan all"))
                Button(model.t("Open matrix")) { NSApp.activate(ignoringOtherApps: true); openWindow(id: "matrix") }.buttonStyle(.borderedProminent).accessibilityLabel(model.t("Open matrix"))
            }
            if !model.notice.isEmpty { Text(model.t(model.notice)).font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack { SettingsLink { Text(model.t("Settings")) }.accessibilityLabel(model.t("Settings")); Spacer(); Button(model.t("Quit")) { NSApp.terminate(nil) } }
            PolicyLinks(model: model)
        }.padding(20).frame(width: 360).onAppear { model.refreshStale() }
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showReport = false
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("EnvTrellis").font(.largeTitle.bold())
                    Text(model.t("Release readiness without exposing values")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) { ModePicker(model: model); Text(model.menuState).font(.headline).foregroundStyle(model.state == .ready ? .green : .orange) }
            }
            if !model.sampleMode {
                HStack {
                    Picker(model.t("Pinned project"), selection: Binding(get: { model.live.pinned }, set: { if let id = $0 { model.pin(id) } })) {
                        Text(model.t("No pinned project")).tag(UUID?.none)
                        ForEach(model.live.projects) { Text($0.label).tag(Optional($0.id)) }
                    }.frame(maxWidth: 290).disabled(model.scanning)
                    Button(model.t("New project")) { model.addProject() }.accessibilityLabel(model.t("New project"))
                    Spacer()
                    Button(model.t("Choose template")) { model.chooseTemplate() }.accessibilityLabel(model.t("Choose template"))
                    Button(model.t("Add environments")) { model.chooseFile() }.accessibilityLabel(model.t("Add environments"))
                }.disabled(model.scanning)
            }
            if let project = model.project {
                HStack {
                    TextField(model.t("Project label"), text: Binding(get: { model.project?.label ?? "" }, set: { text in model.modify { $0.label = String(text.prefix(80)) } })).textFieldStyle(.roundedBorder).frame(maxWidth: 260).disabled(model.scanning)
                    Spacer()
                    Text(model.t("Last scan") + " " + model.lastScanText).font(.caption).foregroundStyle(.secondary)
                    if model.scanning { ProgressView().controlSize(.small) }
                    Button(model.t("Rescan all")) { model.scan() }.buttonStyle(.borderedProminent).disabled(model.scanning).accessibilityLabel(model.t("Rescan all"))
                    Button(model.t(model.reportCopied ? "Copied" : "Copy report")) { model.copyReport() }.disabled(model.scanning).accessibilityLabel(model.t(model.reportCopied ? "Copied" : "Copy report"))
                }
                if project.template == nil || project.environments.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.t("Choose inputs")).font(.title2.bold())
                        Text(model.t("Select a template and one or more environment files. Permission is granted only for the files you choose."))
                        Text(model.t("Then rescan and choose Required, Optional or Forbidden for each key in each environment."))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    MatrixView(model: model, project: project)
                    DiagnosticsView(model: model, project: project)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.t("Catch missing keys before a release")).font(.title2.bold())
                    Text(model.t("See Sample")).font(.headline)
                    Text(model.t("Explore a saved matrix with required, optional and forbidden keys. Sample needs no file permission."))
                    Button(model.t("Try Sample")) { model.toggleSample(true); model.installSampleFixtures() }.buttonStyle(.borderedProminent).accessibilityLabel(model.t("Try Sample"))
                    Text(model.t("Choose inputs")).font(.headline)
                    Text(model.t("Select a template and one or more environment files. Permission is granted only for the files you choose."))
                    Text(model.t("Review result")).font(.headline)
                    Text(model.t("Rescan, decide rules and copy a report containing key names and presence only."))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(26).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            if !model.notice.isEmpty { Text(model.t(model.notice)).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("notice") }
            Spacer(minLength: 0)
            Divider()
            HStack {
                Label(model.t("Values never appear in reports"), systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.t("Review report")) { showReport = true }.disabled(model.project == nil).accessibilityLabel(model.t("Review report"))
                SettingsLink { Text(model.t("Settings")) }.accessibilityLabel(model.t("Settings"))
                PolicyLinks(model: model)
            }
        }.padding(24).frame(minWidth: 850, idealWidth: 950, minHeight: 620, idealHeight: 710)
            .onAppear { model.openPanel = { NSApp.activate(ignoringOtherApps: true); openWindow(id: "matrix") }; model.refreshStale() }
            .sheet(isPresented: $showReport) { VStack { ReportPreviewView(model: model); Button(model.t("Done")) { showReport = false }.padding(.bottom, 20) }.frame(width: 760, height: 650) }
    }
}
struct MatrixView: View {
    @ObservedObject var model: AppModel
    let project: Project
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    Text(model.t("Key names")).font(.headline).frame(width: 175, alignment: .leading)
                    ForEach(project.environments) { environment in
                        VStack(alignment: .leading, spacing: 7) {
                            TextField(model.t("Environment label"), text: Binding(get: { model.project?.environments.first(where: { $0.id == environment.id })?.label ?? "" }, set: { text in model.modify { project in if let index = project.environments.firstIndex(where: { $0.id == environment.id }) { project.environments[index].label = String(text.prefix(80)) } } })).font(.headline).textFieldStyle(.plain)
                            Text(model.t(environment.unavailable ? "Unknown" : "Rules for this environment")).font(.caption).foregroundStyle(.secondary)
                            Button(model.t("Require undecided")) { model.requireUndecided(environment.id) }.font(.caption).accessibilityLabel(model.t("Require undecided") + " " + environment.label)
                        }.frame(width: 185, alignment: .leading)
                    }
                }
                Divider()
                ForEach(project.keys, id: \.self) { key in
                    GridRow {
                        Text(key).font(.system(.callout, design: .monospaced)).textSelection(.enabled).frame(width: 175, alignment: .leading)
                        ForEach(project.environments) { environment in
                            VStack(alignment: .leading, spacing: 5) {
                                Picker(model.t("Rule") + " " + key + " " + environment.label, selection: Binding<Rule?>(get: { model.rule(key: key, environment: environment.id) }, set: { model.setRule(key: key, environment: environment.id, rule: $0) })) {
                                    Text(model.t("Decide rule")).tag(Rule?.none)
                                    ForEach(Rule.allCases, id: \.self) { Text(model.t($0.rawValue)).tag(Optional($0)) }
                                }.labelsHidden().frame(width: 185).accessibilityLabel(model.t("Rule") + " " + key + " " + environment.label)
                                Text(model.t(project.outcome(key: key, environment: environment))).font(.caption.bold()).foregroundStyle(project.outcome(key: key, environment: environment) == "Pass" ? .green : .orange)
                                let entry = environment.parsed?.keys[key]
                                Text(model.t(environment.unavailable ? "Unknown" : entry?.presence.rawValue ?? "Absent") + (entry.map { " · " + model.t("Lines") + " " + $0.lines.map(String.init).joined(separator: ", ") } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 185, alignment: .leading)
                        }
                    }
                    Divider()
                }
                if project.keys.isEmpty { Text(model.t("No keys found. Rescan to read your selected files.")).foregroundStyle(.secondary) }
            }.padding(18)
        }.frame(minHeight: 240, maxHeight: 390).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12)).disabled(model.scanning)
    }
}
struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    let project: Project
    var body: some View {
        DisclosureGroup(model.t("File diagnostics and access")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if let template = project.template { fileRow(template, template: true) }
                    ForEach(project.environments) { fileRow($0, template: false) }
                }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 160)
        }
    }
    private func issueText(_ issue: ParseIssue) -> String {
        let duplicate = issue.kind.hasPrefix("Duplicate key ")
        let kind = model.t(duplicate ? "Duplicate key" : issue.kind)
        let key = duplicate ? " " + String(issue.kind.dropFirst(14)) : ""
        return model.t("Line") + " " + String(issue.line) + " " + kind + key
    }
    @ViewBuilder private func fileRow(_ file: InputFile, template: Bool) -> some View {
        HStack {
            Text(template ? model.t("Template") : file.label).font(.headline)
            Text(model.t(file.unavailable || file.parsed == nil ? "Unknown" : file.parsed?.issues.isEmpty == true ? "No syntax issues" : "Syntax findings")).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if !model.sampleMode {
                Button(model.t("Choose again")) { model.chooseFile(environmentID: template ? nil : file.id, template: template) }.accessibilityLabel(model.t("Choose again"))
                if !template { Button(model.t("Forget")) { model.forgetEnvironment(file.id) }.accessibilityLabel(model.t("Forget")) }
            }
        }
        ForEach(Array((file.parsed?.issues ?? []).enumerated()), id: \.offset) { _, issue in
            Text(issueText(issue))
                .font(.caption).foregroundStyle(.orange)
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var loginError = ""
    @State private var login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(model.t("EnvTrellis settings")).font(.title2.bold())
            if !model.live.projects.isEmpty {
                Picker(model.t("Pinned project"), selection: Binding(get: { model.live.pinned }, set: { if let id = $0 { model.pin(id) } })) {
                    ForEach(model.live.projects) { Text($0.label).tag(Optional($0.id)) }
                }.disabled(model.scanning)
            }
            ModePicker(model: model)
            Button(model.t("Reset Sample")) { model.resetSample() }.disabled(!model.sampleMode).accessibilityLabel(model.t("Reset Sample"))
            Toggle(model.t("Launch at login"), isOn: Binding(get: { login }, set: { enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = SMAppService.mainApp.status == .requiresApproval ? model.t("Approve launch in System Settings Login Items.") : "" }
                catch { loginError = model.t("Launch at login could not be changed.") }
                login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            }))
            if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.orange) }
            Picker(model.t("Appearance"), selection: $model.appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text(model.t($0)).tag($0) } }
            Picker(model.t("Language"), selection: $model.language) { Text("English").tag("English"); Text("Español").tag("Español") }
            Toggle(model.t("Mask project and environment labels in reports"), isOn: $model.maskLabels)
            DisclosureGroup(model.t("Advanced")) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(model.t("Open panel shortcut") + " ⌘ ⇧", selection: $model.shortcutKey) { ForEach(["E", "R", "T", "Y", "U"], id: \.self) { Text($0).tag($0) } }
                    if !model.shortcutError.isEmpty { Text(model.t(model.shortcutError)).font(.caption).foregroundStyle(.orange) }
                    Text(model.t("Manage per environment rules and forgotten files in the matrix.")).font(.caption)
                    Button(model.t("Remove pinned project"), role: .destructive) { model.removeProject() }.disabled(model.sampleMode || model.project == nil || model.scanning).accessibilityLabel(model.t("Remove pinned project"))
                    Button(model.t("Clear local data"), role: .destructive) { model.clearData() }.accessibilityLabel(model.t("Clear local data"))
                    Text(model.t("Source files are never deleted. There is no reveal values setting.")).font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            Divider()
            PolicyLinks(model: model)
            HStack { Text("1.0.0").font(.caption).foregroundStyle(.secondary); Spacer(); Button(model.t("Quit")) { NSApp.terminate(nil) } }
        }.padding(24).frame(width: 540)
    }
}

struct ReportPreviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(model.t("Release readiness report")).font(.title2.bold()); Spacer(); if model.sampleMode { Text("Sample").font(.headline).foregroundStyle(.green) } }
            Text(model.t("Values never appear in reports")).foregroundStyle(.secondary)
            ScrollView { Text(model.report).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Button(model.t(model.reportCopied ? "Copied" : "Copy report")) { model.copyReport() }.buttonStyle(.borderedProminent).accessibilityLabel(model.t(model.reportCopied ? "Copied" : "Copy report"))
        }.padding(24).frame(minWidth: 680, minHeight: 500)
    }
}
