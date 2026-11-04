import SwiftUI
import ServiceManagement
import HushKeyCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?
    @State private var hotKey = HotKeyConfig.decode(UserDefaults.standard.string(forKey: "hotKey") ?? "") ?? .default
    @State private var pushToTalk = UserDefaults.standard.bool(forKey: "pushToTalk")
    @State private var showBadge = UserDefaults.standard.bool(forKey: "showBadge")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HushKey settings").font(.title2.bold())
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = SMAppService.mainApp.status == .requiresApproval
                        ? "Approve HushKey in System Settings → General → Login Items." : nil
                } catch { loginError = error.localizedDescription }
                let status = SMAppService.mainApp.status
                launchAtLogin = status == .enabled || status == .requiresApproval
            }))
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }

            Divider()
            Text("Mute shortcut").font(.headline)
            Picker("Key", selection: Binding(get: { hotKey.keyCode }, set: { code in
                hotKey.keyCode = code; saveHotKey()
            })) {
                ForEach(HotKeyConfig.selectableKeyCodes, id: \.self) { code in
                    Text(HotKeyConfig.keyName(code)).tag(code)
                }
            }
            Toggle("Add Shift", isOn: Binding(get: { hotKey.useShift }, set: { hotKey.useShift = $0; saveHotKey() }))
            Toggle("Add Option", isOn: Binding(get: { hotKey.useOption }, set: { hotKey.useOption = $0; saveHotKey() }))
            Text("Global shortcut \(hotKey.label)").font(.caption).foregroundStyle(.secondary)
            Toggle("Push-to-talk (hold to unmute)", isOn: Binding(get: { model.pushToTalk }, set: { pushToTalk = $0; UserDefaults.standard.set($0, forKey: "pushToTalk"); model.setPushToTalk($0) }))

            Divider()
            Toggle("Show floating mic badge", isOn: Binding(get: { model.showBadge }, set: { showBadge = $0; UserDefaults.standard.set($0, forKey: "showBadge"); model.setShowBadge($0) }))
            Toggle("Hide volume in menu bar", isOn: Binding(get: { model.hideVolume }, set: { model.setHideVolume($0) }))
            Picker("When the default mic changes", selection: Binding(get: { model.intent }, set: { model.setIntent($0) })) {
                ForEach(ReapplyLogic.Intent.allCases, id: \.self) { intent in
                    Text(intentTitle(intent)).tag(intent)
                }
            }

            Divider()
            Toggle("Sample mode (simulated microphones)", isOn: Binding(get: { model.sampleMode }, set: { model.setSampleMode($0) }))
                .accessibilityIdentifier("sampleModeToggle")
            Text("Sample mode simulates devices so every control can be tried without touching the real microphone. No audio is recorded at any time.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Text(model.lastOutcome).font(.caption).accessibilityIdentifier("operationStatus")
            Button("Reset Local Preferences and Device Memory") { model.resetStoredData(); hotKey = .default }
            PolicySupportLinks()
            HStack {
                Text("Version \(ProductInfo.version) (\(ProductInfo.build))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }.padding(24).frame(width: 520)
    }

    private func saveHotKey() {
        UserDefaults.standard.set(HotKeyConfig.encode(hotKey), forKey: "hotKey")
        model.applyHotKey(hotKey)
    }

    private func intentTitle(_ intent: ReapplyLogic.Intent) -> String {
        switch intent {
        case .alwaysMute: return "Always mute it"
        case .stayMutedOnly: return "Keep it muted if it was muted"
        case .off: return "Do nothing"
        }
    }
}
