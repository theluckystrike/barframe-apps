import SwiftUI
import ServiceManagement
import CronSpindleCore

struct Links: View {
    var body: some View {
        HStack { Link("Privacy Policy",destination:URL(string:"https://barframe.com/apps/cronspindle/privacy/")!); Link("Support",destination:URL(string:"https://barframe.com/apps/cronspindle/support/")!) }.font(.caption)
    }
}
struct ContentView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            header
            toolbar
            HStack(alignment:.top,spacing:18) {
                jobList
                Divider()
                editor
            }
            Divider()
            results
            Text(model.t("UTC minute preview · Repeated wall times are separate instants · Actual schedulers may use different DST rules", "Vista por minuto UTC · Las horas repetidas son instantes distintos · Las reglas de horario de verano pueden variar")).font(.caption).foregroundStyle(.secondary)
            HStack {Links(); Spacer(); Text(model.t("Local planning only", "Planificación local")).font(.caption).foregroundStyle(.secondary); Button("Quit"){NSApp.terminate(nil)}}
        }.padding(22).frame(minWidth:870,idealWidth:870,maxWidth:.infinity,minHeight:700).onChange(of:model.expression){model.draftChanged()}.onChange(of:model.duration){model.draftChanged()}.onChange(of:model.name){model.draftChanged()}.onChange(of:model.zone){model.draftChanged()}.onChange(of:model.resource){model.draftChanged()}
    }
    var header: some View {
            HStack {
                Image(systemName:"calendar.badge.clock").font(.largeTitle).foregroundStyle(.teal)
                VStack(alignment:.leading) {Text("CronSpindle").font(.title.bold()); Text(model.t("Find schedule collisions", "Detecta conflictos de horarios")).foregroundStyle(.secondary)}
                Spacer()
                Text(model.sample ? "Sample" : "Live").font(.headline).padding(8).background(.teal.opacity(0.15),in:Capsule())
                SettingsLink { Image(systemName:"gearshape") }.accessibilityLabel("Settings")
            }
    }
    var toolbar: some View {
            HStack {
                Button(model.sample ? model.t("Use Live", "Usar real") : model.t("See Sample", "Ver ejemplo")) {model.toggleSample(!model.sample)}
                Text(model.t("1 See Sample   2 Enter jobs   3 Review result", "1 Ver ejemplo   2 Añadir tareas   3 Revisar resultado")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.busy {ProgressView().controlSize(.small); Button(model.t("Cancel", "Cancelar")){model.cancel()}}
            }
    }
    var jobList: some View {
                VStack(alignment:.leading,spacing:10) {
                    HStack { Text(model.t("Saved jobs", "Tareas guardadas")).font(.headline); Spacer(); Button {model.newJob()} label:{Image(systemName:"plus")}.accessibilityLabel("New job") }
                    if model.jobs.isEmpty {Text(model.t("No jobs yet. Enter a name, schedule and duration to create your first plan.","Sin tareas. Introduce nombre, horario y duración para crear tu plan.")).foregroundStyle(.secondary).padding(.vertical)}
                    ScrollView {
                        VStack(spacing:8) { ForEach(model.jobs) { job in
                            Button {model.select(job)} label: {
                                VStack(alignment:.leading,spacing:5) {Text(job.name).font(.headline); Text(job.expression).font(.system(.body,design:.monospaced)); Text("\(job.minutes.formatted()) min · \(job.resource.isEmpty ? "No shared resource" : job.resource)").font(.caption); Text(job.zone).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(model.selected==job.id ? Color.teal.opacity(0.18) : Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                            }.buttonStyle(.plain)
                        }}
                    }.frame(height:215)
                    Button(model.t("Check saved plan", "Analizar plan")){model.analyze()}.disabled(model.jobs.isEmpty || model.busy)
                    if let last=model.lastCheck {Text("Last check \(last.formatted(date:.omitted,time:.shortened))").font(.caption).foregroundStyle(.secondary)}
                }.frame(width:245)
    }
    var editor: some View {
                VStack(alignment:.leading,spacing:9) {
                    Text(model.selected == nil ? model.t("Create a job", "Crear tarea") : model.t("Propose a change", "Proponer cambio")).font(.headline)
                    HStack {TextField(model.t("Name", "Nombre"),text:$model.name); TextField(model.t("Resource label", "Recurso compartido"),text:$model.resource)}
                    TextField(model.t("Numeric cron expression", "Expresión cron numérica"),text:$model.expression).font(.system(.body,design:.monospaced)).accessibilityLabel("Cron expression")
                    Text(model.t("Minute  Hour  Day  Month  Weekday", "Minuto  Hora  Día  Mes  Día semanal")).font(.caption).foregroundStyle(.secondary)
                    HStack {TextField(model.t("IANA time zone", "Zona horaria IANA"),text:$model.zone); TextField(model.t("Duration in minutes", "Duración en minutos"),text:$model.duration).frame(width:150)}
                    Text(model.t("Duration in minutes is required. Blank resources are not compared.","La duración en minutos es obligatoria. Los recursos vacíos no se comparan.")).font(.caption).foregroundStyle(.secondary)
                    HStack {Button(model.t("Preview change", "Ver cambio")){model.analyze(compare:true)}.disabled(model.selected==nil || model.busy); Button(model.t("Save job", "Guardar tarea")){model.save()}.buttonStyle(.borderedProminent).tint(.teal); Button(model.t("Remove", "Eliminar")){model.deleteJob()}.disabled(model.selected==nil)}
                    if let error=model.error {Text(model.spanish ? "Entrada no válida o acceso local denegado. " + error : error).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
                    Divider()
                    HStack {
                        Image(systemName:model.stale ? "questionmark.circle" : model.result?.state=="Clear" ? "checkmark.circle" : "exclamationmark.triangle").foregroundStyle(model.stale ? Color.secondary : Color.orange)
                        Text(model.spanish ? translatedState : model.state).font(.title3.bold())
                        Spacer()
                        Button(model.t("Copy explanation", "Copiar informe")){model.copyReport()}.disabled(model.result==nil)
                    }
                    if let original=model.result {
                        Text("\(original.collisions.count) contention windows · \(original.occurrences.count) occupied intervals").font(.callout)
                        if let proposal=model.proposed {
                            Text("Proposal \(proposal.state) · \(model.added.count) added · \(model.removed.count) removed").font(.headline).foregroundStyle(.teal)
                            Text(model.t("Original stays saved until Save job", "El original se conserva hasta Guardar tarea")).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(Planner.label(original.start,zone:model.displayZone))\nthrough \(Planner.label(original.end,zone:model.displayZone))").font(.caption).foregroundStyle(.secondary)
                    } else {Text(model.t("No result yet. Check a saved plan or explore Sample.","Sin resultado. Analiza un plan o explora el ejemplo.")).foregroundStyle(.secondary)}
                }.frame(maxWidth:.infinity,alignment:.leading).textFieldStyle(.roundedBorder)
    }
    var translatedState: String { ["Clear":"Sin conflictos","Conflict":"Conflicto","Incomplete":"Incompleto","Working":"Analizando","Stale":"Desactualizado","No inputs":"Sin datos","Cancelled":"Cancelado","Not checked":"Sin analizar"][model.state] ?? model.state }
    @ViewBuilder var results: some View {
        let shown=model.proposed ?? model.result
        VStack(alignment:.leading,spacing:6) {
            Text(model.t("Occupied windows", "Intervalos ocupados")).font(.headline)
            if let shown {
                if shown.incomplete {Text(model.t("Incomplete coverage. Narrow the horizon. Absence of collisions is not established.","Cobertura incompleta. Reduce el horizonte. No se confirma la ausencia de conflictos.")).foregroundStyle(.orange)}
                ScrollView {
                    VStack(alignment:.leading,spacing:8) {
                        if model.proposed != nil {
                            ForEach(Array(model.removed.prefix(60))) { window in
                                Text("\(model.t("Removed", "Eliminado")) · \(window.names) · \(Planner.label(window.start,zone:model.displayZone)) → \(Planner.label(window.end,zone:model.displayZone))").font(.caption).foregroundStyle(.teal)
                            }
                            ForEach(Array(model.added.prefix(60))) { window in
                                Text("\(model.t("Added", "Añadido")) · \(window.names) · \(Planner.label(window.start,zone:model.displayZone)) → \(Planner.label(window.end,zone:model.displayZone))").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        ForEach(Array(shown.collisions.prefix(60))) { c in
                            HStack {Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange); VStack(alignment:.leading) {Text("\(c.names) · \(c.resource)").bold(); Text("\(Planner.label(c.start,zone:model.displayZone)) → \(Planner.label(c.end,zone:model.displayZone))").font(.system(.caption,design:.monospaced))}}
                        }
                        if shown.collisions.isEmpty && !shown.incomplete {Text(model.t("No shared resource collisions in this coverage", "Sin conflictos de recursos en esta cobertura")).foregroundStyle(.teal)}
                        ForEach(Array(shown.occurrences.prefix(60))) {o in
                            HStack {Text(o.job.name).frame(width:140,alignment:.leading); Text(o.wallLabel).font(.system(.caption,design:.monospaced)); Spacer(); Text("\(o.job.minutes.formatted()) min").foregroundStyle(.secondary)}
                        }
                        if shown.occurrences.count>60 || shown.collisions.count>60 {Text("Showing first 60 of each kind. Copy explanation for every collision.").font(.caption)}
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.frame(height:150)
            } else {Text(model.t("Your analysis will appear here", "El análisis aparecerá aquí")).foregroundStyle(.secondary).frame(height:150)}
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: Model
    @State var login=SMAppService.mainApp.status == .enabled
    @State var loginError: String?
    @State var advanced=false
    @State var shortcut=UserDefaults.standard.string(forKey:"shortcut") ?? "K"
    var body: some View {
        Form {
            Text(model.t("CronSpindle settings", "Ajustes de CronSpindle")).font(.title2.bold())
            Toggle(model.t("Sample mode", "Modo de ejemplo"),isOn:Binding(get:{model.sample},set:{model.toggleSample($0)}))
            HStack {Button(model.t("Reset Sample", "Restablecer ejemplo")){model.resetSample()}; Button(model.t("Sample repeated hour", "Ejemplo de hora repetida")){model.dstSample()}}
            Toggle(model.t("Pin current plan in menu bar", "Fijar plan en la barra de menús"),isOn:$model.pinned)
            DatePicker(model.t("Preview start", "Inicio de la vista previa"),selection:Binding(get:{model.start},set:{model.start=$0;model.invalidate();model.savePreviewSettings()}))
            TextField(model.t("Display time zone", "Zona horaria de visualización"),text:$model.displayZone)
            if TimeZone(identifier:model.displayZone)==nil {Text(model.t("Invalid display zone. Enter UTC or an IANA identifier.", "Zona no válida. Introduce UTC o un identificador IANA.")).foregroundStyle(.red)}
            Toggle("Interfaz en español",isOn:$model.spanish)
            Picker(model.t("Appearance", "Apariencia"),selection:$model.appearance) {Text(model.t("System", "Sistema")).tag("System"); Text(model.t("Light", "Claro")).tag("Light"); Text(model.t("Dark", "Oscuro")).tag("Dark")}.onChange(of:model.appearance){NSApp.appearance=model.appearance=="System" ? nil : NSAppearance(named:model.appearance=="Dark" ? .darkAqua : .aqua)}
            Toggle(model.t("Launch at login", "Abrir al iniciar sesión"),isOn:Binding(get:{login},set:{value in
                do {if value {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}; loginError=SMAppService.mainApp.status == .requiresApproval ? "Approve in System Settings Login Items" : nil} catch {loginError=error.localizedDescription}
                login=SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            }))
            if let loginError {Text(loginError).foregroundStyle(.red)}
            DisclosureGroup(model.t("Advanced", "Avanzado"),isExpanded:$advanced) {
                Stepper("Horizon \(model.days) days",value:Binding(get:{model.days},set:{model.days=$0;model.invalidate();model.savePreviewSettings()}),in:1...31)
                Text(model.t("Resource labels match without case. Blank labels opt out. Only one local plan is stored.", "Los recursos coinciden sin distinguir mayúsculas. Los vacíos no se comparan. Se guarda un solo plan local.")).font(.caption)
                Picker(model.t("Open panel with Control Option", "Abrir panel con Control Option"),selection:$shortcut){Text("K").tag("K"); Text("J").tag("J"); Text("L").tag("L")}.onChange(of:shortcut){HotKey.shared.register(shortcut)}
                Text(HotKey.shared.error ?? "Shortcut uses the public hotkey API").font(.caption)
                Button(model.t("Delete local plan", "Eliminar plan local")){model.clear()}
            }
            Text(model.t("Numeric five field cron only. When day and weekday are restricted they use OR semantics. Expansion stops at 5000 intervals or collision windows and reports Incomplete.", "Solo cron numérico de cinco campos. Día del mes y día semanal usan O cuando ambos se restringen. El análisis se detiene a los 5000 intervalos o conflictos e indica Incompleto.")).font(.caption).foregroundStyle(.secondary)
            Links()
        }.padding(24).frame(width:540)
    }
}
