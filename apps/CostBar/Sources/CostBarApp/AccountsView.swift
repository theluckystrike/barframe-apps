import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CostBarCore

struct AccountsView: View {
    @ObservedObject var model: AccountsModel
    @State private var adding = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            Divider()
            Group {
                if adding || model.workspace.accounts.isEmpty { AddAccountForm(model: model, adding: $adding) }
                else if let account = model.selectedAccount { AccountDetail(model: model, account: account).id(account.id) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 820, minHeight: 640)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts").font(.title3.weight(.semibold))
            Text(model.summaryLine).font(.caption).foregroundStyle(.secondary)
            List(selection: Binding(get: { model.selectedAccount?.id }, set: { if let id = $0 { adding = false; model.select(id) } })) {
                ForEach(model.workspace.accounts) { account in
                    let status = model.status(account)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.label).font(.callout.weight(.medium)).lineLimit(1)
                        Text("\(account.provider.name) · ID \(account.shortID)").font(.caption2).foregroundStyle(.secondary)
                        Label(status.headline, systemImage: status.state == .current ? "checkmark.circle" : status.state == .manual ? "pencil.circle" : "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(status.state == .current || status.state == .manual ? Color.secondary : Color.orange)
                    }.tag(account.id).accessibilityElement(children: .combine)
                }
            }.listStyle(.sidebar)
            Button("Add account…") { adding = true }.disabled(model.sample).accessibilityLabel("Add a provider account")
            if model.sample {
                Button("Exit Sample mode") { adding = false; model.leaveSample() }.accessibilityLabel("Exit Sample mode")
            } else {
                Button("Load synthetic sample") { adding = false; model.enterSample() }
                    .accessibilityLabel("Load a labelled synthetic two-account sample")
            }
            Button("Export redacted report…") { exportReport() }.disabled(model.workspace.accounts.isEmpty).accessibilityLabel("Export a redacted report")
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(12)
    }
    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = model.sample ? "costbar-sample-report.json" : "costbar-redacted-report.json"
        panel.message = "Saves pseudonymous account IDs and typed figures. No keys, labels, URLs or file paths. Nothing is sent anywhere."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = model.export(to: url)
    }
}

private struct AddAccountForm: View {
    @ObservedObject var model: AccountsModel
    @Binding var adding: Bool
    @State private var provider: Provider = .anthropic
    @State private var label = ""
    @State private var key = ""
    @State private var manualOnly = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add an account").font(.title3.weight(.semibold))
            Text("Each account has its own identity, records and settings. You can add several from one provider. Existing provider keys from the main CostBar screen are not read or copied.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Provider", selection: $provider) { ForEach(Provider.allCases) { Text($0.name).tag($0) } }.pickerStyle(.segmented)
            Picker("Mode", selection: $manualOnly) {
                Text("Manual records only · no key").tag(true)
                Text("Connect a reporting key").tag(false)
            }.pickerStyle(.segmented).accessibilityLabel("Account mode")
            if manualOnly {
                Text("Record dated credits, debt and plan allowance by hand. No key is stored and no request is sent. Personal Anthropic accounts cannot use the Admin API, so this is the way to track them. You can add a reporting key to this account later.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(provider.keyHint).font(.caption).foregroundStyle(.secondary)
                Text("Reports show \(ReportingScope.scope(for: provider).label.lowercased()). \(ReportingScope.scope(for: provider).caveat)").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Display name (optional, stays on this Mac, never exported)", text: $label).textFieldStyle(.roundedBorder)
            if !manualOnly {
                SecureField("Paste a new key for this account", text: $key).textFieldStyle(.roundedBorder).accessibilityLabel("API key for the new account")
            }
            HStack {
                Button(manualOnly ? "Add manual account" : "Save & connect") {
                    let k = key, p = provider, l = label
                    if manualOnly { if model.addManualAccount(provider: p, label: l) { label = ""; adding = false } }
                    else { Task { if await model.addAccount(provider: p, label: l, key: k) { key = ""; label = ""; adding = false } } }
                }.disabled(model.sample || (!manualOnly && (model.accessingKeys || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                if !model.workspace.accounts.isEmpty { Button("Cancel") { key = ""; adding = false } }
                if !manualOnly { Link("Get a key ↗", destination: provider.setupURL) }
            }
            if model.sample { Text(AccountInputError.sampleReadOnly.localizedDescription).font(.caption).foregroundStyle(.orange) }
            Spacer()
        }.padding(20)
    }
}

private struct AccountDetail: View {
    @ObservedObject var model: AccountsModel
    let account: ProviderAccount
    @State private var newKey = ""
    @State private var confirmRemove = false
    var body: some View {
        let status = model.status(account)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                identity(status)
                report(status)
                workloadSection
                grantsSection
                debtSection
                allowanceSection
                logSection
            }.padding(18)
        }
    }

    // Identity, scope, source, observation time
    private func identity(_ status: AccountStatus) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(account.label).font(.title3.weight(.semibold))
                    if account.isSample { Text("SAMPLE").font(.caption.bold()).padding(3).background(.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 4)) }
                    Spacer()
                    Button("Refresh") { model.refresh(account.id) }
                        .disabled(model.sample || account.connection != .connected || model.refreshing.contains(account.id))
                        .accessibilityLabel("Refresh \(account.label)")
                }
                row("Provider", account.provider.name)
                row("Account ID", account.id)
                row("Reporting scope", ReportingScope.scope(for: account.provider).label)
                row("Report source", account.isSample ? DataSource.syntheticSample.label : account.connection == .manualOnly ? "None · manual records only" : DataSource.providerAPI.label)
                row("Observed", model.workspace.reports[account.id].map { $0.observedAt.formatted(date: .abbreviated, time: .standard) + " (UTC \(UTCClock.iso($0.observedAt)))" } ?? "Not yet observed")
                Label(status.headline, systemImage: status.state == .current ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(status.state == .current ? Color.green : status.state == .manual ? Color.secondary : Color.orange)
                if let detail = status.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if model.refreshing.contains(account.id) { Text("Requesting the cost report…").font(.caption).foregroundStyle(.secondary) }
                Text(ReportingScope.scope(for: account.provider).caveat).font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField(account.connection == .manualOnly ? "Reporting key (optional, adds spend reports)" : "New key for this account only", text: $newKey).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    Button(account.connection == .connected ? "Replace key" : account.connection == .manualOnly ? "Add reporting key" : "Reconnect") {
                        let k = newKey
                        Task { if await model.replaceKey(account.id, key: k) { newKey = "" } }
                    }.disabled(model.accessingKeys || model.sample || newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Disconnect") { Task { await model.disconnect(account.id) } }
                        .disabled(model.accessingKeys || model.sample || account.connection != .connected)
                        .help("Deletes this account's key. The last observation stays, labelled unavailable.")
                    Button("Remove account…", role: .destructive) { confirmRemove = true }.disabled(model.accessingKeys || model.sample)
                }
            }.padding(6)
        }
        .confirmationDialog("Remove \(account.label) and its saved key, report and manual records?", isPresented: $confirmRemove) {
            Button("Remove account and data", role: .destructive) { Task { await model.removeAccount(account.id) } }
        }
    }
    private func report(_ status: AccountStatus) -> some View {
        GroupBox("Reported API cost (not credit, not subscription)") {
            VStack(alignment: .leading, spacing: 6) {
                if let snapshot = model.workspace.reports[account.id]?.snapshot {
                    let historical = status.historicalNote != nil
                    row(historical ? "Month total (historical)" : "Month to date", Money.string(snapshot.monthlyUSD) + (historical ? " · UTC \(UTCClock.monthID(snapshot.fetchedAt))" : ""))
                    row(historical ? "Day total (historical)" : "Today", Money.string(snapshot.dailyUSD) + (historical ? " · \(String(UTCClock.iso(UTCClock.day(snapshot.fetchedAt)).prefix(10))) UTC" : ""))
                    if let note = status.historicalNote { Text(note).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                } else if account.connection == .manualOnly {
                    Text("Provider spend is not connected for this account. Credits, debt and allowance below are manual records.").font(.callout).foregroundStyle(.secondary)
                } else { Text("No complete report has been observed for this account.").font(.callout).foregroundStyle(.secondary) }
                Text("Reports are shown only when every page was received. A failed or partial refresh keeps the last complete observation.").font(.caption).foregroundStyle(.secondary)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Workload and eligibility
    private var workloadSection: some View {
        let summary = model.eligibility(account)
        return GroupBox("Eligible API funds by workload (manual grants)") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Workload", selection: Binding(get: { account.selectedWorkload }, set: { model.setWorkload($0, for: account.id) })) {
                    ForEach(Workload.allCases) { Text($0.name).tag($0) }
                }.accessibilityLabel("Workload for eligibility")
                if summary.applicable {
                    Text(Money.string(summary.totalUSD)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("Counts only non-expired grants explicitly marked eligible for \(summary.workload.name). Unknown eligibility is not counted.").font(.caption).foregroundStyle(.secondary)
                    row("Next eligible expiry", summary.nextExpiry.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No eligible grant")
                    row("Not counted", "\(summary.expiredCount) expired · \(summary.notEligibleCount) not eligible or unknown" + (summary.notYetObservedCount > 0 ? " · \(summary.notYetObservedCount) dated in the future" : ""))
                } else {
                    Text("Subscription use is paid from a plan allowance, not dollar credits. No dollar total applies; see the allowance observation below.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                Text("A monthly Max plan API promotion can never count as ordinary Claude Code funds.").font(.caption).foregroundStyle(.secondary)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @State private var grantBalance = ""
    @State private var grantExpiry = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var grantObserved = Date()
    @State private var grantKind: GrantKind = .prepaidCredit
    @State private var grantSource = ""
    @State private var grantWorkloads: Set<Workload> = []
    private var grantsSection: some View {
        GroupBox("Credit grants · manual records, dated") {
            VStack(alignment: .leading, spacing: 8) {
                let grants = model.grants(account)
                Text("These records are entered manually. CostBar has not verified them with the provider.").font(.caption).foregroundStyle(.secondary)
                if grants.isEmpty { Text("No grants recorded. Enter an observed balance from your console or receipt. A zero total here does not verify your provider balance.").font(.caption).foregroundStyle(.secondary) }
                ForEach(grants) { grant in
                    let expired = grant.expiresAt <= model.now
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Money.string(grant.balanceUSD)) · \(grant.kind.name)\(grant.isSample ? " · SAMPLE" : "")").font(.callout.weight(.medium))
                            Text("\(grant.observedAt > model.now ? "NOT COUNTED · observation date is in the future · " : "")\(expired ? "EXPIRED " : "Expires ")\(grant.expiresAt.formatted(date: .abbreviated, time: .omitted)) · observed \(grant.observedAt.formatted(date: .abbreviated, time: .omitted)) · manual")
                                .font(.caption).foregroundStyle(expired ? Color.orange : Color.secondary)
                            Text("Eligible: " + (grant.eligible.isEmpty ? "unknown (counts for nothing)" : grant.eligible.map(\.name).sorted().joined(separator: ", "))
                                 + (grant.sourceLabel.isEmpty ? "" : " · \(grant.sourceLabel)")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Delete") { model.removeGrant(grant.id) }.font(.caption).accessibilityLabel("Delete grant")
                    }
                }
                Divider()
                HStack {
                    TextField("Balance USD, e.g. 25.00", text: $grantBalance).textFieldStyle(.roundedBorder).frame(width: 170)
                    Picker("Kind", selection: $grantKind) { ForEach(GrantKind.allCases) { Text($0.name).tag($0) } }.labelsHidden().frame(width: 190)
                }
                HStack {
                    DatePicker("Expires", selection: $grantExpiry).datePickerStyle(.compact)
                    DatePicker("Observed", selection: $grantObserved, in: ...Date()).datePickerStyle(.compact)
                }
                Text("Dates use this Mac’s time zone. Convert UTC dates from the provider console before you enter them.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Explicitly eligible for:").font(.caption)
                    ForEach([Workload.directAPI, .agentSDK, .claudeCode]) { workload in
                        Toggle(workload.name, isOn: Binding(get: { grantWorkloads.contains(workload) },
                                                            set: { if $0 { grantWorkloads.insert(workload) } else { grantWorkloads.remove(workload) } }))
                            .toggleStyle(.checkbox).font(.caption)
                            .disabled(workload == .claudeCode && grantKind == .maxPlanAPIPromotion)
                    }
                }
                TextField("Source label (your own note; never exported)", text: $grantSource).textFieldStyle(.roundedBorder)
                Button("Add grant") {
                    if model.addGrant(accountID: account.id, balance: grantBalance, expiresAt: grantExpiry, eligible: grantWorkloads, kind: grantKind, sourceLabel: grantSource, observedAt: grantObserved) {
                        grantBalance = ""; grantSource = ""; grantWorkloads = []; grantObserved = Date()
                    }
                }.disabled(grantBalance.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("Leave all boxes off when eligibility is unknown; the grant then funds no workload.").font(.caption).foregroundStyle(.secondary)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: grantKind) { if grantKind == .maxPlanAPIPromotion { grantWorkloads.remove(.claudeCode) } }
    }

    // Debt
    @State private var debtText = ""
    private var debtSection: some View {
        GroupBox("Debt or amount owed · separate, manual") {
            VStack(alignment: .leading, spacing: 6) {
                if let debt = account.debt {
                    Text("\(Money.string(debt.amountUSD)) owed · observed \(debt.observedAt.formatted(date: .abbreviated, time: .omitted)) · manual" + (debt.observedAt > model.now ? " · dated in the future, not a current observation" : "")).foregroundStyle(.orange)
                } else { Text("No debt recorded.").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    TextField("USD owed (0 clears)", text: $debtText).textFieldStyle(.roundedBorder).frame(width: 170)
                    Button("Save debt") { if model.saveDebt(accountID: account.id, text: debtText, observedAt: model.now) { debtText = "" } }.disabled(debtText.isEmpty)
                }
                Text("Debt is never subtracted from credits or added to spend.").font(.caption).foregroundStyle(.secondary)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Subscription allowance
    @State private var allowancePercent = ""
    @State private var allowanceReset = Date().addingTimeInterval(5 * 3600)
    @State private var allowanceObserved = Date()
    @State private var allowanceLabel = ""
    private var allowanceSection: some View {
        GroupBox("Subscription allowance · manual observation") {
            VStack(alignment: .leading, spacing: 6) {
                if let a = model.workspace.allowances[account.id] {
                    let outdated = a.isOutdated(at: model.now)
                    Text("\(a.percentUsed.formatted(.number.precision(.fractionLength(0...2))))% used · resets \(a.resetsAt.formatted(date: .abbreviated, time: .shortened))\(a.isSample ? " · SAMPLE" : "")")
                        .font(.callout.weight(.medium))
                    Text("Manual observation from \(a.observedAt.formatted(date: .abbreviated, time: .shortened))" + (a.label.isEmpty ? "" : " · \(a.label)") + (outdated ? " · reset time has passed, so this is outdated" : "") + (a.isNotYetObserved(at: model.now) ? " · dated in the future, not a current observation" : ""))
                        .font(.caption).foregroundStyle(outdated || a.isNotYetObserved(at: model.now) ? Color.orange : Color.secondary)
                    Button("Clear observation") { model.clearAllowance(account.id) }.font(.caption)
                } else { Text("No allowance observation.").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    TextField("Percent used, 0–100", text: $allowancePercent).textFieldStyle(.roundedBorder).frame(width: 150)
                    TextField("Note (never exported)", text: $allowanceLabel).textFieldStyle(.roundedBorder)
                }
                HStack {
                    DatePicker("Resets", selection: $allowanceReset).datePickerStyle(.compact)
                    DatePicker("Observed", selection: $allowanceObserved, in: ...Date()).datePickerStyle(.compact)
                }
                Button("Save observation") {
                    if model.saveAllowance(accountID: account.id, percent: allowancePercent, resetsAt: allowanceReset, observedAt: allowanceObserved, label: allowanceLabel) { allowancePercent = ""; allowanceObserved = Date() }
                }.disabled(allowancePercent.isEmpty)
                Text("A percentage and a reset time only. CostBar never turns it into dollars and never infers it from token logs.").font(.caption).foregroundStyle(.secondary)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Log estimate
    @State private var budgetText = ""
    private var logSection: some View {
        GroupBox("Local log token estimate · not spend, not an allowance") {
            VStack(alignment: .leading, spacing: 6) {
                if let e = model.workspace.logEstimates[account.id] {
                    Text("ESTIMATE · input \(e.inputTokens.formatted()) · output \(e.outputTokens.formatted()) tokens\(e.isSample ? " · SAMPLE" : "")").font(.callout.weight(.medium))
                    Text("Method: " + (e.methods.isEmpty ? "n/a" : e.methods.compactMap { LogEstimator.methodNotes[$0] }.joined(separator: " "))).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("\(e.recordsCounted) records counted, \(e.linesSkipped) lines skipped · imported \(e.importedAt.formatted(date: .abbreviated, time: .shortened)) · only totals are stored").font(.caption).foregroundStyle(.secondary)
                    if let f = e.fractionOfBudget(account.tokenBudget) {
                        Text("\(Int(f * 100))% of your own token budget").font(.caption)
                        ProgressView(value: min(1, f))
                    }
                    Button("Clear estimate") { model.clearLogEstimate(account.id) }.font(.caption)
                }
                HStack {
                    Button("Import log file…") { importLog() }.accessibilityLabel("Import a local log file for a token estimate")
                    TextField("Your token budget", text: $budgetText).textFieldStyle(.roundedBorder).frame(width: 150)
                    Button("Save budget") { if model.saveTokenBudget(accountID: account.id, text: budgetText) { budgetText = "" } }
                    if let b = account.tokenBudget { Text("Budget: \(b.formatted())").font(.caption).foregroundStyle(.secondary) }
                }
                Text("Reads input/output token counts from JSON lines, up to \(LogEstimator.maxBytes / 1_048_576) MB. Prices, quotas and plan limits are not applied.").font(.caption).foregroundStyle(.secondary)
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func importLog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose a local .jsonl or .log file. CostBar keeps token totals only, not the file or its path."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = model.importLog(accountID: account.id, url: url)
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
