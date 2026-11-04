import SwiftUI
import StarglassCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.loading { ProgressView().controlSize(.small) }
            if let message = model.errorMessage {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            if model.sampleMode {
                Text("Sample · synthetic forecast")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.searchResults.isEmpty { searchList }
            if let tonight = model.outlooks.first { tonightTimeline(tonight) }
            sevenNightList
            footer
        }
        .padding(18)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayLocation?.isEmpty == false ? model.displayLocation!.name : "No location chosen")
                    .font(.headline).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                Text(model.displayTimeZone.identifier).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let score = model.tonightScore {
                VStack(alignment: .trailing) {
                    Text("\(score)").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("/100 tonight").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("—").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if model.sampleMode { return "Sample data" }
        if model.stale { return "Stale forecast. Refresh needed" }
        if model.offline { return "Offline · cached forecast" }
        if let updated = model.lastUpdated {
            let formatter = DateFormatter()
            formatter.timeZone = model.displayTimeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Updated " + formatter.string(from: updated)
        }
        return "Not loaded yet"
    }

    private var searchList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search results").font(.caption.bold())
            ForEach(model.searchResults) { place in
                Button {
                    model.choose(place)
                } label: {
                    Text(place.summary).frame(maxWidth: 240, alignment: .leading)
                }.buttonStyle(.plain).font(.callout)
            }
        }
    }

    private func tonightTimeline(_ tonight: NightOutlook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tonight").font(.headline)
            Text("\(tonight.label) · clouds \(Int(tonight.averageCloud))% · moon \(Int(tonight.moonIllumination * 100))% lit" +
                 (tonight.hasAstronomicalDark ? " · \(Int(tonight.darkHours))h dark" : " · no full darkness at this latitude"))
                .font(.caption).foregroundStyle(.secondary)
            let hours = tonightTimelineHours(tonight)
            if hours.isEmpty {
                Text("Hourly forecast is unavailable for this night. Refresh to try again.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(hours, id: \.self.time) { hour in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cloudColor(hour))
                                .frame(width: 18, height: CGFloat(12 + (100 - cloudiness(hour)) / 6))
                            Text(hourLabel(hour.time))
                                .font(.system(size: 7)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
    }

    private var sevenNightList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next 7 nights").font(.headline)
            if model.outlooks.count <= 1 {
                Text("No nights available yet. Choose a location or check your connection.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                let best = NightScorer.bestNight(model.outlooks)
                ForEach(Array(model.outlooks.enumerated().dropFirst()), id: \.element.id) { index, night in
                    HStack {
                        Text(nightLabel(night, index: index)).frame(width: 110, alignment: .leading)
                        ProgressView(value: Double(night.score), total: 100).frame(width: 140)
                        Text("\(night.score)").frame(width: 28, alignment: .trailing)
                            .font(.callout.monospacedDigit())
                        Text(night.label).font(.caption).foregroundStyle(.secondary)
                        if best?.id == night.id { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                    }.font(.callout)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(model.sampleMode ? "Use live forecast" : "Try Sample") {
                if model.sampleMode { model.exitSample() } else { model.enterSample() }
            }
            Button("Refresh") { Task { await model.refresh() } }.disabled(model.loading || model.sampleMode)
            Spacer()
            PolicySupportLinks()
            Button("Settings") { openSettings() }
        }
    }

    // MARK: helpers

    func tonightTimelineHours(_ tonight: NightOutlook) -> [Forecast.Hour] {
        Array((model.activeForecast?.hours(between: tonight.nightStart, and: tonight.nightEnd) ?? []).prefix(16))
    }

    func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = model.displayTimeZone
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    func cloudiness(_ hour: Forecast.Hour) -> Double {
        let low = hour.cloudCoverLow ?? 50
        let mid = hour.cloudCoverMid ?? 50
        let high = hour.cloudCoverHigh ?? 50
        return 0.5 * low + 0.3 * mid + 0.2 * high
    }

    func cloudColor(_ hour: Forecast.Hour) -> Color {
        let c = cloudiness(hour)
        if c < 25 { return .cyan }
        if c < 55 { return .blue }
        return .gray
    }

    func nightLabel(_ night: NightOutlook, index: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = model.displayTimeZone
        formatter.dateFormat = index == 0 ? "Tonight" : "EEE d MMM"
        return formatter.string(from: night.nightStart)
    }

    func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

let hourFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH"
    return formatter
}()
