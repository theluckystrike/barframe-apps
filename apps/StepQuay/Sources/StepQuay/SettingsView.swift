import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    @State private var loginError = ""
    @State private var clearing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text(model.l("StepQuay settings")).font(.title2.bold()); Spacer(); if model.sampleMode { Text("Sample").foregroundStyle(.teal).font(.caption.bold()) } }
            Toggle(model.l("Launch at login"), isOn: Binding(get: { login }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = SMAppService.mainApp.status == .requiresApproval ? model.l("Approve StepQuay in System Settings then Login Items.") : ""
                } catch { loginError = error.localizedDescription }
                login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            }))
            if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack { Text(model.l("Default action minutes")); Spacer(); TextField(model.l("Minutes"), value: Binding(get: { model.defaultMinutes }, set: { value in
                if value.isFinite && value > 0 && value <= 1440 { model.defaultMinutes = value; model.message = "" }
                else { model.message = model.l("Enter minutes greater than zero and no more than 1440.") }
            }), format: .number).textFieldStyle(.roundedBorder).frame(width: 70) }
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Toggle(model.l("Show remaining time in menu bar"), isOn: $model.showTime)
            Divider()
            Text(model.l("Panel shortcut")).font(.headline)
            HStack {
                Picker(model.l("Modifiers"), selection: $model.shortcutModifiers) {
                    Text("⌘ ⌥").tag("commandOption")
                    Text("⌃ ⌥").tag("controlOption")
                    Text("⌘ ⇧").tag("commandShift")
                }
                Picker(model.l("Key"), selection: $model.shortcutKey) {
                    ForEach(["K", "J", "U", "P", "L", "Space"], id: \.self) { Text(model.l($0)).tag($0) }
                }.frame(width: 155)
            }
            Text(model.shortcutError.isEmpty ? model.l("Shortcut registered") : model.shortcutError).font(.caption).foregroundStyle(model.shortcutError.isEmpty ? Color.secondary : Color.orange).fixedSize(horizontal: false, vertical: true)
            Text(model.l("The menu bar button always opens your panel.")).font(.caption).foregroundStyle(.secondary)
            Divider()
            Picker(model.l("Keep session history"), selection: $model.retention) {
                Text(model.l("7 days")).tag(7); Text(model.l("30 days")).tag(30); Text(model.l("90 days")).tag(90); Text(model.l("Forever")).tag(0)
            }
            Text(model.l("Live history expires on launch, when retention changes, and every minute while the app is open, including Sample mode.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(model.l("Clear history")) { clearing = true }
                .confirmationDialog(model.l("Clear completed records and notes? Your queue stays intact."), isPresented: $clearing) {
                    Button(model.l("Clear"), role: .destructive) { model.change { $0.history = [] } }
                    Button(model.l("Cancel"), role: .cancel) {}
                }
            Toggle(model.l("Sample mode"), isOn: Binding(get: { model.sampleMode }, set: { model.toggleSample($0) }))
            HStack {
                Text(model.l("Sample changes never affect your live queue.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if model.sampleMode { Button(model.l("Reset Sample")) { model.resetSample() } }
            }
            Picker(model.l("Language"), selection: $model.language) {
                Text(model.l("System language")).tag("auto"); Text("English").tag("en"); Text("Español").tag("es")
            }
            if model.storageFailed {
                Text(model.message).font(.caption).foregroundStyle(.orange)
                HStack {
                    Button(model.l("Restore saved data")) { model.restoreSavedData() }
                    Button(model.l("Reset saved queue")) { model.resetStoredQueue() }
                }
            }
            Divider()
            Text(model.l("All task data stays here. No accounts, analytics, or network access.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(model.l("No special permissions are required.")).font(.caption).foregroundStyle(.secondary)
            HStack { PolicySupportLinks(model: model); Spacer(); Text(model.l("Version 1.0.0")).font(.caption).foregroundStyle(.secondary); Button(model.l("Quit")) { NSApp.terminate(nil) } }
        }.padding(24).frame(width: 580)
    }
}
