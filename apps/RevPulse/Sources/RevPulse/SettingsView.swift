import SwiftUI
import RevPulseCore

public struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var keyInput = ""
    @State private var keyError: String?
    @State private var keySaved = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Form {
            Section("Stripe key") {
                if model.hasKey() {
                    Text("A restricted key is saved in the Keychain.").font(.callout)
                    Button("Remove key") { model.removeKey() }
                    if model.sampleMode { Button("Return to live data") { model.useSavedKey() } }
                } else {
                    SecureField("rk_live_…", text: $keyInput)
                    Button("Save key") { saveKey() }
                }
                if let err = keyError { Text(err).foregroundStyle(.red).font(.callout) }
                if keySaved { Text("Key saved.").foregroundStyle(.green).font(.callout) }
                Text("Use a Stripe restricted key with read-only access. It is stored in your Keychain and sent only to api.stripe.com over HTTPS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Refresh") {
                Picker("Every", selection: $model.refreshInterval) {
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                    Text("30 minutes").tag(1800.0)
                }
            }
            Section("Goal") {
                Stepper(value: $model.goalCents, in: 100...10_000_000, step: 500) {
                    Text("Monthly goal \(Formatting.money(model.goalCents, currency: model.snapshot?.currency ?? "USD"))")
                }
            }
            Section("Notifications") {
                Toggle("First sale of the UTC day", isOn: $model.notificationsEnabled)
                Toggle("Failed payments", isOn: $model.failedPaymentNotificationsEnabled)
                if model.sampleMode {
                    Button("Send Sample first-sale alert") { Task { await model.sendSampleNotification(failedPayment: false) } }
                    Button("Send Sample failed-payment alert") { Task { await model.sendSampleNotification(failedPayment: true) } }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Button("Try Sample mode") { model.loadSample() }
                    .accessibilityIdentifier("trySampleButton")
                Text(model.sampleMode ? "Sample data" : "Live connection").font(.caption).foregroundStyle(.secondary)
                if let error = model.errorText { Text(error).foregroundStyle(.red).font(.caption) }
                PolicySupportLinks()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 720)
        .onDisappear { model.persistSettings() }
    }

    func saveKey() {
        keyError = nil; keySaved = false
        do {
            try model.setKey(keyInput)
            keyInput = ""
            keySaved = true
        } catch {
            keyError = error.localizedDescription
        }
    }
}
