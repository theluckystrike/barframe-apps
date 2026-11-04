import SwiftUI
import ServiceManagement
import MASKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MeetNext settings").font(.title2.bold())
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = SMAppService.mainApp.status == .requiresApproval ? "Approve MeetNext in System Settings → General → Login Items." : nil
                } catch { loginError = error.localizedDescription }
                let status = SMAppService.mainApp.status
                launchAtLogin = status == .enabled || status == .requiresApproval
            }))
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }

            Picker("Remind me before a meeting", selection: $model.reminderMinutes) {
                Text("Never").tag(0)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("15 minutes").tag(15)
            }
            .onChange(of: model.reminderMinutes) { _ in model.requestNotifications() }
            .accessibilityIdentifier("reminderPicker")

            Toggle("Sample mode", isOn: Binding(get: { model.sampleMode }, set: { model.toggleSample($0) }))
            Text("Calendars").font(.headline)
            ForEach(model.calendarChoices) { calendar in
                Toggle(calendar.title, isOn: Binding(get: { model.isCalendarSelected(calendar.id) }, set: { model.selectCalendar(calendar.id, enabled: $0) }))
            }
            Button("Clear reminder history") { model.clearReminderHistory() }
            Divider()
            if model.accessDenied {
                Text("Calendar access: denied. Open System Settings → Privacy & Security → Calendars to allow MeetNext.")
                    .font(.caption).foregroundStyle(.orange)
            } else if model.authorized {
                Text("Calendar access: granted. MeetNext reads event titles, times, locations and notes from the next two days.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Allow calendar access") { model.requestAccess() }
            }
            Divider()
            PolicySupportLinks()
            HStack {
                Text("Version \(ProductInfo.version) (\(ProductInfo.build))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(24).frame(width: 520)
    }
}
