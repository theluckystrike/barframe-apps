import SwiftUI
import NameWeaveCore

struct NamedButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View { NativeActionButton(title: title, action: action).fixedSize() }
}
struct NativeActionButton: NSViewRepresentable {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func invokeAction() { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.invokeAction))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel(title)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title; button.isEnabled = enabled; button.setAccessibilityLabel(title); context.coordinator.action = action
        button.sizeToFit()
    }
}
struct PolicyLinks: View {
    var body: some View {
        HStack {
            PolicyButton(title: "Privacy Policy", key: "MASPrivacyPolicyURL", localResource: "privacy")
            PolicyButton(title: "Support", key: "MASSupportURL", localResource: "support")
            Link("Windows naming rules", destination: URL(string: Weave.source)!)
        }.font(.caption)
    }
}
struct SummaryView: View {
    @ObservedObject var model: AppModel
    var detail: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Image(systemName: "textformat"); Text("NameWeave").font(.headline); Spacer(); if model.sample { Text("Sample").foregroundStyle(.mint) } }
            Text(model.status).font(.title2.bold())
            if model.scan == nil { Text(model.l("Check a folder before a platform handoff", "Comprueba una carpeta antes de compartirla")) }
            else { Text(model.l("\(model.plan.issueCount) flagged paths and \(model.plan.unresolvedCount) unresolved proposals", "\(model.plan.issueCount) rutas con problemas y \(model.plan.unresolvedCount) propuestas pendientes")) }
            if let date = model.checkedAt { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            HStack {
                NamedButton(model.l("Review plan", "Revisar plan"), action: detail).buttonStyle(.borderedProminent)
                NamedButton(model.l("Choose folder", "Elegir carpeta")) { model.chooseFolder() }
            }
            HStack {
                NamedButton(model.l("See Sample", "Ver Sample")) { model.toggleSample(true); detail() }
                SettingsLink { Text(model.l("Settings", "Ajustes")) }
                NamedButton(model.l("Quit", "Salir")) { NSApp.terminate(nil) }
            }
            PolicyLinks()
        }.padding(20).frame(width: 400).preferredColorScheme(model.colorScheme)
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var issuesOnly = false
    @State private var search = ""
    private var filteredRows: [Row] { model.plan.rows.filter { (!issuesOnly || !$0.originalReasons.isEmpty || !$0.unresolved.isEmpty) && (search.isEmpty || $0.entry.path.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NameWeave").font(.system(size: 28, weight: .bold))
                    Text(model.l("Check filename portability", "Comprueba la portabilidad de nombres")).foregroundStyle(.secondary)
                }
                Spacer()
                if model.sample { Text("Sample").font(.headline).padding(8).background(.mint.opacity(0.15), in: Capsule()).foregroundStyle(.mint) }
                Text(model.status).font(.headline).padding(8).background(.secondary.opacity(0.12), in: Capsule())
                SettingsLink { Image(systemName: "gearshape").accessibilityLabel(model.l("Settings", "Ajustes")) }
            }
            HStack {
                NamedButton(model.l("Choose folder", "Elegir carpeta")) { model.chooseFolder() }.buttonStyle(.borderedProminent).disabled(model.busy)
                NamedButton(model.l("See Sample", "Ver Sample")) { model.toggleSample(true) }
                if model.sample { NamedButton(model.l("Use Live", "Usar datos reales")) { model.toggleSample(false) } }
                NamedButton(model.l("Rescan", "Volver a comprobar")) { model.rescan() }.disabled(model.busy || model.scan == nil)
                if model.busy { ProgressView().controlSize(.small); NamedButton(model.l("Cancel", "Cancelar")) { model.cancelScan() } }
                Spacer()
                if !model.rootLabel.isEmpty { Text(model.rootLabel).lineLimit(1).foregroundStyle(.secondary) }
            }
            if model.scan == nil {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.l("A safer folder handoff starts here", "Comparte carpetas con más confianza")).font(.title2.bold())
                    Label(model.l("1  See Sample and explore real conflicts", "1  Ver Sample y explorar conflictos"), systemImage: "sparkles")
                    Label(model.l("2  Choose a folder to grant read access", "2  Elegir una carpeta y permitir la lectura"), systemImage: "folder")
                    Label(model.l("3  Review replacements and copy the plan", "3  Revisar propuestas y copiar el plan"), systemImage: "checklist")
                    Text(model.l("Files stay unchanged. No permission is needed for Sample.", "Los archivos no cambian. Sample no necesita permisos.")).foregroundStyle(.secondary)
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 16) {
                    metric(model.l("Paths reviewed", "Rutas revisadas"), String(model.plan.rows.count))
                    metric(model.l("Source risks", "Riesgos de origen"), String(model.plan.issueCount))
                    metric(model.l("Unresolved", "Pendientes"), String(model.plan.unresolvedCount))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(model.ready ? model.l("Ready", "Listo") : model.stale ? model.l("Rescan required", "Comprobación necesaria") : model.l("Review required", "Revisión necesaria")).font(.headline).foregroundStyle(model.ready ? .mint : .orange)
                        Text(model.l("Windows conservative profile", "Perfil conservador de Windows")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(16).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    TextField(model.l("Find a path", "Buscar una ruta"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    Toggle(model.l("Risks only", "Solo riesgos"), isOn: $issuesOnly).toggleStyle(.checkbox)
                    Spacer()
                    NamedButton(model.l("Resolve candidates", "Resolver propuestas")) { model.resolve() }.disabled(model.busy || model.stale)
                    NamedButton(model.copied ? model.l("Copied", "Copiado") : model.l("Copy plan", "Copiar plan")) { model.copyPlan() }.disabled(model.busy)
                }
                HStack { Text(model.l("Source path and reason", "Ruta de origen y motivo")).frame(maxWidth: .infinity, alignment: .leading); Text(model.l("Replacement component", "Nombre propuesto")).frame(width: 245, alignment: .leading); Text(model.l("Destination check", "Comprobación de destino")).frame(width: 205, alignment: .leading) }.font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRows) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.entry.path).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                        Text(localReasons(row.originalReasons)).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    TextField(row.entry.name, text: Binding(get: { model.edits[row.id] ?? row.entry.name }, set: { model.edit(row.entry, value: $0) }))
                                        .textFieldStyle(.roundedBorder).frame(width: 245).disabled(model.busy || model.stale)
                                        .accessibilityLabel(model.l("Replacement for ", "Nombre propuesto para ") + row.entry.path)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(row.unresolved.isEmpty ? model.l("Clear", "Sin problemas") : model.l("Conflict", "Conflicto"), systemImage: row.unresolved.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                                            .foregroundStyle(row.unresolved.isEmpty ? .mint : .orange)
                                        if !row.unresolved.isEmpty { Text(localReasons(row.unresolved)).font(.caption).foregroundStyle(.orange) }
                                    }.frame(width: 205, alignment: .leading)
                                }
                                if row.proposed != row.entry.path { Text("→ " + row.proposed).font(.system(.caption, design: .monospaced)).foregroundStyle(.mint).textSelection(.enabled) }
                            }.padding(.vertical, 12)
                            Divider()
                        }
                        if filteredRows.isEmpty { Text(model.plan.rows.isEmpty ? model.l("The supported tree is empty. Review coverage below.", "El árbol está vacío. Revisa la cobertura.") : model.l("No paths match this filter.", "No hay rutas que coincidan con el filtro.")).padding(30).foregroundStyle(.secondary) }
                    }
                }.frame(minHeight: 230)
                if model.stale { Text(model.l("Last result is stale. Rescan or choose again before relying on this plan.", "El resultado anterior está pendiente de comprobar. Vuelve a comprobar o elegir.")).foregroundStyle(.orange).font(.caption) }
                if let scan = model.scan, !scan.coverage.complete {
                    DisclosureGroup(model.l("Incomplete coverage", "Cobertura incompleta")) {
                        ScrollView { VStack(alignment: .leading) { ForEach(Array(scan.coverage.omissions.enumerated()), id: \.offset) { _, text in Text(localCoverage(text)).font(.caption).textSelection(.enabled) }; if scan.coverage.cancelled { Text(model.l("Scan cancelled", "Comprobación cancelada")) } } }.frame(maxHeight: 100)
                    }.foregroundStyle(.orange)
                }
            }
            if let notice = model.observationNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            Divider()
            HStack {
                Text(model.l("Simulation only. Source files stay unchanged.", "Solo simulación. Los archivos originales no cambian.")).font(.caption).foregroundStyle(.secondary)
                Spacer(); PolicyLinks()
            }
        }.padding(24).frame(minWidth: 940, minHeight: 650).preferredColorScheme(model.colorScheme)
    }
    private func localCoverage(_ text: String) -> String {
        guard model.spanish else { return text }
        let prefixes = ["Root unavailable or permission denied": "Carpeta no disponible o permiso denegado", "Security scoped permission denied. Choose again.": "Permiso de acceso denegado. Vuelve a elegir.", "Unsupported symbolic link root": "Carpeta raíz de enlace no compatible", "Unsupported symbolic link ": "Enlace simbólico no compatible ", "Excluded directory ": "Carpeta excluida ", "Dependency directory contents skipped ": "Contenido de dependencias omitido ", "Scan limit reached at ": "Límite de comprobación alcanzado en ", "Inaccessible ": "Inaccesible "]
        for (prefix, translated) in prefixes where text.hasPrefix(prefix) { return translated + text.dropFirst(prefix.count) }
        return text
    }
    private func metric(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.title2.bold().monospacedDigit()); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(minWidth: 105, alignment: .leading) }
    private func localReasons(_ values: [String]) -> String {
        guard model.spanish else { return values.isEmpty ? "No source rule issue" : values.joined(separator: " · ") }
        let translations = ["Restricted character": "Carácter restringido", "Trailing dot or space": "Punto o espacio final", "Reserved device stem": "Nombre de dispositivo reservado", "Case or Unicode portability collision": "Colisión de mayúsculas o Unicode", "Virtual destination collision": "Colisión en el destino virtual", "Legacy target budget exceeded": "Se supera el límite de destino", "Invalid parent replacement": "Nombre de carpeta superior no válido", "Empty or navigation component": "Nombre vacío o de navegación", "Component UTF16 budget exceeded": "Se supera el límite UTF16 del nombre"]
        return values.isEmpty ? "Sin problemas de nombre" : values.map { translations[$0] ?? $0 }.joined(separator: " · ")
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section(model.l("Basic", "Básico")) {
                Text("NameWeave").font(.title2.bold())
                Toggle(model.l("Sample mode", "Modo Sample"), isOn: Binding(get: { model.sample }, set: { model.toggleSample($0) }))
                HStack { NamedButton(model.l("Choose folder", "Elegir carpeta")) { model.chooseFolder() }; NamedButton(model.l("Forget root", "Olvidar carpeta")) { model.forget() }; if model.sample { NamedButton(model.l("Reset Sample", "Restablecer Sample")) { model.resetSample() } } }
                Text(model.l("Windows conservative compatibility profile", "Perfil conservador de compatibilidad con Windows"))
                Text(model.l("Case and normalization risks are a policy target, not a guarantee for every filesystem.", "Los riesgos de mayúsculas y normalización son un objetivo de compatibilidad, no una garantía universal.")).font(.caption).foregroundStyle(.secondary)
                Picker(model.l("Appearance", "Apariencia"), selection: $model.appearance) { Text(model.l("System", "Sistema")).tag("system"); Text(model.l("Light", "Claro")).tag("light"); Text(model.l("Dark", "Oscuro")).tag("dark") }
                Toggle("Español", isOn: $model.spanish)
            }
            Section(model.l("Advanced destination policy", "Política avanzada de destino")) {
                TextField(model.l("Destination prefix", "Prefijo de destino"), text: $model.policy.prefix).onChange(of: model.policy.prefix) { _, _ in model.updatePolicy() }
                TextField(model.l("Legacy full path UTF16 budget or blank", "Límite UTF16 de ruta heredado o vacío"), text: Binding(get: { model.budgetText }, set: { model.budgetText = $0 }))
                if !model.budgetText.isEmpty && (Int(model.budgetText) ?? 0) <= 0 { Text(model.l("Enter a positive integer. Budget is disabled until valid.", "Introduce un entero positivo. El límite está desactivado.")).font(.caption).foregroundStyle(.orange) }
                Toggle(model.l("Canonical Unicode normalization risks", "Riesgos de normalización Unicode canónica"), isOn: $model.policy.normalize).onChange(of: model.policy.normalize) { _, _ in model.updatePolicy() }
                TextField(model.l("Excluded relative directories separated by commas", "Carpetas relativas excluidas separadas por comas"), text: Binding(get: { model.exclusionsText }, set: { model.exclusionsText = $0 }))
                Text(model.l("Budgets are compatibility targets. Exclusions and skipped links prevent complete coverage.", "Los límites son objetivos de compatibilidad. Las exclusiones y enlaces omitidos impiden cobertura completa.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(model.l("Global open panel shortcut", "Atajo global para abrir el panel")) {
                HStack {
                    Picker(model.l("Modifiers", "Modificadores"), selection: $model.shortcutModifier) { Text("⌘ ⇧").tag("commandShift"); Text("⌃ ⌥").tag("controlOption") }
                    Picker(model.l("Key", "Tecla"), selection: $model.shortcutKey) { Text(model.l("None", "Ninguno")).tag(""); ForEach(["N", "W", "P", "K"], id: \.self) { Text($0).tag($0) } }
                }
                if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
                Text(model.l("Registration failures appear here. No Accessibility permission is required.", "Los errores de registro se muestran aquí. No se requiere permiso de accesibilidad.")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                NamedButton(model.l("Clear local data", "Borrar datos locales")) { model.clearLocalData() }
                PolicyLinks()
                Text(model.l("Data Not Collected. All checks stay on this Mac.", "No se recopilan datos. Las comprobaciones quedan en este Mac.")).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(10).frame(width: 610, height: 740).preferredColorScheme(model.colorScheme)
    }
}

struct PolicyButton: View {
    let title: String
    let key: String
    let localResource: String
    @State private var showLocal = false
    static func usableURL(_ value: String?) -> URL? {
        guard let value, !value.contains("{"), !value.contains("}"), let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    var body: some View {
        Button(title) {
            if let url = Self.usableURL(Bundle.main.object(forInfoDictionaryKey: key) as? String), url.path == (key == "MASPrivacyPolicyURL" ? "/apps/nameweave/privacy/" : "/apps/nameweave/support/") { NSWorkspace.shared.open(url) }
            else { showLocal = true }
        }.buttonStyle(.link)
        .sheet(isPresented: $showLocal) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.title2.bold())
                ScrollView { Text(localText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                NamedButton("Done") { showLocal = false }
            }.padding(24).frame(width: 540, height: 460)
        }
    }
    static func bundledText(_ resource: String, resourceDirectory: URL? = Bundle.main.resourceURL) -> String {
        // SwiftPM's generated Bundle.module searches the build folder for executable targets.
        // The kit ships that resource bundle inside Contents/Resources instead.
        if let directory = resourceDirectory {
            let url = directory.appendingPathComponent("NameWeave_NameWeave.bundle").appendingPathComponent(resource + ".md")
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        }
        return "NameWeave keeps checks on this Mac. Source files stay unchanged. Support is provided by Michael Lip."
    }
    private var localText: String { Self.bundledText(localResource) }
}
