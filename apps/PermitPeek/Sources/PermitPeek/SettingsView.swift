import SwiftUI
import ServiceManagement
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var error=""
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L("PermitPeek settings","Ajustes de PermitPeek")).font(.title2.bold())
            Toggle(L("Launch at login","Abrir al iniciar sesión"),isOn:Binding(get:{login},set:{ enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; error=SMAppService.mainApp.status == .requiresApproval ? L("Approve in System Settings Login Items","Aprueba en Ajustes del Sistema") : "" } catch { self.error=error.localizedDescription }
                login=SMAppService.mainApp.status == .enabled
            }))
            if !error.isEmpty { Text(error).foregroundStyle(.orange) }
            Picker(L("Open review inbox","Abrir bandeja de revisión"),selection:$model.shortcutChoice) { Text("⇧⌘P").tag(0); Text("⇧⌘I").tag(1); Text(L("Off","Desactivado")).tag(2) }.onChange(of:model.shortcutChoice) { _ in model.registerShortcut() }
            if !model.shortcutError.isEmpty { Text(model.shortcutError).foregroundStyle(.orange) }
            Toggle(L("Sample mode","Modo Sample"),isOn:Binding(get:{model.sampleMode},set:{model.toggleSample($0)}))
            Button(L("Reset Sample fixtures","Restablecer ejemplos Sample")) { model.toggleSample(true) }
            Text(L("Sample has separate temporary data. Live baselines remain on this Mac. No automatic scan runs on launch.","Sample usa datos temporales separados. Las referencias reales permanecen en este Mac. No hay inspección automática al abrir.")).font(.callout).foregroundStyle(.secondary)
            HStack { Button(L("Choose app","Elegir aplicación")){model.choose()}.disabled(model.savedDataUnreadable); Button(L("Rescan","Volver a inspeccionar")){model.rescan()}.disabled(!model.sampleMode && model.savedDataUnreadable) }
            Text(L("Remove an individual app from the inbox or erase all local watches below. App bundles are never modified.","Elimina una aplicación desde la bandeja o borra todas las referencias. Las aplicaciones nunca se modifican.")).font(.caption)
            if model.sampleMode {
                Button(L("Delete Sample watches only","Borrar solo ejemplos Sample"),role:.destructive){model.clearSampleData()}
            }
            if model.savedDataUnreadable {
                Text(L("Saved data is unreadable. Writes are paused until recovery or explicit deletion.","Los datos guardados son ilegibles. Se pausó el guardado hasta recuperarlos o borrarlos.")).font(.callout).foregroundStyle(.orange)
                Button(L("Retry saved data","Reintentar datos guardados")){model.retrySavedData()}
            }
            Button(L("Delete all live watches and history","Borrar referencias reales e historial"),role:.destructive){model.deleteAllLiveData()}
            Text(L("This deletes saved live data even while Sample is enabled.","Esto borra los datos reales guardados incluso en modo Sample.")).font(.caption)
            if !model.notice.isEmpty { Text(model.notice).font(.caption).foregroundStyle(.orange) }
            Divider(); PolicySupportLinks()
            HStack { Text("PermitPeek 1.0.0").font(.caption); Spacer(); Button(L("Quit","Salir")){NSApp.terminate(nil)} }
        }.padding(24).frame(width:540)
    }
}
