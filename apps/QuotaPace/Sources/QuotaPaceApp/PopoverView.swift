import SwiftUI
import MASKit
import QuotaPaceCore

struct PopoverView: View {
    @ObservedObject var model: AppModel
    private var connected: Bool { model.grants[model.selected] != nil || model.sampleMode }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "speedometer").font(.system(size: 24)).foregroundStyle(.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("QuotaPace").font(.headline)
                    Text(model.sampleMode ? "Sample data · local estimate" : "Local token pace estimate")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.errors[model.selected] != nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityLabel("Log access needs attention")
                }
            }
            HStack(spacing: 4) {
                ForEach(Provider.allCases) { provider in
                    Button { model.selected = provider } label: {
                        Text(provider.title).font(.callout.weight(model.selected == provider ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(model.selected == provider ? Color.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(PopoverButtonStyle())
                        .accessibilityLabel("Show \(provider.title) usage")
                        .accessibilityValue(model.selected == provider ? "Selected" : "Not selected")
                }
            }.padding(3).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            if connected {
                windowCard(.fiveHours, prominent: true)
                windowCard(.sevenDays, prominent: false)
                let summary = model.summary(.fiveHours)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CURRENT PACE").font(.caption2).foregroundStyle(.secondary)
                        Text(summary.tokensPerHour > 0 ? "\(compact(summary.tokensPerHour)) / hour" : "Gathering pace")
                            .font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("TIME TO 5H LIMIT").font(.caption2).foregroundStyle(.secondary)
                        Text(forecast(summary)).font(.callout.weight(.semibold))
                    }
                }
                Text("Uses the average since the first event in this window. Old events expire; plan rules may differ.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Pace details…") { model.showPaceDetails() }.accessibilityLabel("Show pace forecast calculation")
                Divider()
                if let error = model.errors[model.selected] {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
                    Button("Reconnect logs") { model.chooseFolder(for: model.selected) }.accessibilityLabel("Reconnect session log folder")
                } else if let warning = model.warnings[model.selected] {
                    Text(warning).font(.caption).foregroundStyle(.orange).lineLimit(3)
                    Button("Choose another folder") { model.chooseFolder(for: model.selected) }.accessibilityLabel("Choose another session log folder")
                } else if let cache = model.caches[model.selected], cache.samples.isEmpty {
                    Text("No usage events were found in the last seven days.").font(.caption).foregroundStyle(.secondary)
                    Button("Choose log folder") { model.chooseFolder(for: model.selected) }.accessibilityLabel("Choose session log folder")
                } else {
                    HStack {
                        if let cache = model.caches[model.selected] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(cache.files) log \(cache.files == 1 ? "file" : "files") · read only")
                                Text("Updated \(cache.scannedAt.formatted(date: .omitted, time: .shortened))")
                            }.font(.caption).foregroundStyle(.secondary)
                        } else { Text("Reading session logs…").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(PopoverButtonStyle()).disabled(model.isRefreshing).accessibilityLabel("Refresh token usage")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("See your pace before you reach your limit.").font(.title3.weight(.semibold))
                    Text("Choose your \(model.selected.title) session log folder to calculate rolling token usage.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("~/\(model.selected.folderHint)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Connect \(model.selected.title) logs") { model.chooseFolder(for: model.selected) }
                        .buttonStyle(PopoverButtonStyle(prominent: true)).accessibilityLabel("Connect \(model.selected.title) session log folder")
                    if let error = model.errors[model.selected] { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(.vertical, 12)
            }
            Button(model.sampleMode ? "Exit Sample mode" : "Try Sample mode") { model.setSampleMode(!model.sampleMode) }
                .font(.callout).accessibilityLabel(model.sampleMode ? "Exit Sample mode" : "Try Sample mode without an account")
            Divider()
            HStack {
                Button("Settings…") { model.showSettings() }.keyboardShortcut(",", modifiers: .command).accessibilityLabel("Open QuotaPace settings")
                Spacer()
                AppPolicyButton(page: .privacy)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command).accessibilityLabel("Quit QuotaPace")
            }.buttonStyle(PopoverButtonStyle()).font(.callout)
        }
        .buttonStyle(PopoverButtonStyle())
        .padding(18).frame(width: 360).tint(QuotaPaceBrand.accent)
        .onExitCommand { NSApp.keyWindow?.close() }
    }
    @ViewBuilder private func windowCard(_ window: UsageWindow, prominent: Bool) -> some View {
        let summary = model.summary(window)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(window.title).font(.callout.weight(.medium))
                Spacer()
                if let fraction = summary.fraction {
                    Text(percent(fraction))
                        .font(prominent ? .title.weight(.bold) : .headline)
                        .foregroundStyle(summary.isOverLimit ? Color.orange : Color.primary).monospacedDigit()
                } else { Text("Set a limit").font(.caption).foregroundStyle(.secondary) }
            }
            if let fraction = summary.fraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(summary.isOverLimit ? Color.orange : Color.accentColor)
                            .frame(width: geometry.size.width * max(0, min(1, fraction)))
                    }
                }.frame(height: 5).accessibilityElement()
                    .accessibilityLabel("\(window.title) token usage").accessibilityValue("\(Int(min(999, fraction * 100))) percent")
            }
            HStack(alignment: .firstTextBaseline) {
                Text(summary.used.formatted()).font(prominent ? .title2.weight(.semibold) : .callout.weight(.semibold)).monospacedDigit()
                Text(summary.limit > 0 ? "of \(summary.limit.formatted()) tokens" : "tokens logged").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }.padding(12).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
    private func percent(_ fraction: Double) -> String {
        let percent = (fraction * 100).rounded()
        return percent > 999 ? ">999%" : "\(Int(percent))%"
    }
    private func compact(_ number: Double) -> String {
        if number >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if number >= 1000 { return String(format: "%.1fk", number / 1000) }
        return String(format: "%.0f", number)
    }
    private func forecast(_ summary: WindowSummary) -> String {
        if summary.limit == 0 { return "Set a limit" }
        if summary.isOverLimit { return "Limit reached" }
        if summary.tokensPerHour == 0 { return "Need more activity" }
        guard let seconds = summary.secondsToLimit else { return "Within pace" }
        if seconds < 60 { return "Less than 1 min" }
        if seconds < 3600 { return "~\(Int(seconds / 60)) min" }
        return String(format: "~%.1f hours", seconds / 3600)
    }
}

struct PopoverButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .padding(.horizontal, prominent ? 12 : 0)
            .padding(.vertical, prominent ? 8 : 2)
            .background(prominent ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(Rectangle())
    }
}
