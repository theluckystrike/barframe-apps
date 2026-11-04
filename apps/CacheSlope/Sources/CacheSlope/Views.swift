import SwiftUI
import ServiceManagement
import CacheSlopeCore

func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
struct ContentView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: model.symbol).font(.title).foregroundStyle(.teal).accessibilityLabel(model.state)
                VStack(alignment: .leading) { Text("CacheSlope").font(.title.bold()); Text(model.tr("Find folders that keep growing", "Descubre qué carpetas crecen")).foregroundStyle(.secondary) }
                Spacer()
                if model.sample { Text("Sample").font(.headline).padding(8).background(.teal.opacity(0.2), in: Capsule()) }
                SettingsLink { Image(systemName: "gearshape") }.accessibilityLabel(model.tr("Settings", "Ajustes"))
            }
            HStack {
                ActionButton(model.tr("Add folder", "Añadir carpeta")) { model.choose() }.disabled(model.sample || model.scanning)
                LabeledToggle(model.tr("Sample mode", "Modo de muestra"), isOn: Binding(get: { model.sample }, set: { model.toggleSample($0) })).toggleStyle(.switch).disabled(model.scanning)
                Spacer()
            }
            if model.roots.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.tr("Start with a folder you choose", "Empieza con una carpeta elegida")).font(.title2.bold())
                    Text(model.tr("Read only permission lets CacheSlope measure logical file sizes. File contents stay untouched. Take a snapshot now and another after your work session.", "El permiso de lectura permite medir tamaños lógicos sin leer contenido. Guarda una captura ahora y otra al terminar tu trabajo."))
                    ActionButton(model.tr("Try Sample", "Probar muestra")) { model.toggleSample(true) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Picker(model.tr("Selected folder", "Carpeta seleccionada"), selection: $model.selected) { ForEach(model.roots) { Text($0.name).tag(Optional($0.id)) } }.disabled(model.scanning)
                HStack { Text(model.state).font(.title2.bold()); Spacer(); if model.scanning { ProgressView().controlSize(.small); ActionButton(model.tr("Cancel", "Cancelar")) { model.cancel() } } else { ActionButton(model.tr("Take snapshot", "Guardar captura")) { model.scan() }.buttonStyle(.borderedProminent).tint(.teal) } }
                if model.denied { ActionButton(model.tr("Choose folder again", "Selecciona la carpeta de nuevo")) { model.choose(replace: true) } }
                if let current = model.pair.0 {
                    HStack(alignment: .firstTextBaseline) { Text(bytes(current.total)).font(.system(size: 36, weight: .semibold, design: .rounded)); Text(model.tr("logical file bytes", "bytes lógicos de archivos")).foregroundStyle(.secondary) }
                    Text(current.date.formatted()).font(.caption).foregroundStyle(.secondary)
                    if let baseline = model.pair.1 { Text(model.tr("Compared with", "Comparado con") + " " + baseline.date.formatted() + (model.root?.baseline != nil ? model.tr(" · Pinned baseline", " · Referencia fijada") : "")).font(.caption) }
                    if Date().timeIntervalSince(current.date) > 86400 { Text(model.tr("Snapshot is older than a day. Scan to refresh.", "La captura tiene más de un día. Analiza para actualizar.")).foregroundStyle(.orange) }
                }
                if let last = model.root?.history.last, !last.complete {
                    VStack(alignment: .leading) {
                        Text(model.tr("Partial totals are not compared", "Los totales parciales no se comparan")).font(.headline)
                        Text(bytes(last.total) + model.tr(" observed · ", " observados · ") + String(last.issues.count) + model.tr(" skipped entries", " elementos omitidos"))
                        if last.cancelled { Text(model.tr("Scan cancelled", "Análisis cancelado")) }
                        ForEach(Array(last.issues.prefix(3).enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption) }
                        Text(model.tr("The report below uses only complete snapshots", "El informe inferior solo usa capturas completas")).font(.caption)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                if !model.changes.isEmpty {
                    HStack { Text(model.tr("Folder", "Carpeta")); Spacer(); Text(model.tr("Size and change", "Tamaño y cambio")) }.font(.caption).foregroundStyle(.secondary)
                    ForEach(model.changes.prefix(7)) { change in
                        HStack {
                            Button { model.reveal(change.name) } label: { Label(change.name, systemImage: "folder") }.buttonStyle(.plain).accessibilityLabel(model.tr("Reveal in Finder", "Mostrar en Finder") + " " + change.name).help(model.tr("Reveal in Finder", "Mostrar en Finder"))
                            Spacer()
                            Text(bytes(change.bytes)).monospacedDigit().foregroundStyle(.secondary)
                            Text((change.delta >= 0 ? "+" : "−") + bytes(abs(change.delta))).monospacedDigit().foregroundStyle(change.delta > 0 ? .orange : .teal).frame(width: 120, alignment: .trailing)
                        }.padding(.vertical, 5)
                        Divider()
                    }
                    if model.changes.count > 7 { Text(model.tr("Copy the report to see every folder", "Copia el informe para ver todas las carpetas")).font(.caption) }
                } else if model.pair.0 != nil { Text(model.tr("Take another complete snapshot to see growth", "Guarda otra captura completa para ver los cambios")).foregroundStyle(.secondary) }
                HStack {
                    ActionButton(model.tr("Pin baseline", "Fijar referencia")) { model.pin() }.disabled(model.pair.0 == nil)
                    ActionButton(model.tr("Undo baseline", "Deshacer referencia")) { model.undoPin() }.disabled(!model.canUndo)
                    Spacer()
                    ActionButton(model.tr("Copy report", "Copiar informe")) { model.copyReport() }.disabled(model.pair.0 == nil)
                }
            }
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if !model.shortcutError.isEmpty { Text(model.shortcutError).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack { PolicyLinks(model: model); Spacer(); Text(model.tr("Read only · Local history", "Solo lectura · Historial local")).font(.caption).foregroundStyle(.secondary) }
        }.padding(24).frame(width: 690)
    }
}
struct PolicyLinks: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack {
            Link(model.tr("Privacy Policy", "Política de privacidad"), destination: URL(string: "https://barframe.com/apps/cacheslope/privacy/")!).accessibilityLabel(model.tr("Privacy Policy", "Política de privacidad"))
            Link(model.tr("Support", "Ayuda"), destination: URL(string: "https://barframe.com/apps/cacheslope/support/")!).accessibilityLabel(model.tr("Support", "Ayuda"))
        }.font(.caption)
    }
}
struct SettingsView: View {
    @ObservedObject var model: Model
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.tr("CacheSlope settings", "Ajustes de CacheSlope")).font(.title2.bold())
            LabeledToggle("Español", isOn: $model.spanish)
            LabeledToggle(model.tr("Launch at login", "Abrir al iniciar sesión"), isOn: Binding(get: { login }, set: { value in
                do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; login = SMAppService.mainApp.status == .enabled; error = SMAppService.mainApp.status == .requiresApproval ? model.tr("Approve in System Settings Login Items", "Autoriza en Ajustes del Sistema") : "" } catch { self.error = error.localizedDescription }
            }))
            if !error.isEmpty { Text(error).foregroundStyle(.orange) }
            LabeledToggle(model.tr("Sample mode", "Modo de muestra"), isOn: Binding(get: { model.sample }, set: { model.toggleSample($0) })).disabled(model.scanning)
            if model.sample { ActionButton(model.tr("Reset Sample", "Restablecer muestra")) { model.toggleSample(true) } }
            Picker(model.tr("Scan selected folder while awake", "Analizar carpeta seleccionada al estar activo"), selection: $model.interval) {
                Text(model.tr("Manual only", "Solo manual")).tag(0); Text(model.tr("Every 15 minutes", "Cada 15 minutos")).tag(15); Text(model.tr("Every hour", "Cada hora")).tag(60)
            }.onChange(of: model.interval) { model.schedule() }
            Picker(model.tr("Global report shortcut", "Atajo global del informe"), selection: $model.shortcutChoice) { Text("⇧⌘C").tag(0); Text("⇧⌘G").tag(1) }.onChange(of: model.shortcutChoice) { model.registerShortcut() }
            if !model.shortcutError.isEmpty { Text(model.shortcutError).foregroundStyle(.orange) }
            Stepper(model.tr("History per folder", "Historial por carpeta") + "  \(model.retention)", value: $model.retention, in: 2...100).onChange(of: model.retention) { UserDefaults.standard.set(model.retention, forKey: "retention"); model.trim() }
            if let root = model.root {
                Text(model.tr("Selected folder", "Carpeta seleccionada") + " · " + root.name).font(.headline)
                Picker(model.tr("Attention when a folder grows by", "Avisar cuando una carpeta crezca más de"), selection: Binding(get: { root.threshold }, set: { value in if let i = model.index { model.roots[i].threshold = value; model.persist() } })) {
                    Text(model.tr("Off", "Desactivado")).tag(Int64(0)); Text("100 MB").tag(Int64(100_000_000)); Text("500 MB").tag(Int64(500_000_000)); Text("1 GB").tag(Int64(1_000_000_000))
                }
                HStack { ActionButton(model.tr("Pin newest complete snapshot", "Fijar última captura completa")) { model.pin() }.disabled(model.pair.0 == nil); ActionButton(model.tr("Use previous scan", "Usar captura anterior")) { model.unpin() } }
                Text(model.tr("Saved snapshots", "Capturas guardadas") + "  \(root.history.count)")
                ScrollView { VStack(alignment: .leading) { ForEach(root.history.reversed()) { snapshot in Text(snapshot.date.formatted() + " · " + bytes(snapshot.total) + " · " + (snapshot.complete ? model.tr("Complete", "Completa") : model.tr("Partial", "Parcial"))).font(.caption) } } }.frame(height: 60)
                ActionButton(model.tr("Remove selected folder and history", "Eliminar carpeta seleccionada e historial")) { model.remove() }.disabled(model.scanning)
            }
            ActionButton(model.tr("Clear all local folders and history", "Borrar todas las carpetas y el historial local")) { model.clear() }.disabled(model.scanning)
            Text(model.tr("Only chosen folders are scanned. Symbolic links and cloud files not downloaded are skipped. These scans are partial and never used for comparisons.", "Solo se analizan carpetas elegidas. Se omiten enlaces simbólicos y archivos en la nube no descargados. Esos análisis son parciales y no se comparan.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider(); PolicyLinks(model: model)
            HStack { Text("CacheSlope 1.0.0").font(.caption); Spacer(); ActionButton(model.tr("Quit", "Salir")) { NSApp.terminate(nil) } }
        }.padding(24).frame(width: 600)
    }
}

struct ActionButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View { Button(action: action) { Text(title) }.accessibilityLabel(Text(title)) }
}
struct LabeledToggle: View {
    let title: String
    let isOn: Binding<Bool>
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; self.isOn = isOn }
    var body: some View { Toggle(title, isOn: isOn).accessibilityLabel(Text(title)) }
}
