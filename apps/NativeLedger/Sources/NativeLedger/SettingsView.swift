import SwiftUI
import LedgerCore

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var alerts: AlertController
    var body: some View {
        SettingsForm(model: state.current, alerts: alerts)
            .id(ObjectIdentifier(state.current))
    }
}

struct SettingsForm: View {
    @ObservedObject var model: LedgerModel
    @ObservedObject var alerts: AlertController
    @AppStorage(LedgerModel.staleKey) private var staleDays = LedgerModel.defaultStaleDays
    static let staleChoices = [7, 14, 30, 60, 90]
    static let alertToggleLabel = "Alert me about high-severity changes"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("NativeLedger settings").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Toggle(Self.alertToggleLabel, isOn: Binding(get: { alerts.enabled }, set: { on in
                    Task { await alerts.setEnabled(on) }
                }))
                .disabled(alerts.requesting)
                Text("Off by default. When it is on, NativeLedger shows a local notification when an automatic entry has Signature invalid, Team change or New background item. The notification names the app and the anomaly.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !alerts.message.isEmpty {
                    Label(alerts.message, systemImage: "bell.slash").font(.caption).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Picker("Mark an app as not read lately after", selection: $staleDays) {
                    ForEach(Self.staleChoices, id: \.self) { Text("\($0) days").tag($0) }
                }
                .frame(maxWidth: 420)
                Text("Only a label. While NativeLedger is open, it reads an app in a watched folder again when the app changes.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(model.isSample ? "Tracked apps · Sample" : "Tracked apps").font(.headline)
                if model.ledgers.isEmpty {
                    Text("No apps yet. Use Watch a Folder or Add App in the main window.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.ledgers) { ledger in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ledger.displayName).font(.callout.weight(.medium))
                                        Text("\(ledger.entries.count) \(ledger.entries.count == 1 ? "entry" : "entries")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Remove", role: .destructive) { model.remove(ledger.id) }
                                        .disabled(!model.canWrite)
                                        .accessibilityLabel("Remove \(ledger.displayName)")
                                }
                            }
                        }
                    }.frame(maxHeight: 180)
                }
                Text(model.isSample
                     ? "Removing a Sample app only changes the Sample in memory."
                     : "Remove deletes the ledger and its saved read access. Export first to keep a copy.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            PolicySupportLinks()
            HStack {
                Text("Version \(ProductInfo.version) (\(ProductInfo.build))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("About NativeLedger") { showAbout() }
            }
        }
        .padding(24).frame(width: 560)
    }
}
