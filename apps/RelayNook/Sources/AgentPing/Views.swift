import SwiftUI
import AgentPingCore

extension EventKind {
    var symbol: String {
        switch self { case .waiting: return "hourglass"; case .done: return "checkmark.circle.fill"; case .error: return "exclamationmark.triangle.fill"; case .info: return "info.circle" }
    }
    var color: Color {
        switch self { case .waiting: return .orange; case .done: return .green; case .error: return .red; case .info: return .blue }
    }
}

struct PopoverView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.system(size: 26)).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("RelayNook").font(.title2.bold())
                    Text("Keep your agents in view.").foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Text("\(model.history.waitingCount)").font(.title.bold()).monospacedDigit()
                    .foregroundStyle(model.history.waitingCount == 0 ? Color.secondary : .orange)
            }
            HStack {
                Label("\(model.history.waitingCount) waiting", systemImage: "hourglass")
                Spacer()
                Text("\(model.history.events.count) / 200 events").foregroundStyle(.secondary)
            }.font(.callout)
            if model.history.unresolvedLegacyCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(model.history.unresolvedLegacyCount) unresolved legacy sessions").font(.callout)
                    Text("Agent identity is unavailable. Excluded from the waiting count.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Dismiss unresolved sessions") { model.dismissUnresolvedLegacySessions() }
                }
            }
            Divider()
            HStack {
                Text("EVENT HISTORY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.clear() }
                    .disabled(model.history.events.isEmpty && model.history.waitingCount == 0 && model.history.unresolvedLegacyCount == 0)
            }
            ScrollView { historyRows }.frame(height: 310)
            Text("Rejected: \(model.history.rejectedCount)").font(.caption).foregroundStyle(.secondary)
            if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.orange).lineLimit(3) }
            Toggle("Sample mode", isOn: Binding(get: { model.isSample }, set: model.setSampleMode))
            Button("Send test event") { model.sendTest() }
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Button("About") { AppLinks.showAbout() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }.padding(22).frame(width: 440)
    }
    private var historyRows: some View {
                VStack(alignment: .leading, spacing: 12) {
                    if model.history.events.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(.secondary)
                            Text("No events received").font(.headline)
                            Text("Open Settings → Setup. Copy a hook to connect an agent, or send a test event.")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 32).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.history.events.reversed()) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: event.kind.symbol).foregroundStyle(event.kind.color).frame(width: 20)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(event.agent).font(.headline)
                                    Text(event.kind.rawValue).font(.caption).foregroundStyle(event.kind.color)
                                    Spacer()
                                    Text(event.receivedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(event.title).lineLimit(3)
                                if !event.project.isEmpty { Text(event.project).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Text("Session: \(event.session)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SnippetBlock: View {
    @ObservedObject var model: AppModel
    let title: String
    let instructions: String
    let code: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Copy") { model.copy(code, name: title) }
            }
            Text(instructions).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView([.horizontal, .vertical]) { codeText }
                .frame(height: min(CGFloat(code.components(separatedBy: "\n").count) * 14 + 44, 150)).clipped()
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    private var codeText: some View {
        Text(code).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: true).padding(12)
    }
}
struct SetupView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView { setupContent }
    }
    private var setupContent: some View {
            VStack(alignment: .leading, spacing: 22) {
                Text("Connect an agent").font(.title2.bold())
                Text("Paste these snippets yourself. RelayNook receives events through its URL scheme.").foregroundStyle(.secondary)
                SnippetBlock(model: model, title: "No-install Terminal test", instructions: "No account or agent required. Run this command to test URL delivery. The test event button only tests local processing and notification settings.", code: model.terminalTest)
                Text("Optional integrations below require manual setup and a real-agent test.").font(.callout)
                SnippetBlock(model: model, title: "1. Install the hook script", instructions: "Run in Terminal. Use the system Perl JSON parser. Keep agent output out of shell code.", code: Snippets.installScript(token: model.token))
                SnippetBlock(model: model, title: "2. Claude Code", instructions: "Merge the hooks into ~/.claude/settings.json. Notification marks waiting. Stop marks done. Hooks report responses, not project completion.", code: Snippets.claudeJSON)
                SnippetBlock(model: model, title: "3. Codex CLI", instructions: "Add at the top level of ~/.codex/config.toml. Restart Codex. notify reports turn completion only; it does not report approval requests.", code: Snippets.codexTOML)
                SnippetBlock(model: model, title: "Generic shell function", instructions: "Paste into your shell configuration. Call with AGENT KIND TITLE PROJECT SESSION. Use waiting, done, error, or info.", code: Snippets.genericFunction(token: model.token))
                        HStack {
                            Link("Claude hook reference", destination: URL(string: "https://code.claude.com/docs/en/hooks")!)
                            Link("Codex notify reference", destination: URL(string: "https://learn.chatgpt.com/docs/config-file/config-advanced#notifications")!)
                        }

                Text(model.copied).font(.caption).foregroundStyle(.secondary)
            }.padding(24)
    }
}
struct SettingsView: View {
    @State var selectedTab = 0
    @ObservedObject var model: AppModel
    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Section("Notifications") {
                    ForEach(EventKind.allCases, id: \.self) { kind in
                        Toggle("Notify for \(kind.rawValue)", isOn: Binding(get: { model.preferences.permits(kind) }, set: { enabled in
                            if enabled { model.preferences.enabledKinds.insert(kind) } else { model.preferences.enabledKinds.remove(kind) }
                            model.savePreferences()
                        }))
                    }
                    Toggle("Play sound", isOn: Binding(get: { model.preferences.sound }, set: { model.preferences.sound = $0; model.savePreferences() }))
                    Text(model.notificationStatus).foregroundStyle(.secondary)
                    Button("Enable notifications…") { model.enableNotifications() }
                    Text("Focus and notification delivery follow system settings.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Event security") {
                    EventSecurityView(model: model)
                }
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLogin))
                    Button("Send test event") { model.sendTest() }
                    Text("Keep the last 200 events on this device.").foregroundStyle(.secondary)
                    Button("Privacy Policy") { AppLinks.showDocument(privacyPolicy: true) }
                    Button("Support") { AppLinks.showDocument(privacyPolicy: false) }
                    Button("About RelayNook") { AppLinks.showAbout() }
                }
                if !model.status.isEmpty { Text(model.status).foregroundStyle(.orange) }
            }.formStyle(.grouped).padding(16).tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            SetupView(model: model).tabItem { Label("Setup", systemImage: "terminal") }.tag(1)
        }.frame(width: 740, height: 720).onAppear { model.refreshNotificationStatus() }
    }
}

struct EventSecurityView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                    Text("Require the installation token for every event. Reject missing or incorrect tokens. Accept at most 30 events per minute. Coalesce duplicate notifications for 10 seconds.").foregroundStyle(.secondary)
                    Button("Copy Terminal test command") { model.copy(model.terminalTest, name: "Terminal test command") }
                    Button("Regenerate token") { model.regenerateToken() }
                    Text("Regeneration invalidates installed hooks. Copy and install the new snippets.").font(.caption).foregroundStyle(.secondary)
                    if !model.copied.isEmpty { Text(model.copied).foregroundStyle(.secondary) }
            Text("Rejected: \(model.history.rejectedCount)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
