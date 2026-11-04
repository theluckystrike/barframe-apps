import SwiftUI
import QuotaPaceCore

struct PaceDetailsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let summary = model.summary(.fiveHours)
        VStack(alignment: .leading, spacing: 18) {
            Label("Pace details", systemImage: "speedometer").font(.title2.weight(.bold))
            Text(model.sampleMode ? "Sample data · \(model.selected.title)" : model.selected.title)
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT PACE").font(.caption).foregroundStyle(.secondary)
                Text("\(summary.tokensPerHour.formatted(.number.precision(.fractionLength(0)))) tokens / hour").font(.title3.weight(.semibold)).monospacedDigit()
            }
            Divider()
            detail("Observed activity", value: String(format: "%.1f hours", summary.elapsed / 3600))
            detail("Rolling five-hour usage", value: summary.used.formatted())
            detail("Your five-hour budget", value: summary.limit == 0 ? "Unset" : summary.limit.formatted())
            detail("Projected full-window usage", value: summary.projected.formatted(.number.precision(.fractionLength(0))))
            Divider()
            Text("ESTIMATED TIME TO LIMIT").font(.caption).foregroundStyle(.secondary)
            Text(forecast(summary)).font(.title.weight(.bold)).foregroundStyle(QuotaPaceBrand.accent)
            Text("Assumes the observed average pace continues. Past events are removed as they leave the five-hour window. Provider plan rules may differ.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 360).tint(QuotaPaceBrand.accent)
            .onExitCommand { NSApp.keyWindow?.close() }
    }
    private func detail(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
    }
    private func forecast(_ summary: WindowSummary) -> String {
        if summary.limit == 0 { return "Set a budget" }
        if summary.isOverLimit { return "Limit reached" }
        if summary.tokensPerHour == 0 { return "Need more activity" }
        guard let seconds = summary.secondsToLimit else { return "Within pace" }
        return seconds < 60 ? "Less than 1 minute" : "About \(Int(seconds / 60)) minutes"
    }
}

enum QuotaPaceBrand {
    static let accent = Color(red: 94.0 / 255, green: 92.0 / 255, blue: 230.0 / 255)
}
