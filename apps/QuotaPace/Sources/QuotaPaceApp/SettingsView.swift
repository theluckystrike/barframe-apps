import SwiftUI
import MASKit
import AppKit
import QuotaPaceCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }.padding(18).frame(width: 480, height: 530)
            .onAppear { model.refreshLoginStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshLoginStatus() }
    }
    private var general: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Launch at Login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    .accessibilityLabel("Launch QuotaPace at login")
                if let error = model.loginError { Text(error).font(.caption).foregroundStyle(.red) }
                Toggle("Sample mode", isOn: Binding(get: { model.sampleMode }, set: { model.setSampleMode($0) }))
                    .accessibilityLabel("Use Sample token usage without a log folder")
                Text(model.sampleMode ? "Sample data · budgets are temporary and logs are not read." : "Try every usage view without an account or session files.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(model.sampleMode ? "Sample token limits" : "Your token limits").font(.headline)
                Text("Enter your own token budgets. Zero leaves a limit unset. These are estimates, not the provider’s official plan limits.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Provider.allCases) { provider in
                    LimitEditor(model: model, provider: provider)
                }
                Text("Refreshes every 30 seconds. Only JSONL logs are read; message text is never retained.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(4)
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("QuotaPace", systemImage: "speedometer").font(.title.weight(.bold))
            Text("Version 1.0.0 · © 2026 Michael Lip").font(.caption).foregroundStyle(.secondary)
            Text("A local pace forecaster for Claude Code and Codex session logs.")
            Text("Claude totals include input, output, cache creation and cache reads. Codex totals use cumulative token deltas; cached input is already included.")
            Text("Rolling windows cover the previous five hours and seven days. Forecasts use observed average consumption and account for events leaving the window. Provider billing, weights, resets and shared usage may differ.")
            Text("Privacy: folder bookmarks, limits and recent token counts stay in your app container. QuotaPace has no network access and sends nothing to the developer.")
            AppLinksView()
            Spacer()
        }.font(.callout).padding(12)
    }
}
private struct LimitEditor: View {
    @ObservedObject var model: AppModel
    let provider: Provider
    @State private var short = ""
    @State private var week = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.title).font(.headline)
                Spacer()
                if !model.sampleMode, model.grants[provider] != nil {
                    Button("Disconnect") { model.disconnect(provider) }.accessibilityLabel("Disconnect \(provider.title) folder")
                }
                if !model.sampleMode { Button(model.grants[provider] == nil ? "Connect folder…" : "Change folder…") { model.chooseFolder(for: provider) }
                    .accessibilityLabel("Choose \(provider.title) log folder") }
            }
            if let grant = model.grants[provider] { Text("Connected: \(grant.name)").font(.caption).foregroundStyle(.secondary) }
            HStack {
                VStack(alignment: .leading) {
                    Text("5-hour tokens").font(.caption)
                    TextField("Unset", text: $short).textFieldStyle(.roundedBorder).accessibilityLabel("\(provider.title) five hour token limit")
                }
                VStack(alignment: .leading) {
                    Text("7-day tokens").font(.caption)
                    TextField("Unset", text: $week).textFieldStyle(.roundedBorder).accessibilityLabel("\(provider.title) seven day token limit")
                }
                Button("Save") { save() }.accessibilityLabel("Save \(provider.title) token limits")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .onAppear { reload() }.onChange(of: model.limits[provider]) { reload() }
    }
    private func reload() {
        let limits = model.limits[provider] ?? Limits()
        short = limits.fiveHours == 0 ? "" : String(limits.fiveHours)
        week = limits.sevenDays == 0 ? "" : String(limits.sevenDays)
    }
    private func save() {
        do {
            let limits = try Limits.entered(fiveHours: short, sevenDays: week)
            model.saveLimits(limits, for: provider)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
