import SwiftUI
import AppKit
import CostBarCore
import MASKit
import ServiceManagement

struct PopoverView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CostBar").font(.title3.weight(.semibold))
                    Label(model.state, systemImage: model.warning ? "exclamationmark.circle.fill" : "circle.fill")
                        .font(.caption).foregroundStyle(model.warning ? Color.orange : Color.secondary)
                }
                Spacer()
                Button { model.refresh(model.selected) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!model.connected.contains(model.selected) || model.refreshing.contains(model.selected))
                .accessibilityLabel("Refresh \(model.selected.name) spend")
                .help("Refresh reported costs")
            }
            Text(model.coverageText).font(.caption).foregroundStyle(.secondary)
            if let issues = model.connectionIssues {
                Text(issues).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            ProviderSelector(selection: Binding(get: { model.selected }, set: model.select))
            if let snapshot = model.snapshot {
                spendContent(snapshot)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text(model.errors[model.selected] ?? (model.connected.contains(model.selected) ? "Your first cost report is being requested." : "Connect \(model.selected.name) to see your API spend."))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button(model.connected.contains(model.selected) ? "Refresh costs" : "Connect provider") {
                        if model.connected.contains(model.selected) { model.refresh(model.selected) } else { model.openSettings() }
                    }
                    .disabled(model.refreshing.contains(model.selected))
                    .accessibilityLabel("\(model.connected.contains(model.selected) ? "Refresh" : "Connect") \(model.selected.name)")
                    Button("Try with sample data") { model.enterSample() }
                        .accessibilityLabel("Try CostBar with sample data")
                }.frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            }
            if let message = model.errors[model.selected], model.snapshot != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Review connection") { model.openSettings() }.font(.caption).accessibilityLabel("Review provider connection settings")
                }
            }
            if model.sample {
                if let message = model.notificationMessage {
                    Label(message, systemImage: "bell")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Exit Sample mode") { model.leaveSample() }
                    .disabled(model.accessingKeys || model.sampleNotificationInFlight).font(.caption).accessibilityLabel("Exit Sample mode and return to your providers")
            }
            Divider()
            AccountsEntryRow()
            Divider()
            HStack {
                Button("Settings…") { model.openSettings() }.keyboardShortcut(",", modifiers: .command).accessibilityLabel("Open CostBar Settings")
                Spacer()
                DocumentLinksView()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command).accessibilityLabel("Quit CostBar")
            }.buttonStyle(.plain).font(.callout)
        }
        .buttonStyle(.plain)
        .padding(16).frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(red: 1, green: 159.0 / 255, blue: 10.0 / 255))
        .onExitCommand { NSApp.keyWindow?.close() }
    }
    private func spendContent(_ snapshot: SpendSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.showingExpandedCredits, let credits = snapshot.remainingCredits {
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.sample ? "Sample · account credits left" : "Account credits left", systemImage: "creditcard").font(.callout)
                    Text(Money.string(credits)).font(.system(size: 32, weight: .semibold, design: .rounded))
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("MONTH TO DATE · USD").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Text(Money.string(snapshot.monthlyUSD)).font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
                    .accessibilityLabel("Month to date spend, \(Money.string(snapshot.monthlyUSD))")
                Text(model.selected.scope).font(.caption).foregroundStyle(.secondary)
            }
            if !model.showingExpandedCredits {
                HStack(spacing: 10) {
                    metric("Today", value: Money.string(snapshot.dailyUSD), symbol: "sun.max")
                    metric("Hourly average", value: Money.string(snapshot.hourlyUSD), symbol: "flame")
                }
            }
            if model.selected == .openRouter {
                HStack(spacing: 10) {
                    metric("Key this week", value: snapshot.weeklyUSD.map(Money.string) ?? "Unknown", symbol: "calendar")
                    metric("Key lifetime", value: snapshot.lifetimeUSD.map(Money.string) ?? "Unknown", symbol: "clock")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Monthly budget").font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(min(999, model.budget.fraction(spend: snapshot.monthlyUSD) * 100)))% used").font(.caption.weight(.medium))
                        .foregroundStyle(model.warning ? Color.orange : Color.secondary)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(Color(red: 1, green: 159.0 / 255, blue: 10.0 / 255))
                            .frame(width: geometry.size.width * min(1, model.budget.fraction(spend: snapshot.monthlyUSD)))
                    }
                }.frame(height: 6)
                    .accessibilityElement()
                    .accessibilityLabel("Monthly budget used")
                    .accessibilityValue("\(Int(min(999, model.budget.fraction(spend: snapshot.monthlyUSD) * 100))) percent")
                HStack {
                    Text("\(Money.string(model.budget.monthlyUSD)) budget")
                    Spacer()
                    Text("Alert at \(model.budget.thresholdPercent)%")
                }.font(.caption).foregroundStyle(.secondary)
                if model.warning {
                    Label("Your budget threshold has been reached.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }.padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Projected month-end").font(.caption).foregroundStyle(.secondary)
                    Text(model.forecastText).font(.title3.weight(.medium)).monospacedDigit()
                }
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.secondary).font(.title2).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let remaining = snapshot.remainingCredits {
                    Button(model.showingExpandedCredits ? "Hide account credit details" : "Account credits left: \(Money.string(remaining))") { model.focusCredits.toggle() }
                        .font(.caption).accessibilityLabel("Toggle account credit details")
                } else if let note = snapshot.creditNote { Text(note).font(.caption) }
                Text("UTC periods · reported costs can lag. Forecast assumes this month's average pace; hourly average uses today, with a one-hour minimum.")
                    .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                if !model.sample {
                    Text("Updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(snapshot.isStale(at: Date()) ? Color.orange : Color.secondary)
                }
            }.foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            VStack(alignment: .leading, spacing: 18) {
                Label("CostBar", systemImage: "chart.bar.fill").font(.largeTitle.weight(.semibold))
                Text("Version 1.0.0 · " + (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 Michael Lip")).foregroundStyle(.secondary)
                Text("Your API spend, within reach.").font(.title3)
                if model.sample { Label("Sample mode", systemImage: "flask").foregroundStyle(.orange) }
                DocumentLinksView()
                Text("Provider reports stay on this Mac. Keys are stored in Keychain. CostBar sends authenticated read-only requests directly to the provider you connect and sends nothing to the developer.")
                Text("Budgets are reminders, not spending caps. Costs may lag and projections are estimates. Provider billing dashboards remain the source of truth.")
                Spacer()
            }.padding(30).tabItem { Label("About", systemImage: "info.circle") }
        }.padding(12).frame(width: 540, height: 590)
                .onExitCommand { NSApp.keyWindow?.close() }
    }
}

struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var keyText = ""
    @State private var budgetText = "100"
    @State private var threshold = 80
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.sample {
                    Label("Sample mode · budgets and alerts are previews", systemImage: "flask").font(.callout).foregroundStyle(.orange)
                    Button("Exit Sample mode") { model.leaveSample() }.disabled(model.accessingKeys || model.sampleNotificationInFlight).accessibilityLabel("Exit Sample mode")
                } else {
                    Button("Try with sample data") { model.enterSample() }.accessibilityLabel("Try CostBar with sample data")
                }
                GroupBox("Startup & alerts") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                            .accessibilityLabel("Launch CostBar at login")
                        if model.loginPending {
                            Text("Approval pending in System Settings. Turn this off to cancel registration.").font(.caption).foregroundStyle(.secondary)
                            Button("Review Login Items") { SMAppService.openSystemSettingsLoginItems() }
                                .accessibilityLabel("Review pending CostBar login registration")
                        }
                        Toggle("Notify when a monthly budget threshold is reached", isOn: Binding(get: { model.preferences.alertsEnabled }, set: model.setAlerts))
                            .accessibilityLabel("Enable monthly budget threshold notifications")
                        if model.sample {
                            Button("Send Sample notification") { Task { await model.testSampleNotification() } }
                                .disabled(model.sampleNotificationInFlight).accessibilityLabel("Send a real Sample notification without an account")
                        }
                        if let message = model.notificationMessage { Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }.padding(8)
                }
                Picker("Provider", selection: Binding(get: { model.selected }, set: model.select)) {
                    ForEach(Provider.allCases) { Text($0.name).tag($0) }
                }.pickerStyle(.segmented).accessibilityLabel("Provider to configure")
                GroupBox("Connection") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label(model.sample ? (model.connected.contains(model.selected) ? "Sample key saved in Keychain" : "Sample report · no key required") : model.connected.contains(model.selected) ? "Key saved in Keychain" : "No key saved", systemImage: model.connected.contains(model.selected) ? "lock.shield" : "key")
                            Spacer()
                            Link("Get a key ↗", destination: model.selected.setupURL).accessibilityLabel("Open \(model.selected.name) key setup")
                        }.font(.callout)
                        if model.sample {
                            Text("Use the supplied demo key to test Keychain save, read, update, removal and local refresh. Real provider keys are not accepted in Sample mode.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Fill sample key") { keyText = AppModel.sampleKey }
                                .accessibilityLabel("Fill the supplied Sample key; no private credentials needed")
                        }
                        Text(model.sample ? "Sample connections use bundled reports and a separate Keychain item; no provider request is sent." : model.selected.keyHint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        SecureField("Paste a new key", text: $keyText).disabled(model.accessingKeys).textFieldStyle(.roundedBorder).accessibilityLabel("New \(model.selected.name) API key")
                        HStack {
                            Button("Save & connect") {
                                let text = keyText, provider = model.selected
                                Task { if await model.saveKey(text, provider: provider) { keyText = "" } }
                            }
                                .disabled(model.accessingKeys || keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Save key in Keychain and connect")
                            Button("Remove key", role: .destructive) {
                                let provider = model.selected
                                Task { await model.removeKey(provider); keyText = "" }
                            }
                                .disabled(model.accessingKeys || !model.connected.contains(model.selected)).accessibilityLabel("Remove saved API key and cached costs")
                        }
                        if let error = model.errors[model.selected] { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                        else if model.refreshing.contains(model.selected) { Text("Requesting the cost report…").font(.caption).foregroundStyle(.secondary) }
                        else if let snapshot = model.snapshots[model.selected] { Text("\(model.sample ? "Sample" : "Connected") · month to date \(Money.string(snapshot.monthlyUSD))").font(.caption).foregroundStyle(.secondary) }
                    }.padding(8)
                }
                GroupBox("\(model.selected.name) monthly budget") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Budget in USD")
                            TextField("100.00", text: $budgetText).textFieldStyle(.roundedBorder).frame(width: 110).accessibilityLabel("Monthly budget in USD")
                            Spacer()
                        }
                        HStack {
                            Picker("Alert threshold", selection: $threshold) {
                                ForEach([50, 75, 80, 90, 100], id: \.self) { Text("\($0)%").tag($0) }
                            }.frame(width: 230).accessibilityLabel("Budget alert threshold percentage")
                            Spacer()
                            Button("Save budget") { model.saveBudget(budgetText, threshold: threshold, provider: model.selected) }.accessibilityLabel("Save provider monthly budget")
                        }
                        Text("Each provider has its own budget. Refreshes every five minutes while CostBar runs. Alerts do not stop API usage.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(8)
                }
                if let message = model.settingsMessage { Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.padding(14)
        }
        .onAppear { loadBudget() }
        .onChange(of: model.selected) { keyText = ""; model.settingsMessage = nil; loadBudget() }
        .onChange(of: model.sample) { keyText = ""; loadBudget() }
        .onDisappear { keyText = "" }
    }
    private func loadBudget() {
        budgetText = NSDecimalNumber(decimal: model.budget.monthlyUSD).stringValue
        threshold = model.budget.thresholdPercent
    }
}

/// A SwiftUI-only selector also renders faithfully with ImageRenderer.
private struct ProviderSelector: View {
    @Binding var selection: Provider
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Provider.allCases) { provider in
                Button { selection = provider } label: {
                    Text(provider.name)
                        .font(.system(size: 11, weight: selection == provider ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(selection == provider ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(provider.name) spend")
                .accessibilityValue(selection == provider ? "Selected" : "")
            }
        }.padding(3).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Only configured HTTPS destinations for this app can leave the native local documents.
enum CostBarLinks {
    static func privacyPolicy(_ bundle: Bundle = .main) -> URL? {
        configuredURL("MASPrivacyPolicyURL", allowedPaths: ["/apps/costbar/privacy/", "/costbar/privacy/", "/mac-apps/costbar/privacy/"], bundle: bundle)
    }
    static func support(_ bundle: Bundle = .main) -> URL? {
        configuredURL("MASSupportURL", allowedPaths: ["/apps/costbar/support/", "/costbar/support/", "/mac-apps/costbar/support/"], bundle: bundle)
    }
    private static func configuredURL(_ key: String, allowedPaths: [String], bundle: Bundle) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String,
              !raw.contains("{"), !raw.contains("}"),
              let parts = URLComponents(string: raw), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, allowedPaths.contains(parts.path),
              parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
}

/// Entry point into the account and credit workflow from the menu bar popover.
struct AccountsEntryRow: View {
    @ObservedObject private var accounts = AccountsModel.shared
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Accounts & credits").font(.callout.weight(.medium))
                Text(accounts.workspace.accounts.isEmpty && !accounts.sample ? "Connect two accounts, record credits, export a redacted report." : accounts.summaryLine)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open…") { accounts.openWindow() }.accessibilityLabel("Open accounts and credits")
        }
    }
}
