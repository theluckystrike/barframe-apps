import AppKit
import SwiftUI
import RevPulseCore

/// Last-7-days sparkline drawn with Path (no SF Symbols needed).
struct Sparkline: View {
    let days: [Revenue.Day]
    var color: Color = .green

    var body: some View {
        GeometryReader { geo in
            let values = days.map { Double($0.netCents) }
            let minV = min(values.min() ?? 0, 0)
            let range = max((values.max() ?? 0) - minV, 1)
            let w = geo.size.width, h = geo.size.height
            let stepX = values.count > 1 ? w / CGFloat(values.count - 1) : w
            Path { p in
                for (i, v) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * stepX, y: h - (h * 0.85) * ((v - minV) / range))
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Last 7 days sparkline")
    }
}

public struct PopoverView: View {
    static let goalSymbolName = "target"
    @ObservedObject var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = model.errorText {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if let snap = model.snapshot {
                if let issue = snap.netIssue { Text(issue).font(.callout).foregroundStyle(.orange) }
                metrics(snap)
                Text("UTC · " + snap.currency.uppercased() + " · " + snap.fetchedAt.formatted(date: .omitted, time: .shortened).replacingOccurrences(of: ":", with: ".")).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No data yet. Add a Stripe restricted key in Settings, or explore Sample mode.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            PolicySupportLinks()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit RevPulse") { NSApp.terminate(nil) }
            }.font(.caption)

        }
        .padding(14)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var header: some View {
        HStack {
            Text(model.sampleMode ? "Sample data" : "Revenue").font(.headline)
            Spacer()
            Button(action: { Task { await model.refresh() } }) {
                if model.isLoading { ProgressView().controlSize(.small) } else { Text("Refresh") }
            }
            .disabled(model.isLoading)
            .accessibilityIdentifier("refreshButton")
        }
    }

    func metrics(_ snap: Revenue.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(money(snap.today.netCents, snap))
                    .font(.title2.bold()).monospacedDigit()
            }.accessibilityElement(children: .combine)
            HStack {
                Text("Yesterday").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(money(snap.yesterday.netCents, snap))
                    .font(.subheadline).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Last 7 days").font(.subheadline).foregroundStyle(.secondary)
                if snap.netComplete { Sparkline(days: snap.last7Days).frame(height: 44) } else { Text("Net unavailable").font(.caption) }
            }
            Divider()
            row("Month to date", money(snap.monthToDateNetCents, snap))
            row("New customers", "\(snap.newCustomersMTD)")
            row("New subscriptions", "\(snap.newSubscriptionsMTD)")
            row("Failed payments", "\(snap.failedPaymentsMTD)")
            row("Refunds", money(snap.refundsMTDCents, snap))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Goal", systemImage: Self.goalSymbolName).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(snap.netComplete ? Formatting.percent(snap.goalProgress) : "Unavailable") of \(Formatting.money(snap.goalCents, currency: snap.currency))")
                        .font(.subheadline).monospacedDigit()
                }
                ProgressView(value: snap.goalProgress)
                    .progressViewStyle(.linear)
                    .tint(.yellow)
                    .accessibilityIdentifier("goalProgress")
            }
        }
    }

    func money(_ units: Int, _ snap: Revenue.Snapshot) -> String {
        snap.netComplete ? Formatting.money(units, currency: snap.currency) : "Unavailable"
    }
    func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }
}
