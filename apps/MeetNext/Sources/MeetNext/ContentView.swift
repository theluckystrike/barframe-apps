import SwiftUI
import MeetNextCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    private var now: Date { model.now }
    @State private var sampleJoin: URL?
    @State private var showSampleJoin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.accessDenied && !model.sampleMode {
                deniedView
            } else {
                timelineBar
                nextCard
                upcomingList
            }
            if !model.authorized && !model.accessDenied && !model.sampleMode {
                Button("Allow calendar access") { model.requestAccess() }
            }
            if !model.statusText.isEmpty { Text(model.statusText).font(.caption) }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
        .alert("Sample meeting link", isPresented: $showSampleJoin) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Sample preview: \(sampleJoin?.absoluteString ?? ""). Real events open their meeting link in your browser or meeting app.")
        }
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Calendar access needed", systemImage: "calendar.badge.exclamationmark")
                .font(.headline)
            Text("MeetNext shows your next meetings in the menu bar. Grant access to your calendars in System Settings, or explore the app with sample events.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(url) }
                }
                Button("Try Sample") { model.toggleSample(true) }
            }
            if model.sampleMode { timelineBar }
        }
    }

    private var timelineBar: some View {
        let window = SampleCalendar.dayWindow(for: now)
        let blocks = DayTimeline.blocks(events: model.events, dayStart: window.start, dayEnd: window.end)
        return VStack(alignment: .leading, spacing: 4) {
            Text(model.sampleMode ? "Today · Sample" : "Today").font(.headline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * block.width)
                            .offset(x: geo.size.width * block.start)
                    }
                    if let marker = DayTimeline.nowMarker(now: now, dayStart: window.start, dayEnd: window.end) {
                        Rectangle().fill(Color.primary).frame(width: 2)
                            .offset(x: geo.size.width * marker)
                    }
                }
            }
            .frame(height: 12)
            .accessibilityIdentifier("timelineBar")
            .accessibilityLabel("Today’s busy periods and current time")
            HStack { Text(format(window.start)); Spacer(); Text("End of day") }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var nextCard: some View {
        Group {
            if let next = model.nextEvent {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.title).font(.headline).lineLimit(2)
                    Text(format(next.start)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(Countdown.menuBarText(now: now, next: next)).font(.caption.bold())
                        Spacer()
                        if let join = JoinParser.firstJoinLink(in: next.searchText) {
                            Button {
                                if model.sampleMode { sampleJoin = join; showSampleJoin = true }
                                else { NSWorkspace.shared.open(join) }
                            } label: {
                                Label("Join \(JoinParser.service(for: join) ?? "meeting")", systemImage: "video.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("joinButton")
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            } else {
                Text(model.sampleMode ? "No upcoming sample events." : "No upcoming events today.").foregroundStyle(.secondary)
            }
        }
    }

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next 5").font(.subheadline.bold())
            ForEach(DayTimeline.upcoming(events: model.events, now: now, limit: 5), id: \.id) { event in
                HStack {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    VStack(alignment: .leading) {
                        Text(event.title).font(.callout).lineLimit(1)
                        Text(format(event.start)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if JoinParser.firstJoinLink(in: event.searchText) != nil {
                        Image(systemName: "video").foregroundStyle(.secondary)
                    }
                }
            }
            if model.events.isEmpty {
                Text("No events in the next two days.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if model.sampleMode {
                    Button("Use my calendar") { model.toggleSample(false) }
                } else {
                    Button("Try Sample") { model.toggleSample(true) }
                }
                Spacer()
                SettingsLink { Text("Settings") }
            }
            PolicySupportLinks()
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened).replacingOccurrences(of: ":", with: ".")
    }
}
