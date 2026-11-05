import SwiftUI
import LinkSprigCore

struct PolicyLinks: View {
    @ObservedObject var model: AppModel
    @State private var localPage: String?
    var body: some View {
        HStack(spacing: 16) {
            Button(model.tr("Privacy Policy", "Política de privacidad")) { open("MASPrivacyPolicyURL", fallback: "privacy") }
            Button(model.tr("Support", "Ayuda")) { open("MASSupportURL", fallback: "support") }
        }.buttonStyle(.link).font(.caption)
        .sheet(item: Binding(get: { localPage.map(LocalPage.init) }, set: { localPage = $0?.name })) { page in
            VStack(alignment: .leading, spacing: 18) {
                Text(page.name == "privacy" ? model.tr("Privacy Policy", "Política de privacidad") : model.tr("Support", "Ayuda")).font(.title2)
                ScrollView { Text(localText(page.name)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button(model.tr("Done", "Listo")) { localPage = nil }
            }.padding(24).frame(width: 550, height: 430)
        }
    }
    private func open(_ key: String, fallback: String) {
        if let url = ProductLink.webURL(Bundle.main.object(forInfoDictionaryKey: key) as? String) { NSWorkspace.shared.open(url) }
        else { localPage = fallback }
    }
    private func localText(_ name: String) -> String {
        let file = name + (model.language == "es" ? "-es" : "")
        let bundled = Bundle.module.url(forResource: file, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return bundled ?? model.tr("All processing stays on your Mac. Use Sample in Settings to explore a move. Choose a folder for read access and review a proposed move without changing files.", "El procesamiento permanece en tu Mac. Usa Sample en Ajustes para explorar un cambio. Elige una carpeta para leer y revisar un cambio sin modificar archivos.")
    }
    private struct LocalPage: Identifiable { let name: String; var id: String { name } }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "link").font(.largeTitle).foregroundStyle(.mint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LinkSprig").font(.title2.bold())
                    Text(model.tr("Preview a document move", "Previsualiza un cambio de ubicación")).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.sampleMode ? "Sample" : model.tr("Live", "Real")).font(.caption.bold()).padding(7).background(.mint.opacity(0.12), in: Capsule())
            }
            if model.rootName.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.tr("See the impact before moving files", "Revisa el impacto antes de mover archivos")).font(.headline)
                    Text(model.tr("1  See Sample to explore incoming and outgoing links\n2  Choose a documentation folder for read access\n3  Enter a move and review the change plan", "1  Ver Sample para explorar enlaces entrantes y salientes\n2  Elegir una carpeta para acceso de lectura\n3  Proponer un cambio y revisar el plan"))
                    HStack { Button(model.tr("See Sample", "Ver Sample")) { model.setSample(true) }.buttonStyle(.borderedProminent).accessibilityIdentifier("seeSample"); Button(model.tr("Choose folder", "Elegir carpeta")) { model.chooseRoot() } }
                    Text(model.tr("Local processing. Your documents stay unchanged.", "Procesamiento local. Tus documentos permanecen intactos.")).font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack { Label(model.rootName, systemImage: "folder").font(.headline).lineLimit(1); Spacer(); Button(model.tr("Choose again", "Elegir de nuevo")) { model.chooseRoot() } }
                GroupBox(model.tr("Proposed move within this root", "Cambio propuesto dentro de esta carpeta")) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading) { Text(model.tr("Existing path", "Ruta existente")).font(.caption); TextField("guide.md", text: $model.source).accessibilityIdentifier("sourcePath") }
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                        VStack(alignment: .leading) { Text(model.tr("Destination path", "Ruta de destino")).font(.caption); TextField("archive/guide.md", text: $model.destination).accessibilityIdentifier("destinationPath") }
                    }.textFieldStyle(.roundedBorder).padding(8)
                }
                HStack {
                    if model.busy { ProgressView().controlSize(.small); Button(model.tr("Cancel", "Cancelar")) { model.cancel() } }
                    else { Button(model.tr("Preview move", "Previsualizar cambio")) { model.rescan() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [.command]) }
                    Button(model.tr("Reset proposal", "Restablecer propuesta")) { model.resetProposal() }
                    Spacer()
                    Button(model.tr("Copy change plan", "Copiar plan")) { model.copyPlan() }.disabled(model.plan == nil || model.stale || model.busy)
                }
                if let plan = model.plan {
                    ReportView(model: model, plan: plan)
                } else {
                    Label(model.tr("Enter an existing file or folder and a new path. Preview reads the tree and simulates the move.", "Introduce un archivo o carpeta existente y una nueva ruta. La vista previa lee y simula el cambio."), systemImage: "info.circle").foregroundStyle(.secondary).padding(.vertical, 12)
                }
            }
            if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(model.stale ? .orange : .secondary).textSelection(.enabled).accessibilityIdentifier("statusMessage") }
            Divider()
            HStack {
                Button(model.sampleMode ? model.tr("Use live inputs", "Usar datos reales") : model.tr("See Sample", "Ver Sample")) { model.setSample(!model.sampleMode) }
                Spacer(); SettingsLink { Text(model.tr("Settings", "Ajustes")) }; Button(model.tr("Quit", "Salir")) { NSApp.terminate(nil) }
            }
            PolicyLinks(model: model)
        }.padding(24).frame(minWidth: 760, idealWidth: 820, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
    }
}

struct ReportView: View {
    @ObservedObject var model: AppModel
    var plan: Plan
    @State private var showCoverage: Bool
    init(model: AppModel, plan: Plan, expandedCoverage: Bool = false) { self.model = model; self.plan = plan; _showCoverage = State(initialValue: expandedCoverage) }
    private func kind(_ kind: FindingKind) -> String {
        switch kind {
        case .newlyBroken: return model.tr("Newly broken", "Nuevo enlace roto")
        case .changed: return model.tr("Target changes", "Destino diferente")
        case .preexisting: return model.tr("Already missing", "Ya faltaba")
        case .escape: return model.tr("Outside root", "Fuera de carpeta")
        case .unchecked: return model.tr("Unchecked", "Sin verificar")
        case .external: return model.tr("External", "Externo")
        case .fragment: return model.tr("Fragment unchecked", "Fragmento sin verificar")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                metric("\(plan.affected.count)", model.tr("Link changes", "Cambios de enlace"), .mint)
                metric("\(plan.broken.count)", model.tr("Newly broken", "Nuevos enlaces rotos"), .orange)
                metric("\(plan.preexisting.count)", model.tr("Already missing", "Ya faltaban"), .secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(model.status, systemImage: model.stale ? "questionmark.circle" : model.badge).font(.headline)
                    Text(plan.scannedAt.formatted(date: .abbreviated, time: .shortened).replacingOccurrences(of: ":", with: ".")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if plan.affected.isEmpty { Text(model.tr("No link replacements in checked forms. Review coverage below.", "Sin cambios en enlaces comprobados. Revisa la cobertura debajo.")).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(plan.affected) { f in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(f.link.source + " · " + model.tr("line", "línea") + " \(f.link.line)").font(.callout.bold()); Spacer(); Text(kind(f.kind)).font(.caption).foregroundStyle(.orange) }
                            HStack(spacing: 8) { Text(f.link.target).foregroundStyle(.secondary); Image(systemName: "arrow.right"); Text(f.replacement ?? "").foregroundStyle(.mint) }.font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            if f.sourceAfter != f.link.source { Text(model.tr("Source after move", "Origen tras el cambio") + " · " + f.sourceAfter).font(.caption).foregroundStyle(.secondary) }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    DisclosureGroup(isExpanded: $showCoverage) {
                        ForEach(plan.findings.filter { $0.replacement == nil && $0.kind != .external }) { f in
                            HStack(alignment: .top) { Text(kind(f.kind)).foregroundStyle(.secondary); Text("\(f.link.source) · \(f.link.line) · \(f.link.target)").textSelection(.enabled) }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in Text(CoverageKind.localized(warning, spanish: model.language == "es")).font(.caption).foregroundStyle(.orange) }
                    } label: {
                        Text("\(plan.findings.filter { $0.replacement == nil && $0.kind != .external }.count + plan.warnings.count) " + model.tr("coverage items to review", "elementos de cobertura para revisar")).font(.caption)
                    }

                }
            }.frame(minHeight: 110, idealHeight: 230, maxHeight: .infinity)
            Text(model.tr("Dry run only. Fragments, wiki links, HTML and nested syntax are Unchecked. External URLs are not requested.", "Solo simulación. Fragmentos, enlaces wiki, HTML y sintaxis anidada sin verificar. No se solicitan URL externas.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ value: String, _ label: String, _ color: Color) -> some View { VStack(alignment: .leading, spacing: 3) { Text(value).font(.title2.bold()).foregroundStyle(color); Text(label).font(.caption).foregroundStyle(.secondary) } }
}
struct PanelView: View {
    @ObservedObject var model: AppModel
    var openWindow: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("LinkSprig", systemImage: "link").font(.headline); Spacer(); if model.sampleMode { Text("Sample").font(.caption.bold()).foregroundStyle(.mint) } }
            Label(model.status, systemImage: model.badge).font(.title3.bold())
            if let plan = model.plan {
                Text("\(plan.affected.count) " + model.tr("links need replacement", "enlaces necesitan cambios"))
                Text(model.tr("Last check", "Última revisión") + " · " + plan.scannedAt.formatted(date: .abbreviated, time: .shortened).replacingOccurrences(of: ":", with: ".")).font(.caption).foregroundStyle(.secondary)
            } else { Text(model.tr("See Sample or choose your documents to preview a move.", "Ver Sample o elegir documentos para previsualizar un cambio.")).font(.callout).foregroundStyle(.secondary) }
            Button(model.tr("Review move", "Revisar cambio"), action: openWindow).buttonStyle(.borderedProminent)
            if model.plan == nil { Button(model.tr("See Sample", "Ver Sample")) { model.setSample(true); openWindow() } }
            HStack { SettingsLink { Text(model.tr("Settings", "Ajustes")) }; Spacer(); Button(model.tr("Quit", "Salir")) { NSApp.terminate(nil) } }
            PolicyLinks(model: model)
        }.padding(18).frame(width: 350)
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack { Text(model.tr("LinkSprig settings", "Ajustes de LinkSprig")).font(.title2.bold()); Spacer(); if model.sampleMode { Text("Sample").font(.caption.bold()).foregroundStyle(.mint) } }
                GroupBox(model.tr("Basic", "Básicos")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(model.rootName.isEmpty ? model.tr("No documentation root", "Sin carpeta de documentación") : model.rootName).lineLimit(1); Spacer(); Button(model.tr("Choose folder", "Elegir carpeta")) { model.chooseRoot() } }
                        Toggle(model.tr("Include image links", "Incluir enlaces de imágenes"), isOn: $model.includeImages)
                        Toggle(model.tr("Sample mode", "Modo Sample"), isOn: Binding(get: { model.sampleMode }, set: { model.setSample($0) })).accessibilityIdentifier("sampleToggle")
                        if model.sampleMode { Button(model.tr("Reset Sample", "Restablecer Sample")) { model.resetSample() } }
                    }.padding(10)
                }
                GroupBox(model.tr("Advanced", "Avanzados")) {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(model.tr("Excluded folder names separated by commas", "Carpetas excluidas separadas por comas")).font(.caption)
                        TextField(".git, node_modules", text: $model.excludedNames).textFieldStyle(.roundedBorder)
                        HStack { Text(model.tr("Existing path", "Ruta existente")); TextField("guide.md", text: $model.source) }.textFieldStyle(.roundedBorder)
                        HStack { Text(model.tr("Destination", "Destino")); TextField("archive/guide.md", text: $model.destination) }.textFieldStyle(.roundedBorder)
                        HStack {
                            Text(model.tr("Open panel shortcut", "Atajo para abrir panel"))
                            ShortcutRecorder(model: model).frame(width: 200, height: 26)
                            Button(model.tr("Disable", "Desactivar")) { model.shortcutKey = UInt32.max }
                        }

                        if !model.shortcutError.isEmpty { Text(model.shortcutError).font(.caption).foregroundStyle(.orange) }
                        Picker(model.tr("Appearance", "Apariencia"), selection: $model.appearance) { Text(model.tr("System", "Sistema")).tag("system"); Text(model.tr("Light", "Claro")).tag("light"); Text(model.tr("Dark", "Oscuro")).tag("dark") }
                        Picker(model.tr("Language", "Idioma"), selection: $model.language) { Text("English").tag("en"); Text("Español").tag("es") }
                    }.padding(10)
                }
                Text(model.tr("Read access comes only from choosing a folder. All scans and move plans stay on this computer. Resetting a proposal never changes documents.", "El acceso de lectura se obtiene al elegir una carpeta. Escaneos y planes permanecen aquí. Restablecer la propuesta nunca modifica documentos.")).font(.caption).foregroundStyle(.secondary)
                HStack { Button(model.tr("Clear local data", "Borrar datos locales")) { model.clearLocalData() }; Spacer(); Text("1.0.0").font(.caption).foregroundStyle(.secondary) }
                PolicyLinks(model: model)
            }.padding(24)
        }.frame(width: 610, height: 710)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> RecorderButton { let button = RecorderButton(); button.bezelStyle = .rounded; return button }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.model = model
        if !button.recording { button.title = model.shortcutKey == UInt32.max ? model.tr("Disabled · Record", "Desactivado · Grabar") : button.shortcutTitle }
    }
}
final class RecorderButton: NSButton {
    weak var model: AppModel?
    var recording = false
    private var previousKey = UInt32.max
    override var acceptsFirstResponder: Bool { true }
    var shortcutTitle: String {
        guard let model else { return "" }
        let flags = model.shortcutModifiers
        return (flags & 4096 != 0 ? "⌃ " : "") + (flags & 256 != 0 ? "⌘ " : "") + (flags & 2048 != 0 ? "⌥ " : "") + (flags & 512 != 0 ? "⇧ " : "") + model.tr("Key", "Tecla") + " \(model.shortcutKey)"
    }
    override func mouseDown(with event: NSEvent) {
        previousKey = model?.shortcutKey ?? UInt32.max; model?.shortcutKey = UInt32.max
        recording = true; title = model?.tr("Press a shortcut", "Pulsa un atajo") ?? ""; window?.makeFirstResponder(self)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording, let model else { super.keyDown(with: event); return }
        if event.keyCode == 53 { model.shortcutKey = previousKey; recording = false; title = model.shortcutKey == UInt32.max ? model.tr("Disabled · Record", "Desactivado · Grabar") : shortcutTitle; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) else { title = model.tr("Use Command or Control", "Usa Comando o Control"); return }
        model.shortcutKey = UInt32.max
        model.shortcutModifiers = (flags.contains(.command) ? 256 : 0) | (flags.contains(.option) ? 2048 : 0) | (flags.contains(.shift) ? 512 : 0) | (flags.contains(.control) ? 4096 : 0)
        model.shortcutKey = UInt32(event.keyCode); recording = false; title = shortcutTitle
    }
}
