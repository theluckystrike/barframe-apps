import SwiftUI
import ServiceManagement
import CheckHarborCore
func AccessibleButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
    Button(role:role,action:action) { Text(title) }.accessibilityLabel(Text(title))
}
func AccessibleToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn:isOn) { Text(title) }.accessibilityLabel(Text(title))
}
enum LocalHelp: String, Identifiable {
    case privacy = "Privacy", support = "Support"
    var id: String { rawValue }
    var title: String { self == .privacy ? L("Privacy Policy","Política de privacidad") : L("Support","Soporte") }
    var text: String {
        let installed=Bundle.main.resourceURL.flatMap { Bundle(url:$0.appendingPathComponent("CheckHarbor_CheckHarbor.bundle")) }
        let resources=installed ?? Bundle.module
        guard let url=resources.url(forResource:rawValue,withExtension:"txt"),
              let text=try? String(contentsOf:url,encoding:.utf8) else { return "Michael Lip" }
        return text
    }
    var webURL: URL? {
        HelpDestination.url(Bundle.main.object(forInfoDictionaryKey:self == .privacy ? "MASPrivacyPolicyURL" : "MASSupportURL") as? String, path:self == .privacy ? "/apps/checkharbor/privacy/" : "/apps/checkharbor/support/")
    }
}
enum HelpDestination {
    static func url(_ raw: String?, path: String? = nil) -> URL? {
        guard let raw, !raw.contains("{"), !raw.contains("}"),
              let url=URL(string:raw), url.scheme == "https", url.host != nil,
              path.map({ URLComponents(url:url,resolvingAgainstBaseURL:false)?.path == $0 }) ?? true else { return nil }
        return url
    }
}
struct PolicyLinks: View {
    @State private var selected: LocalHelp?
    var body: some View { HStack {
        AccessibleButton(L("Privacy Policy","Política de privacidad")) { selected = .privacy }
        AccessibleButton(L("Support","Soporte")) { selected = .support }
    }.font(.caption).sheet(item:$selected) { help in
        VStack(alignment:.leading,spacing:16) {
            Text(help.title).font(.title2.bold())
            ScrollView { Text(help.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            HStack {
                if let url=help.webURL { Link(L("Open website","Abrir sitio web"),destination:url) }
                Spacer()
                AccessibleButton(L("Done","Cerrar")) { selected=nil }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width:560,height:560)
    } }
}
struct ContentView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:12) {
                Image(systemName:model.symbol).font(.system(size:30)).foregroundStyle(model.stale ? .orange : .teal).accessibilityLabel(model.status)
                VStack(alignment:.leading) { Text("CheckHarbor").font(.title.bold()); Text(L("Track builds until they recover","Sigue las compilaciones hasta su recuperación")).foregroundStyle(.secondary) }
                Spacer()
                if model.sample { Text("Sample").font(.caption.bold()).padding(8).background(.teal.opacity(0.15),in:Capsule()) }
            }
            HStack(spacing:12) {
                metric("\(model.state.inbox.active.count)",L("Unresolved","Pendientes"),.orange)
                metric("\(model.state.inbox.active.filter(\.acknowledged).count)",L("Acknowledged","Reconocidos"),.blue)
                metric("\(model.state.inbox.recovered.count)",L("Recovered","Recuperados"),.teal)
            }
            HStack {
                Picker(L("Recovery inbox","Bandeja de recuperación"),selection:$model.recovered) {
                    Text(L("Unresolved","Pendientes")).tag(false); Text(L("Recovered","Recuperados")).tag(true)
                }.pickerStyle(.segmented)
                Button { Task { await model.refresh() } } label: { Label(L("Refresh","Actualizar"),systemImage:"arrow.clockwise") }.accessibilityLabel(L("Refresh","Actualizar")).disabled(model.busy)
                SettingsLink { Image(systemName:"gearshape") }.accessibilityLabel(L("Settings","Ajustes")).keyboardShortcut(",",modifiers:.command)
            }
            if model.sample {
                HStack {
                    AccessibleButton(L("Simulate recovery","Simular recuperación")) { model.sampleRecovery() }
                    AccessibleButton(L("Simulate stale","Simular datos antiguos")) { model.staleSample.toggle() }
                    AccessibleButton(L("Reset Sample","Reiniciar Sample")) { model.resetSample() }
                    AccessibleButton(L("Use live data","Usar datos reales")) { model.toggleSample(false) }
                }.controlSize(.small)
            }
            HStack { Circle().fill(model.stale ? .orange : .teal).frame(width:7,height:7); Text(model.status).font(.caption); Spacer(); if model.busy { ProgressView().controlSize(.small) } }
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            if let until=model.state.backoff,until > Date() { Text(L("Next API request after ","Próxima consulta después de ")+until.formatted()).font(.caption).foregroundStyle(.orange) }
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    if model.shown.isEmpty {
                        VStack(alignment:.leading,spacing:12) {
                            Text(model.recovered ? L("No recoveries recorded yet","Aún no hay recuperaciones") : model.repositories.isEmpty && !model.sample ? L("Give failed builds a safe harbor","Un puerto seguro para las compilaciones fallidas") : L("Your recovery inbox is clear","Tu bandeja de recuperación está vacía")).font(.title3.bold())
                            Text(L("Add an owner and repository in Settings, then refresh. Only a newer success on the same branch and workflow closes a failure.","Añade propietario y repositorio en Ajustes y actualiza. Solo un éxito posterior en la misma rama y flujo cierra un fallo.")).foregroundStyle(.secondary)
                            if !model.sample { AccessibleButton(L("Try Sample","Probar Sample")) { model.toggleSample(true) }.buttonStyle(.borderedProminent) }
                        }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:14))
                    }
                    ForEach(model.shown) { e in EpisodeCard(model:model,episode:e) }
                    ForEach(model.errors.keys.sorted(),id:\.self) { repo in Text(repo+"\n"+(model.errors[repo] ?? "")).font(.caption).foregroundStyle(.orange).padding(10) }
                    DisclosureGroup(L("Recent workflow runs","Ejecuciones recientes")) {
                        ForEach(model.state.runs.keys.sorted(),id:\.self) { repo in
                            VStack(alignment:.leading,spacing:8) {
                                Text(repo).font(.headline)
                                if let date=model.state.fetched[repo] { Text(L("Last successful fetch ","Última consulta correcta ")+date.formatted()).font(.caption).foregroundStyle(.secondary) }
                                ForEach(Array((model.state.runs[repo] ?? []).sorted{$0.updated_at > $1.updated_at}.prefix(12))) { run in
                                    HStack { VStack(alignment:.leading) { Text((run.name ?? "Workflow")+" · "+(run.head_branch ?? L("Unknown branch","Rama desconocida"))); Text(run.status+" · "+(run.conclusion ?? L("Pending","Pendiente"))+" · "+run.updated_at.formatted()).font(.caption).foregroundStyle(.secondary) }; Spacer(); RunLink(run:run,repository:repo,sample:model.sample,label:L("View","Ver")) }
                                }
                            }.padding(.vertical,6)
                        }
                    }.padding(12)
                }
            }.frame(height:330)
            Text(L("Limited API history and polling gaps can miss runs. Acknowledged and snoozed failures remain unresolved.","El historial limitado y los intervalos de consulta pueden omitir ejecuciones. Los fallos reconocidos y pospuestos siguen pendientes.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack { PolicyLinks(); Spacer(); Text(L("Local recovery digest","Resumen local de recuperación")).font(.caption).foregroundStyle(.secondary); AccessibleButton(L("Quit","Salir")) { NSApp.terminate(nil) }.controlSize(.small) }
        }.padding(24).frame(width:720).background(Color(nsColor:.windowBackgroundColor))
    }
    func metric(_ count: String,_ label: String,_ color: Color) -> some View {
        VStack(alignment:.leading,spacing:5) { Text(count).font(.system(size:28,weight:.semibold,design:.rounded)).foregroundStyle(color); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(color.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
    }
}
struct RunLink: View {
    let run: Run
    let repository: String
    let sample: Bool
    let label: String
    @State var preview=false
    var body: some View {
        if sample { AccessibleButton(label) { preview=true }.alert(L("Sample run preview","Vista previa de Sample"),isPresented:$preview) { AccessibleButton("OK",role:.cancel) {} } message: { Text(L("Fictional run in harbor/demo. Live runs open their validated GitHub page.","Ejecución ficticia en harbor/demo. Las ejecuciones reales abren su página validada de GitHub.")) } }
        else if let url=Validation.runURL(run.html_url,repository:repository) { Link(label,destination:url) }
        else { Text(L("Invalid run link","Enlace de ejecución inválido")).font(.caption).foregroundStyle(.secondary) }
    }
}
struct EpisodeCard: View {
    @ObservedObject var model: Model
    let episode: Episode
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(episode.first.name ?? "Workflow").font(.headline); Spacer(); Text(episode.unresolved ? L("Needs recovery","Necesita recuperación") : L("Recovered","Recuperado")).font(.caption.bold()).foregroundStyle(episode.unresolved ? .orange : .teal) }
            Text(episode.repository+"  /  "+(episode.first.head_branch ?? "")).font(.system(.subheadline,design:.monospaced)).foregroundStyle(.secondary)
            Text("\(episode.failures) "+L("failed runs in this episode","ejecuciones fallidas en este episodio")+" · "+episode.latest.updated_at.formatted(date:.abbreviated,time:.shortened)).font(.caption)
            if episode.acknowledged { Label(episode.unresolved ? L("Acknowledged and still unresolved","Reconocido y aún pendiente") : L("Acknowledged before recovery","Reconocido antes de la recuperación"),systemImage:"checkmark.seal").font(.caption) }
            if let until=episode.snoozedUntil,until > Date() { Text(L("Snoozed until ","Pospuesto hasta ")+until.formatted()).font(.caption).foregroundStyle(.secondary) }
            HStack {
                RunLink(run:episode.first,repository:episode.repository,sample:model.sample,label:L("First failure","Primer fallo"))
                RunLink(run:episode.latest,repository:episode.repository,sample:model.sample,label:L("Latest failure","Último fallo"))
                if let recovery=episode.recovery { RunLink(run:recovery,repository:episode.repository,sample:model.sample,label:L("Recovery run","Recuperación")) }
                Spacer()
                if episode.unresolved {
                    AccessibleButton(episode.acknowledged ? L("Unacknowledge","Quitar reconocimiento") : L("Acknowledge","Reconocer")) { model.acknowledge(episode) }
                    AccessibleButton(episode.snoozed(at:Date()) ? L("Unsnooze","Reactivar") : L("Snooze","Posponer")) { model.snooze(episode) }
                }
            }.controlSize(.small)
        }.padding(16).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:12))
    }
}
struct SettingsView: View {
    @ObservedObject var model: Model
    @State private var repo=""
    @State private var token=""
    @State private var login=SMAppService.mainApp.status == .enabled
    @State private var error=""
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                Text(L("CheckHarbor settings","Ajustes de CheckHarbor")).font(.title2.bold())
                AccessibleToggle(L("Sample mode","Modo Sample"),isOn:Binding(get:{model.sample},set:{model.toggleSample($0)}))
                Text(L("Sample uses fictional local data and never contacts GitHub.","Sample usa datos locales ficticios y nunca contacta con GitHub.")).font(.caption).foregroundStyle(.secondary)
                GroupBox(L("Repositories on GitHub.com","Repositorios en GitHub.com")) {
                    VStack(alignment:.leading,spacing:10) {
                        HStack { TextField(L("owner/repository","propietario/repositorio"),text:$repo).accessibilityLabel(L("Owner and repository","Propietario y repositorio")); AccessibleButton(L("Add","Añadir")) { model.add(repo); repo="" } }
                        ForEach(model.repositories,id:\.self) { name in HStack { Text(name); Spacer(); AccessibleButton(L("Remove","Eliminar")) { model.remove(name) } } }
                        Text(L("Public repositories need no token where API limits permit. Private repositories need a fine grained token with Actions read access.","Los repositorios públicos no necesitan token si los límites lo permiten. Los privados necesitan un token con permiso de lectura de Actions.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }.disabled(model.sample)
                SecureField(L("Optional token stored in Keychain","Token opcional guardado en el llavero"),text:$token).accessibilityLabel(L("Optional token","Token opcional")).disabled(model.sample)
                HStack { AccessibleButton(L("Save token","Guardar token")) { model.token(token); token="" }.disabled(token.isEmpty || model.sample); AccessibleButton(L("Remove credentials","Eliminar credenciales")) { model.token(""); token="" }.disabled(model.sample) }
                Text(L("The token is sent only to api.github.com. Source code and logs are never fetched.","El token solo se envía a api.github.com. Nunca se consultan código fuente ni registros.")).font(.caption).foregroundStyle(.secondary)
                Picker(L("Poll interval","Intervalo de consulta"),selection:$model.interval) { Text(L("Every minute","Cada minuto")).tag(60); Text(L("Every five minutes","Cada cinco minutos")).tag(300); Text(L("Every fifteen minutes","Cada quince minutos")).tag(900) }
                Picker(L("Recovered digest retention","Conservar recuperaciones"),selection:$model.retention) { Text(L("7 days","7 días")).tag(7); Text(L("30 days","30 días")).tag(30); Text(L("90 days","90 días")).tag(90) }
                Picker(L("Snooze duration","Duración de pausa"),selection:$model.snoozeMinutes) { Text(L("15 minutes","15 minutos")).tag(15); Text(L("1 hour","1 hora")).tag(60); Text(L("4 hours","4 horas")).tag(240) }
                Picker(L("Open unresolved shortcut","Atajo para abrir pendientes"),selection:$model.shortcut) { Text("⌘⇧H").tag(0); Text("⌘⇧J").tag(1); Text(L("Disabled","Desactivado")).tag(2) }
                if !model.shortcutError.isEmpty { Text(model.shortcutError).font(.caption).foregroundStyle(.orange) }
                AccessibleToggle(L("Launch at login","Abrir al iniciar sesión"),isOn:Binding(get:{login},set:{ value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; error=SMAppService.mainApp.status == .requiresApproval ? L("Approve in System Settings Login Items","Autoriza en los ítems de inicio de Ajustes del Sistema") : "" } catch { self.error=error.localizedDescription }
                    login=SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
                }))
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
                if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange) }
                HStack { AccessibleButton(L("Refresh now","Actualizar ahora")) { Task { await model.refresh() } }.disabled(model.busy); AccessibleButton(L("Delete local history and repositories","Borrar historial y repositorios locales"),role:.destructive) { model.deleteData() } }
                Text(L("Deletion keeps your optional Keychain token. Remove credentials separately. Polling runs only while CheckHarbor is open.","El borrado conserva el token opcional. Elimina las credenciales por separado. Las consultas solo se realizan con CheckHarbor abierto.")).font(.caption).foregroundStyle(.secondary)
                Divider(); PolicyLinks()
            }.padding(24)
        }.frame(width:620,height:750)
    }
}
