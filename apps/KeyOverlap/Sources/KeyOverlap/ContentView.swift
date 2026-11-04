import SwiftUI
import KeyOverlapCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var editing: ShortcutRecord?
    @State private var showEditor = false
    @State private var showImport = false
    @State private var showContexts = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text("KeyOverlap").font(.system(size: 28, weight: .bold))
                        if model.sampleMode { SampleBadge(language: model.language) }
                    }
                    Text(model.l("Check your plan before changing shortcuts", "Revisa el plan antes de cambiar atajos"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.sampleMode {
                    LabeledButton(model.l("Use my plan", "Usar mi plan")) { model.toggleSample(false) }
                } else { LabeledButton(model.l("Try Sample", "Probar ejemplo")) { model.toggleSample(true) } }
                SettingsLink { Image(systemName: "gearshape").font(.title3) }
                    .accessibilityLabel(model.l("Settings", "Ajustes")).help(model.l("Settings with Command comma", "Ajustes con Comando coma"))
            }
            HStack(spacing: 12) {
                summary(model.definiteCount, model.l("Definite overlaps", "Cruces seguros"), .orange)
                summary(model.possibleCount, model.l("Possible overlaps", "Cruces posibles"), .purple)
                summary(model.pairs.filter { $0.kind == .separate }.count, model.l("Separate scopes", "Ámbitos separados"), .green)
            }
            if let error = model.storageError, !model.sampleMode {
                HStack { Text(error).font(.caption).fixedSize(horizontal: false, vertical: true); Spacer(); LabeledButton(model.l("Retry", "Reintentar")) { model.reload() } }
                    .padding(10).background(Color.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let message = model.message {
                HStack(alignment: .top) { Text(message).font(.caption).textSelection(.enabled); Spacer(); Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel(model.l("Dismiss message", "Cerrar mensaje")) }
                    .padding(8).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Picker(model.l("Planner view", "Vista del plan"), selection: $model.tab) {
                Text(model.l("Plan", "Plan")).tag(0)
                Text(model.l("Candidate", "Candidato")).tag(1)
                Text(model.l("Changes", "Cambios")).tag(2)
            }.pickerStyle(.segmented)
            Group {
                if model.tab == 0 { planView }
                else if model.tab == 1 { CandidateView(model: model) }
                else { ChangesView(model: model) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(model.l("Checks only records in this plan", "Solo comprueba los registros de este plan")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                PolicyLinks(model: model)
                LabeledButton(model.l("Quit", "Salir")) { NSApp.terminate(nil) }.font(.caption)
            }
        }.padding(24).frame(width: 940, height: 740)
            .sheet(isPresented: $showEditor) { RecordEditor(model: model, record: editing) }
            .sheet(isPresented: $showImport) { ImportView(model: model) }
            .sheet(isPresented: $showContexts) { ContextView(model: model) }
    }
    private func summary(_ count: Int, _ label: String, _ color: Color) -> some View {
        HStack { Text("\(count)").font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundStyle(color); Text(label).font(.subheadline); Spacer() }
            .padding(12).frame(maxWidth: .infinity).background(color.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
    }
    private var planView: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LabeledButton(model.l("Create shortcut", "Crear atajo")) { editing = nil; showEditor = true }.buttonStyle(.borderedProminent)
                    LabeledButton(model.l("Import plan", "Importar plan")) { showImport = true }
                    Spacer()
                }
                TextField(model.l("Search command, app or chord", "Buscar comando, app o atajo"), text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(model.l("Search the plan", "Buscar en el plan"))
                if model.plan.records.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "keyboard").font(.system(size: 44)).foregroundStyle(.secondary)
                        Text(model.l("Your plan starts here", "Tu plan empieza aquí")).font(.title3.bold())
                        Text(model.l("Create shortcut or Import plan. Enter the shortcuts you want to compare and give each an app scope.", "Crea un atajo o importa un plan. Introduce los atajos que quieres comparar y su ámbito de aplicación."))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        LabeledButton(model.l("Try Sample", "Probar ejemplo")) { model.toggleSample(true) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            let filtered = OverlapEngine.search(model.plan.records, query: query)
                            if filtered.isEmpty { Text(model.l("No matching records. Clear the search to see your plan.", "No hay coincidencias. Borra la búsqueda para ver el plan.")).foregroundStyle(.secondary).padding() }
                            ForEach(filtered) { row in
                                Button { editing = row; showEditor = true } label: {
                                    RecordRow(row: row, model: model)
                                }.buttonStyle(.plain).accessibilityLabel(model.l("Edit ", "Editar ") + row.searchText)
                            }
                        }
                    }
                }
            }.frame(width: 428)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(model.l("Scope comparison", "Comparación de ámbitos")).font(.headline); Spacer(); LabeledButton(model.l("Contexts", "Contextos")) { showContexts = true } }
                Text(model.l("Same chord does not always mean conflict", "El mismo atajo no siempre implica conflicto")).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 10) {
                        let comparison = PlanComparison(pairs: model.pairs, showPossible: model.showPossible)
                        if comparison.isClear {
                            Text(model.l("No overlap in this plan", "Sin cruces en este plan")).font(.headline).padding(.top, 50)
                            Text(model.l("Results use your declared scopes. Shortcuts outside this plan are unknown.", "El resultado usa los ámbitos declarados. No se conocen los atajos fuera del plan.")).foregroundStyle(.secondary)
                        }
                        if comparison.hasHiddenPossible {
                            Text(model.l("Possible overlaps are hidden. Enable Show possible overlaps in Settings to review them.", "Los cruces posibles están ocultos. Activa Mostrar cruces posibles en Ajustes para revisarlos.")).foregroundStyle(.purple).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(comparison.visible) { OverlapCard(overlap: $0, model: model) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity)
        }
    }
}

struct SampleBadge: View {
    let language: String
    var body: some View { Text(PlanText.translate("Sample", language: language)).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 4).background(Color.teal.opacity(0.16)).foregroundStyle(.teal).clipShape(Capsule()).accessibilityLabel(PlanText.translate("Sample", language: language)) }
}
@MainActor
func scopeLabel(_ row: ShortcutRecord, _ model: AppModel) -> String {
    (row.scope == "*" ? model.l("Global", "Global") : row.scope ?? model.l("Scope unknown", "Ámbito desconocido")) + (row.context.map { " · " + $0 } ?? "")
}
struct OverlapCard: View {
    let overlap: Overlap
    @ObservedObject var model: AppModel
    private var color: Color { overlap.kind == .definite ? .orange : overlap.kind == .possible ? .purple : .green }
    private var title: String {
        switch overlap.kind {
        case .definite: return model.l("Definite overlap", "Cruce seguro")
        case .possible: return model.l("Possible overlap", "Cruce posible")
        case .separate: return model.l("Separate scope", "Ámbito separado")
        }
    }
    private var reason: String {
        if overlap.exclusive { return model.l("Exclusive contexts declared by you", "Contextos excluyentes declarados por ti") }
        switch overlap.kind {
        case .definite: return model.l("Scopes can be active together", "Los ámbitos pueden estar activos a la vez")
        case .possible: return model.l("Add missing app scope to resolve", "Añade el ámbito que falta para resolverlo")
        case .separate: return model.l("Different foreground app scopes", "Ámbitos de distintas apps en primer plano")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title).font(.caption.bold()).foregroundStyle(color); Spacer(); Text(overlap.first.chord.display(language: model.language)).font(.system(.subheadline, design: .monospaced).bold()) }
            Text(overlap.first.command + " · " + overlap.second.command).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(color.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .combine)
    }
}

struct CandidateView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.l("Test a proposed shortcut", "Prueba un atajo propuesto")).font(.title2.bold())
                Text(model.l("Preview against your saved baseline. This check changes no records.", "Compara con el plan guardado. Esta comprobación no cambia registros.")).foregroundStyle(.secondary)
                field(model.l("Chord", "Atajo"), "command+shift+5", $model.candidateChord)
                field(model.l("App scope", "Ámbito de aplicación"), model.l("App name or * for global", "Nombre de app o * para global"), $model.candidateScope)
                field(model.l("Context optional", "Contexto opcional"), model.l("Example Edit", "Ejemplo Edición"), $model.candidateContext)
                Text(model.l("Blank scope means unknown. A global scope overlaps every app. Only contexts you declare exclusive are treated as separate.", "Un ámbito vacío es desconocido. El ámbito global cruza todas las apps. Solo se separan los contextos que declares excluyentes.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.frame(width: 390)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch model.candidate {
                    case .failure(let error):
                        Label(model.l("Check the chord and scope", "Revisa el atajo y el ámbito"), systemImage: "exclamationmark.circle").font(.headline).foregroundStyle(.orange)
                        Text(model.errorText(error)).foregroundStyle(.secondary)
                    case .success(let results):
                        let conflicts = results.filter { $0.kind != .separate }
                        Label(conflicts.isEmpty ? model.l("No overlap in this plan", "Sin cruces en este plan") : model.l("Candidate overlaps this plan", "El candidato cruza este plan"), systemImage: conflicts.isEmpty ? "checkmark.circle" : "exclamationmark.triangle").font(.headline).foregroundStyle(conflicts.isEmpty ? .green : .orange)
                        Text(model.l("Systemwide availability is unknown", "La disponibilidad fuera del plan es desconocida")).font(.caption).foregroundStyle(.secondary)
                        ForEach(results) { OverlapCard(overlap: $0, model: model) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.top, 8)
    }
    private func field(_ name: String, _ prompt: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(name).font(.subheadline.bold()); TextField(prompt, text: binding).textFieldStyle(.roundedBorder).accessibilityLabel(name) }
    }
}

struct ChangesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.l("Before and after in your plan", "Antes y después en tu plan")).font(.title2.bold())
                    Text(model.l("Target apps are changed manually by you", "Tú cambias las apps de destino manualmente")).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 18) {
                comparison(model.l("Baseline", "Plan inicial"), model.pairs)
                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel(model.l("Compared with", "Comparado con"))
                comparison(model.l("Proposed", "Propuesto"), model.afterPairs)
            }
            if model.plan.replacements.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch").font(.largeTitle).foregroundStyle(.secondary)
                    Text(model.l("No staged changes", "Sin cambios propuestos")).font(.headline)
                    Text(model.l("Open a record in Plan and stage a replacement. The baseline stays separate until you apply it.", "Abre un registro en Plan y propone un reemplazo. El plan inicial permanece separado hasta aplicarlo.")).foregroundStyle(.secondary)
                    LabeledButton(model.l("Open Plan", "Abrir plan")) { model.tab = 0 }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.plan.replacements) { change in
                            if let row = model.plan.records.first(where: { $0.id == change.recordID }) {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) { Text(row.command).font(.headline); Text(scopeLabel(row, model)).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Text(row.chord.display(language: model.language)).foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    Text(change.chord.display(language: model.language)).foregroundStyle(.teal).fontWeight(.semibold)
                                    LabeledButton(model.l("Remove", "Quitar")) { model.unstage(row.id) }
                                }.padding(16).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                Text(model.l("Copy the checklist before applying. Applying updates these local records and clears staged changes. It never configures another app.", "Copia la lista antes de aplicar. Aplicar actualiza estos registros locales y borra los cambios propuestos. No configura otra app.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    LabeledButton(model.l("Copy change checklist", "Copiar lista de cambios")) { model.copy(model.plan.checklist(language: model.language)) }
                    Spacer()
                    LabeledButton(model.l("Apply to local records", "Aplicar a registros locales")) { model.apply() }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(.top, 8)
    }
    private func comparison(_ name: String, _ pairs: [Overlap]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).font(.headline)
            Text("\(pairs.filter { $0.kind == .definite }.count) " + model.l("definite", "seguros") + " · \(pairs.filter { $0.kind == .possible }.count) " + model.l("possible", "posibles")).font(.system(size: 21, weight: .medium))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.teal.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct RecordEditor: View {
    @ObservedObject var model: AppModel
    let record: ShortcutRecord?
    @Environment(\.dismiss) private var dismiss
    @State private var command: String
    @State private var chord: String
    @State private var scope: String
    @State private var context: String
    @State private var error: String?
    init(model: AppModel, record: ShortcutRecord?) {
        self.model = model; self.record = record
        _command = State(initialValue: record?.command ?? "")
        _chord = State(initialValue: record?.chord.text ?? "command+k")
        _scope = State(initialValue: RecordDefaults.scope(for: record, defaultScope: model.defaultScope))
        _context = State(initialValue: record?.context ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(record == nil ? model.l("Create shortcut", "Crear atajo") : model.l("Edit shortcut or stage replacement", "Editar atajo o proponer reemplazo")).font(.title2.bold())
            TextField(model.l("Command name", "Nombre del comando"), text: $command).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("Command name", "Nombre del comando"))
            TextField("command+option+k", text: $chord).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("Shortcut chord", "Atajo de teclado"))
            Text(model.l("Modifiers use command, option, shift and control. Use one key such as k, space, return or F5.", "Los modificadores usan command, option, shift y control. Usa una tecla como k, space, return o F5.")).font(.caption).foregroundStyle(.secondary)
            TextField(model.l("App scope or * for global", "Ámbito de app o * para global"), text: $scope).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("App scope", "Ámbito de aplicación"))
            TextField(model.l("Context optional", "Contexto opcional"), text: $context).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("Context", "Contexto"))
            Text(model.l("Leave scope blank for unknown. Contexts belong to a named app. Global shortcuts have no app context.", "Deja el ámbito vacío si es desconocido. Los contextos pertenecen a una app. Los atajos globales no tienen contexto de app.")).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let record {
                LabeledButton(model.l("Stage chord replacement", "Proponer reemplazo del atajo")) {
                    do { try model.stage(record.id, Chord.parse(chord)); dismiss() } catch { self.error = model.errorText(error) }
                }
                Text(model.l("Staging changes only the chord. Command and scope edits use Save record.", "Proponer solo cambia el atajo. Guarda el registro para editar el comando o el ámbito.")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let record { LabeledButton(model.l("Delete record", "Borrar registro"), role: .destructive) { model.remove(record.id); dismiss() } }
                Spacer()
                LabeledButton(model.l("Cancel", "Cancelar")) { dismiss() }.keyboardShortcut(.cancelAction)
                LabeledButton(model.l("Save record", "Guardar registro")) {
                    do {
                        let parsed = try Chord.parse(chord)
                        let row = try ShortcutRecord(id: record?.id ?? UUID(), command: command, key: parsed.key, modifiers: parsed.modifiers, scope: scope, context: context)
                        model.save(row)
                        if model.sampleMode || model.storageError == nil { dismiss() }
                    } catch { self.error = model.errorText(error) }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 580)
    }
}

struct ImportView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.l("Import a shortcut plan", "Importar un plan de atajos")).font(.title2.bold())
            Text(model.l("Import replaces the baseline only after every row validates. Invalid rows leave existing records unchanged. Staged changes are cleared after a successful import.", "La importación reemplaza el plan inicial solo cuando cada fila es válida. Las filas inválidas no cambian los registros. Una importación válida borra los cambios propuestos."))
            Text(model.l("Strict schema", "Esquema estricto")).font(.headline)
            Text(model.l("JSON array with exactly five fields in every row. command and key are strings. modifiers is an array of unique command, option, shift or control strings. scope and context are strings or null. Use * for global scope and null for unknown. Global and unknown scopes cannot have contexts. Error indices start at zero.", "Matriz JSON con exactamente cinco campos por fila. command y key son cadenas. modifiers contiene cadenas únicas command, option, shift o control. scope y context son cadenas o null. Usa * para el ámbito global y null para desconocido. Los ámbitos globales y desconocidos no admiten contextos. Los índices de error empiezan en cero.")).font(.subheadline)
            ScrollView { Text(PlanImport.template).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 135).padding(12).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 9))
            Text(model.l("The native file picker grants read access only to your selected file. No typing or other apps are inspected.", "El selector nativo permite leer solo el archivo elegido. No se inspecciona la escritura ni otras apps.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                LabeledButton(model.l("Copy template", "Copiar plantilla")) { model.copy(PlanImport.template) }
                Spacer()
                LabeledButton(model.l("Done", "Listo")) { dismiss() }
                LabeledButton(model.l("Choose JSON file", "Elegir archivo JSON")) { dismiss(); DispatchQueue.main.async { model.importFile() } }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 650)
    }
}

struct ContextView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var app = ""
    @State private var first = ""
    @State private var second = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.l("Declare exclusive contexts", "Declarar contextos excluyentes")).font(.title2.bold())
            Text(model.l("This is your assumption about an app. KeyOverlap does not infer app behavior. Declare a pair only when those contexts cannot be active together.", "Esta es tu suposición sobre una app. KeyOverlap no deduce su comportamiento. Declara un par solo cuando los contextos no pueden estar activos a la vez.")).foregroundStyle(.secondary)
            TextField(model.l("App name", "Nombre de app"), text: $app).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("App name", "Nombre de app"))
            HStack {
                TextField(model.l("First context", "Primer contexto"), text: $first).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("First context", "Primer contexto"))
                TextField(model.l("Second context", "Segundo contexto"), text: $second).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("Second context", "Segundo contexto"))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            LabeledButton(model.l("Declare pair", "Declarar par")) {
                do { model.addContext(try ExclusiveContexts(app: app, first: first, second: second)); error = nil; app = ""; first = ""; second = "" }
                catch { self.error = model.errorText(error) }
            }
            ScrollView {
                VStack(spacing: 10) {
                    if model.plan.contexts.isEmpty { Text(model.l("No exclusive context pairs declared", "Sin pares excluyentes declarados")).foregroundStyle(.secondary) }
                    ForEach(model.plan.contexts) { pair in
                        HStack { VStack(alignment: .leading) { Text(pair.app).font(.headline); Text(pair.first + " · " + pair.second).foregroundStyle(.secondary) }; Spacer(); LabeledButton(model.l("Remove", "Quitar")) { model.removeContext(pair.id) } }.padding(10).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(height: 150)
            HStack { Spacer(); LabeledButton(model.l("Done", "Listo")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 620)
    }
}

struct PolicyLinks: View {
    @ObservedObject var model: AppModel
    @State private var localPolicy: Bool?
    var body: some View {
        HStack(spacing: 14) {
            LabeledButton(model.l("Privacy Policy", "Política de privacidad")) { open(privacy: true) }
            LabeledButton(model.l("Support", "Ayuda")) { open(privacy: false) }
        }.font(.caption)
        .sheet(isPresented: Binding(get: { localPolicy != nil }, set: { if !$0 { localPolicy = nil } })) {
            VStack(alignment: .leading, spacing: 18) {
                Text(localPolicy == true ? model.l("Privacy Policy", "Política de privacidad") : model.l("Support", "Ayuda")).font(.title2.bold())
                Text(localPolicy == true ? model.l(
                    "Shortcut plans and imports stay in the app container on your Mac. KeyOverlap does not listen to typing or inspect other apps. There are no accounts, analytics, cloud sync or network requests. Import reads only the JSON file you select. Clipboard copies happen only on command. Clear local plans in Settings deletes records, contexts and staged changes for the active plan. Preferences remain.",
                    "Los planes y las importaciones quedan en el contenedor de la app en tu Mac. KeyOverlap no escucha tu escritura ni inspecciona otras apps. No hay cuentas, analítica, sincronización ni solicitudes de red. La importación solo lee el JSON que eliges. Las copias al portapapeles se hacen por orden tuya. Borrar planes locales en Ajustes elimina registros, contextos y cambios propuestos del plan activo. Las preferencias se conservan.") : model.l(
                    "Create shortcuts or choose Import plan to see the JSON schema and copy a template. Blank scope means unknown and * means global. Try Sample or restore its fixtures in Settings to explore all planner features. If the opening shortcut fails, use the menu bar button and register a different chord in Settings. Changes apply only to local records. Set shortcuts manually in each target app.",
                    "Crea atajos o elige Importar plan para ver el esquema JSON y copiar una plantilla. Un ámbito vacío es desconocido y * es global. Prueba el ejemplo o restaura sus datos en Ajustes para explorar todas las funciones. Si falla el atajo de apertura, usa la barra de menús y registra otro en Ajustes. Los cambios solo se aplican a registros locales. Configura los atajos manualmente en cada app."))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text("© 2026 Michael Lip").font(.caption).foregroundStyle(.secondary)
                HStack { Spacer(); LabeledButton(model.l("Done", "Listo")) { localPolicy = nil } }
            }.padding(24).frame(width: 580)
        }
    }
    private func open(privacy: Bool) {
        // The builder supplies the host from brand.env. Keep policy paths in the binary for the gate.
        let key = privacy ? "MASPrivacyPolicyURL" : "MASSupportURL"
        let path = privacy ? "/apps/keyoverlap/privacy/" : "/apps/keyoverlap/support/"
        if let url = PolicyDestination.webURL(Bundle.main.object(forInfoDictionaryKey: key) as? String), url.path == path,
           NSWorkspace.shared.open(url) { return }
        localPolicy = privacy
    }
}

struct RecordRow: View {
    let row: ShortcutRecord
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.command).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(scopeLabel(row, model)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.chord.display(language: model.language)).font(.system(size: 18, weight: .medium, design: .monospaced)).foregroundStyle(.primary)
        }.padding(.horizontal, 11).padding(.vertical, 5).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .combine)
    }
}
