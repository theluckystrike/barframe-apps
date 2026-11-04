import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var loginError: String?
    @State private var refreshLogin = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.l("KeyOverlap settings", "Ajustes de KeyOverlap")).font(.title2.bold())
            Picker(model.l("Language", "Idioma"), selection: $model.language) { Text("English").tag("en"); Text("Español").tag("es") }
            LabeledToggle(model.l("Launch at login", "Abrir al iniciar sesión"), isOn: Binding(get: {
                _ = refreshLogin
                return SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = SMAppService.mainApp.status == .requiresApproval ? model.l("Approve KeyOverlap in System Settings under General and Login Items.", "Autoriza KeyOverlap en Ajustes del Sistema en General e Ítems de inicio.") : nil
                } catch { loginError = model.errorText(error) }
                refreshLogin.toggle()
            }))
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            VStack(alignment: .leading, spacing: 7) {
                Text(model.l("Open planner shortcut", "Atajo para abrir el plan")).font(.headline)
                HStack {
                    TextField("command+option+k", text: $model.opener).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("Open planner shortcut", "Atajo para abrir el plan"))
                    LabeledButton(model.l("Register", "Registrar")) { model.registerShortcut() }
                }
                Text(model.l("Default Command Option K. Register changes to activate them. Uses physical key positions on a US keyboard. Use the menu bar button if registration fails.", "Predeterminado Comando Opción K. Registra los cambios para activarlos. Usa posiciones físicas de un teclado estadounidense. Usa la barra de menús si falla el registro.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }
            TextField(model.l("Default app scope for new records", "Ámbito predeterminado para nuevos registros"), text: $model.defaultScope).textFieldStyle(.roundedBorder).accessibilityLabel(model.l("Default app scope", "Ámbito predeterminado"))
            Text(model.l("Leave blank for unknown scope or use * for global", "Deja vacío para ámbito desconocido o usa * para global")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LabeledToggle(model.l("Show possible overlaps in Plan", "Mostrar cruces posibles en Plan"), isOn: $model.showPossible)
            LabeledToggle(model.l("Sample mode", "Modo de ejemplo"), isOn: Binding(get: { model.sampleMode }, set: { model.toggleSample($0) }))
            if model.sampleMode { LabeledButton(model.l("Restore Sample fixtures", "Restaurar ejemplos")) { model.resetSample() } }
            LabeledButton(model.sampleMode ? model.l("Clear Sample plan", "Borrar plan de ejemplo") : model.l("Clear local plans", "Borrar planes locales"), role: .destructive) { model.clear() }
            Text(model.l("No automatic scans or imports. Plans stay on your Mac. Import reads a file only when you choose it.", "Sin análisis ni importaciones automáticas. Los planes quedan en tu Mac. La importación lee un archivo solo cuando lo eliges.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack { PolicyLinks(model: model); Spacer(); Text("1.0.0").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); LabeledButton(model.l("Quit", "Salir")) { NSApp.terminate(nil) } }
        }.padding(24).frame(width: 620)
    }
}
