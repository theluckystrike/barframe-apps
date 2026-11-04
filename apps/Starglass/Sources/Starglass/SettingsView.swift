import SwiftUI
import ServiceManagement
import StarglassCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?
    @State private var query = ""
    @AppStorage("showScore") private var showScore = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Starglass settings").font(.title2.bold())

            Text("Location").font(.headline)
            if let location = model.location, !location.isEmpty {
                Text(location.name).font(.callout)
            } else {
                Text("No location chosen. Search for a city below.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                TextField("City search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.search(query) } }
                Button("Search") { Task { await model.search(query) } }.disabled(query.count < 2)
            }
            if model.searching { ProgressView().controlSize(.small) }
            ForEach(model.searchResults) { place in
                Button {
                    model.choose(place)
                } label: {
                    Text(place.summary)
                }.buttonStyle(.plain)
            }
            Text("City search uses the free Open-Meteo geocoding service. No location permission is requested; your search text is sent to Open-Meteo.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = SMAppService.mainApp.status == .requiresApproval ? "Approve Starglass in System Settings → General → Login Items." : nil
                } catch { loginError = error.localizedDescription }
                let status = SMAppService.mainApp.status
                launchAtLogin = status == .enabled || status == .requiresApproval
            }))
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }

            Toggle("Show tonight's score in the menu bar", isOn: $showScore)
            Toggle("Notify when a clear dark night is coming", isOn: Binding(get: { model.notifyEnabled }, set: { enabled in Task { await model.setNotifications(enabled) } }))
            Button("Clear saved city and forecast") { model.clearSavedData() }

            Divider()
            PolicySupportLinks()
            HStack {
                Text("Version \(ProductInfo.version) (\(ProductInfo.build))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("About Starglass") { showAbout() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }.padding(24).frame(width: 520)
    }

    func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Starglass",
            .applicationVersion: ProductInfo.version,
        ])
    }
}
