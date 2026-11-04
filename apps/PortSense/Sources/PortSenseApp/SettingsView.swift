import SwiftUI
import ServiceManagement
import MASKit

struct SettingsView: View {
    @ObservedObject var model: AppState
    @StateObject private var login = LoginPreference()
    var body: some View {
        TabView {
            Form {
                Toggle("Launch at Login", isOn: Binding(get: { login.enabled || login.needsApproval }, set: login.update))
                    .accessibilityLabel("Launch PortSense at Login")
                Text("Off by default. Changes apply to this app only.").font(.caption).foregroundStyle(.secondary)
                if login.needsApproval {
                    Text("Allow PortSense in Login Items to finish enabling it.").font(.caption)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .accessibilityLabel("Open system Login Items settings")
                }
                if let error = login.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Refresh login status") { login.sync() }.accessibilityLabel("Refresh Launch at Login status")
                }
                Divider()
                Toggle("Sample mode", isOn: Binding(get: { model.isSample }, set: model.setSample))
                    .accessibilityLabel("Use Sample hardware readings")
                Text("Sample shows neutral examples of Power, Connections, and History. Turn it off for live readings.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Charger rating")
                    Spacer()
                    TextField("Watts", value: Binding(get: { model.effectiveRating }, set: model.setChargerRating), format: .number.precision(.fractionLength(0)))
                        .frame(width: 70).accessibilityLabel("Charger rated watts")

                    Text("W")
                }
                Text("Use the rating printed on the charger. Set 0 to disable the warning. A lower macOS reading may indicate a cable, dock, or shared power limit.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Include built-in USB devices", isOn: $model.showBuiltIn).accessibilityLabel("Include built-in USB devices")
            }
            .padding(22)
            .tabItem { Label("General", systemImage: "gearshape") }
            VStack(spacing: 12) {
                Image(systemName: "cable.connector").font(.system(size: 42)).foregroundStyle(.tint).accessibilityHidden(true)
                Text("PortSense").font(.title2.bold())
                Text("Version 1.0.0 · " + PortLinks.copyright()).font(.caption).foregroundStyle(.secondary)
                Text("See the power and USB connection details macOS reports. No account or analytics. Hardware readings stay local.")
                    .multilineTextAlignment(.center).frame(maxWidth: 320)
                Text("Readings stay on this Mac. Missing hardware fields are shown as unavailable.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
                Button("Read privacy policy") { model.openPrivacy() }
                PortLinksView(model: model)
            }
            .padding(24)
            .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 440)
        .onAppear { login.sync() }
        .onExitCommand { NSApp.keyWindow?.close() }
    }
}
