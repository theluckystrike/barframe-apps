import SwiftUI
import ServiceManagement
import ColumnLatchCore

struct PolicySupportLinks: View {
    var body: some View { HStack { Link("Privacy Policy", destination: URL(string: "https://barframe.com/apps/columnlatch/privacy/")!); Link("Support", destination: URL(string: "https://barframe.com/apps/columnlatch/support/")!) }.font(.caption) }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: model.statusSymbol).font(.largeTitle).foregroundStyle(model.result?.failed == true ? .orange : .teal).accessibilityLabel(model.status)
                VStack(alignment: .leading) { Text(L("ColumnLatch")).font(.title.bold()); Text(model.tr("Check the delivery before import", "Revise la entrega antes de importar")).foregroundStyle(.secondary) }
                Spacer()
                Toggle(L("Sample"), isOn: Binding(get: { model.sampleMode }, set: model.setSample)).toggleStyle(.switch).fixedSize()
            }
            HStack(spacing: 20) { Label(model.tr("See Sample", "Ver ejemplo"), systemImage: "1.circle"); Label(model.tr("Choose inputs", "Elegir archivo"), systemImage: "2.circle"); Label(model.tr("Review result", "Revisar resultado"), systemImage: "3.circle") }.font(.caption).foregroundStyle(.secondary)
            HStack {
                if model.sampleMode { Text(L("Sample supplier contract")).font(.headline) }
                else { Picker(model.tr("Contract", "Contrato"), selection: Binding(get: { model.selected }, set: model.select)) { Text(L("New contract")).tag(nil as UUID?); ForEach(model.state.contracts) { Text($0.name).tag(Optional($0.id)) } }.frame(maxWidth: 350) }
                Spacer()
                Text(model.sampleMode ? model.tr("Sample · synthetic data", "Sample · datos sintéticos") : model.tr("Live · local only", "Real · solo local")).font(.caption.bold()).padding(7).background(.teal.opacity(0.12), in: Capsule())
            }
            HStack {
                Button(model.tr("Create from header", "Crear desde cabecera")) { model.choose(headerOnly: true); tab = 1 }.accessibilityLabel("Create from header").accessibilityIdentifier("createHeader").disabled(model.sampleMode || model.busy)
                Button(model.tr("Choose delivery", "Elegir entrega")) { model.choose() }.accessibilityLabel("Choose delivery").accessibilityIdentifier("chooseDelivery").disabled(model.busy || model.draft.rules.isEmpty)
                Button(model.tr("Check again", "Revisar de nuevo")) { model.checkSaved() }.accessibilityLabel("Check again").accessibilityIdentifier("checkAgain").disabled(model.busy || model.draft.rules.isEmpty).keyboardShortcut("r")
                if model.busy { ProgressView().controlSize(.small); Button(L("Cancel")) { model.cancel() } }
            }
            Text(model.tr("UTF8 CSV · 20 MB maximum · comma, semicolon or tab · record 1 is the header", "CSV UTF8 · máximo 20 MB · coma, punto y coma o tabulador · registro 1 es la cabecera")).font(.caption).foregroundStyle(.secondary)
            Text(model.localizedMessage).font(.callout).foregroundStyle(model.outdated ? .orange : .primary).fixedSize(horizontal: false, vertical: true)
            Picker(L("View"), selection: $tab) { Text(model.tr("Results", "Resultados")).tag(0); Text(model.tr("Contract", "Contrato")).tag(1) }.pickerStyle(.segmented)
            if tab == 0 { ResultsView(model: model) } else { ContractView(model: model) }
            Divider()
            HStack { PolicySupportLinks(); Spacer(); SettingsLink { Text(model.tr("Settings", "Ajustes")) }; Button(L("Quit")) { NSApp.terminate(nil) }.accessibilityLabel("Quit") }
        }.padding(24).frame(minWidth: 740, idealWidth: 800, maxWidth: .infinity, minHeight: 620, idealHeight: 700)
        .preferredColorScheme(model.appearance == "Dark" ? .dark : model.appearance == "Light" ? .light : nil)
    }
}
struct ResultsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = model.result {
                HStack {
                    metric(L(model.outdated ? "Stale" : result.failed ? "Findings" : "Accepted"), model.tr("Acceptance", "Aceptación"))
                    metric("\(result.rows)", model.tr("Data records checked", "Registros revisados"))
                    metric("\(result.findings.count)", model.tr("Findings and warnings", "Hallazgos y avisos"))
                }
                Text("\(model.sampleMode ? "Sample · " : "")\(model.draft.name) · \(result.timestamp.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                if !result.optionalAbsent.isEmpty { Label(model.tr("Optional absent and accepted · ", "Opcionales ausentes aceptadas · ") + result.optionalAbsent.joined(separator: ", "), systemImage: "checkmark.circle").foregroundStyle(.teal) }
                if result.findings.isEmpty { Label(model.tr("All contract rules passed", "Todas las reglas aprobadas"), systemImage: "checkmark.seal").padding() }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(result.findings) { finding in
                            HStack(alignment: .top) {
                                Image(systemName: finding.failure ? "exclamationmark.circle" : "info.circle").foregroundStyle(finding.failure ? .orange : .teal)
                                VStack(alignment: .leading, spacing: 3) { Text(L(finding.category) + " · " + finding.column).font(.body.bold()); Text(finding.records.isEmpty ? L("Header rule") : model.tr("Records ", "Registros ") + finding.records.map(String.init).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text(finding.failure ? "FAIL" : "WARN").font(.caption.monospaced().bold())
                            }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(minHeight: 100)
                Text(result.newCategories.isEmpty ? L("No newly failing rule categories") : model.tr("New since last completed check · ", "Nuevos fallos desde la última revisión completa · ") + result.newCategories.map { key in result.findings.first(where: { $0.categoryKey == key }).map { L($0.category) + " · " + $0.column } ?? key }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                HStack { Button(model.tr("Copy redacted report", "Copiar informe sin valores")) { model.copyReport() }.accessibilityLabel("Copy redacted report"); Button(model.tr("Pin contract", "Fijar contrato")) { model.pin() }.disabled(model.sampleMode); Spacer(); Text(L("Source values never saved")).font(.caption).foregroundStyle(.secondary) }
            } else {
                Spacer(); Label(model.tr("No delivery checked yet", "Ninguna entrega revisada"), systemImage: "tablecells").font(.title2)
                Text(model.tr("See Sample now, or create a supplier contract from a CSV header. Define rules explicitly before checking a delivery.", "Vea el ejemplo o cree un contrato desde la cabecera CSV. Defina las reglas antes de revisar una entrega.")).foregroundStyle(.secondary)
                Button(model.tr("See Sample", "Ver ejemplo")) { model.setSample(true) }; Spacer()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    func metric(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.title2.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }
}
struct ContractView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L("Supplier contract name"), text: $model.draft.name)
            HStack {
                Picker(L("Delimiter"), selection: $model.draft.delimiter) { Text(L("Comma")).tag(","); Text(L("Semicolon")).tag(";"); Text(L("Tab")).tag("\t") }
                Picker(L("Unique key"), selection: $model.draft.uniqueKey) { Text(L("None")).tag(""); ForEach(model.draft.rules) { Text($0.name).tag($0.name) } }
            }
            Toggle(L("Unexpected columns fail instead of warn"), isOn: $model.draft.unexpectedFails)
            Text(L("Advanced rules · exact values · no automatic inference")).font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($model.draft.rules) { $rule in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(rule.name).font(.headline); Spacer(); Toggle(L("Required"), isOn: $rule.required); Toggle(L("Allow empty"), isOn: $rule.allowEmpty) }
                            Picker(L("Value type"), selection: $rule.kind) { ForEach(ValueKind.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) } }
                            if rule.kind == .allowed { TextField(L("Exact allowed values separated by |"), text: Binding(get: { rule.allowed.joined(separator: "|") }, set: { rule.allowed = $0.components(separatedBy: "|") })); Text(L("Case sensitive. No trimming. Pipe separates values.")).font(.caption) }
                        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Text(L("Integer accepts an optional sign and digits. Decimal also permits a dot and fractional digits. Identifiers stay text.")).font(.caption).foregroundStyle(.secondary)
            Button(L("Save contract rules")) { model.saveContract() }.accessibilityLabel("Save contract rules").accessibilityIdentifier("saveContract").buttonStyle(.borderedProminent)
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    var body: some View {
        Form {
            Section(L("ColumnLatch")) {
                if !model.sampleMode {
                    Picker(model.tr("Contract", "Contrato"), selection: Binding(get: { model.selected }, set: model.select)) {
                        Text(L("New contract")).tag(nil as UUID?)
                        ForEach(model.state.contracts) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Picker(L("Delimiter"), selection: $model.draft.delimiter) { Text(L("Comma")).tag(","); Text(L("Semicolon")).tag(";"); Text(L("Tab")).tag("\t") }

                Toggle(model.tr("Sample mode", "Modo de ejemplo"), isOn: Binding(get: { model.sampleMode }, set: model.setSample))
                Button(L("Reset Sample")) { model.setSample(true); model.resetSample() }
                Toggle(model.tr("Launch at login", "Abrir al iniciar sesión"), isOn: Binding(get: { login }, set: { value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; login = SMAppService.mainApp.status == .enabled; loginError = SMAppService.mainApp.status == .requiresApproval ? "Approve in System Settings Login Items." : "" } catch { loginError = error.localizedDescription }
                }))
                if !loginError.isEmpty { Text(loginError).foregroundStyle(.orange) }
                Picker(L("Appearance"), selection: $model.appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text(L($0)) } }.onChange(of: model.appearance) { _, v in UserDefaults.standard.set(v, forKey: "appearance") }
                Picker(L("Language"), selection: $model.language) { Text(L("English")).tag("English"); Text(L("Español")).tag("Español") }.onChange(of: model.language) { _, v in UserDefaults.standard.set(v, forKey: "language") }
            }
            Section(L("Advanced")) {
                Picker(L("Open panel shortcut"), selection: $model.shortcutKey) { Text(L("⌘⌥L")).tag(0); Text(L("⌘⌥K")).tag(1); Text(L("⌘⌥J")).tag(2) }.onChange(of: model.shortcutKey) { _, _ in model.registerShortcut() }
                if !model.shortcutError.isEmpty { Text(model.shortcutError).foregroundStyle(.orange) }
                Text(L("Only selected files are read. Contracts, bookmarks and value redacted summaries stay in the app container.")).font(.caption)
                Button(L("Delete local data"), role: .destructive) { model.clear() }
            }
            PolicySupportLinks()
        }.formStyle(.grouped).padding(16).frame(width: 540, height: 540)
    }
}
