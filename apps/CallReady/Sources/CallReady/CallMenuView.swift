import SwiftUI
import CallCore

private let accent = Color(red: 0.20, green: 0.24, blue: 0.55)
/// System link color: readable on light and dark cards.
private let linkColor = Color(nsColor: .linkColor)

/// Wraps instead of truncating inside the fixed-width menu window.
private extension View {
    func wraps() -> some View { fixedSize(horizontal: false, vertical: true) }
}
private let ready = Color(red: 0.16, green: 0.62, blue: 0.38)

/// The window under the menu bar item: one status line, then the three parts.
struct CallMenuView: View {
    @ObservedObject var app: CallCoordinator
    @ObservedObject var calendar: CalendarModel
    @ObservedObject var microphone: GuardModel
    @ObservedObject var mute: MuteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.status).font(.system(size: 15, weight: .semibold)).wraps()
                .accessibilityIdentifier("combinedStatus")
            if let note = app.preCallNote {
                HStack(alignment: .top) {
                    Image(systemName: "checklist").foregroundStyle(ready)
                    Text(note).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("OK") { app.dismissPreCallNote() }.buttonStyle(.plain).foregroundStyle(linkColor)
                }.padding(10).background(ready.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            if microphone.needsIntroduction {
                HStack(alignment: .top) {
                    Text("CallReady puts your wired or built-in mic back when a Bluetooth headset takes over the input, and mutes it with \(mute.hotKey.label) in any app. Allow calendar access to see your next call.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Got it") { microphone.dismissIntroduction() }
                }
            }
            NextCallCard(app: app, calendar: calendar, mute: mute)
            MicrophoneCard(microphone: microphone)
            MuteCard(mute: mute)
            Divider()
            HStack {
                Button("Settings…") { AppWindows.showSettings(app) }.keyboardShortcut(",")
                Button("About") { showAbout() }
                Spacer()
                Button("Quit CallReady") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.plain).font(.callout)
        }.padding(16).frame(width: 400)
    }
}

private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            content
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NextCallCard: View {
    @ObservedObject var app: CallCoordinator
    @ObservedObject var calendar: CalendarModel
    @ObservedObject var mute: MuteModel

    var body: some View {
        Card(title: "Next call", symbol: "calendar") {
            switch calendar.access {
            case .notDetermined:
                Text("CallReady reads today's and tomorrow's events to show the next call and its join link.").font(.callout).foregroundStyle(.secondary).wraps()
                Button("Allow calendar access") { calendar.requestAccess() }
            case .denied:
                Text("Calendar access is off. Turn it on in System Settings → Privacy & Security → Calendars.").font(.callout).foregroundStyle(.secondary).wraps()
                Button("Open System Settings") { NSWorkspace.shared.open(AppLinks.calendarPrivacySettings) }
            case .granted:
                granted
            }
            if !calendar.statusText.isEmpty { Text(calendar.statusText).font(.caption).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder private var granted: some View {
        TimelineBar(events: calendar.events, now: calendar.now)
        if let next = calendar.nextEvent {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.title).font(.headline).lineLimit(3).wraps()
                    Text("\(time(next.start)) · \(CallStatus.countdown(now: calendar.now, event: next))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                MuteBadge(muted: mute.muteState(), talking: mute.pttActive)
            }
            Label(app.readiness.isReady ? "Ready for this call" : app.readiness.text,
                  systemImage: app.readiness.isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.caption.bold()).foregroundStyle(app.readiness.isReady ? ready : Color.orange)
                .accessibilityIdentifier("readiness")
            if let link = JoinParser.firstJoinLink(in: next.searchText) {
                Button { app.join(link) } label: {
                    Label("Join \(JoinParser.service(for: link) ?? "call")", systemImage: "video.fill")
                }.buttonStyle(.borderedProminent).tint(accent).accessibilityIdentifier("joinButton")
            }
        } else {
            Text("No calls today or tomorrow.").font(.callout).foregroundStyle(.secondary)
        }
        let later = DayTimeline.upcoming(events: calendar.events, now: calendar.now, limit: 4).dropFirst()
        ForEach(Array(later), id: \.id) { event in
            HStack {
                Text(time(event.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                Text(event.title).font(.callout).lineLimit(2).wraps()
                Spacer()
                if JoinParser.firstJoinLink(in: event.searchText) != nil { Image(systemName: "video").foregroundStyle(.secondary) }
            }
        }
    }

    private func time(_ date: Date) -> String {
        let day = Calendar.current.isDateInToday(date) ? "" : "Tomorrow "
        return day + date.formatted(date: .omitted, time: .shortened)
    }
}

struct MuteBadge: View {
    let muted: Bool?
    let talking: Bool
    var body: some View {
        let text = CallStatus.mutePart(muted: muted, talking: talking) ?? "No mute control"
        let isMuted = muted == true && !talking
        Label(text, systemImage: isMuted ? "mic.slash.fill" : "mic.fill")
            .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(isMuted ? Color.red : ready)
            .background((isMuted ? Color.red : ready).opacity(0.12), in: Capsule())
            .accessibilityIdentifier("muteBadge")
    }
}

struct TimelineBar: View {
    let events: [MeetEvent]
    let now: Date
    var body: some View {
        let window = DayTimeline.dayWindow(for: now)
        let blocks = DayTimeline.blocks(events: events, dayStart: window.start, dayEnd: window.end)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    Capsule().fill(accent.opacity(0.75))
                        .frame(width: max(2, geo.size.width * block.width))
                        .offset(x: geo.size.width * block.start)
                }
                if let marker = DayTimeline.nowMarker(now: now, dayStart: window.start, dayEnd: window.end) {
                    Rectangle().fill(Color.primary).frame(width: 2).offset(x: geo.size.width * marker)
                }
            }
        }.frame(height: 8).accessibilityLabel("Today's busy periods and the current time")
    }
}

struct MicrophoneCard: View {
    @ObservedObject var microphone: GuardModel
    var body: some View {
        Card(title: "Microphone", symbol: "mic") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(microphone.currentInput?.name ?? "No input device").font(.headline).lineLimit(2).wraps()
                    Text(microphone.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Bluetooth guard", isOn: Binding(get: { microphone.settings.enabled }, set: microphone.setEnabled))
                    .toggleStyle(.switch).labelsHidden().accessibilityLabel("Put my preferred microphone back when Bluetooth takes over")
            }
            Text(microphone.preferred.map { "Preferred: \($0.name)" } ?? "Connect a wired or built-in microphone.").wraps()
                .font(.caption).foregroundStyle(.secondary)
            if microphone.recentIntervention, let moved = microphone.lastMovedName {
                Text("Input moved to \(moved)").font(.caption).foregroundStyle(ready)
            }
            if let note = microphone.availabilityNote { Text(note).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let error = microphone.error { Text(error).font(.caption).foregroundStyle(.red) }
            if microphone.bluetoothAllowed {
                HStack {
                    Text("Bluetooth mic allowed until \(microphone.settings.bluetoothAllowedUntil?.formatted(date: .omitted, time: .shortened) ?? "")").wraps()
                    Spacer()
                    Button("Resume") { microphone.resumeGuard() }.foregroundStyle(linkColor)
                }.buttonStyle(.plain).font(.caption)
            } else if microphone.devices.contains(where: { $0.transport.isBluetooth && $0.inputChannels > 0 }) {
                Button("Allow Bluetooth mic for 1 hour") { microphone.allowBluetoothForOneHour() }
                    .buttonStyle(.plain).foregroundStyle(linkColor).font(.caption)
            }
        }
    }
}

struct MuteCard: View {
    @ObservedObject var mute: MuteModel
    var body: some View {
        Card(title: "Mute", symbol: "mic.slash") {
            let device = mute.currentDefault()
            let muted = mute.muteState()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MenuLine.statusLine(deviceName: device?.name, muted: muted == true,
                                             volumePercent: mute.currentVolume().map { Int(($0 * 100).rounded()) }))
                        .font(.callout).lineLimit(3).wraps()
                    Text(mute.pushToTalk ? "Hold \(mute.hotKey.label) to talk" : "Press \(mute.hotKey.label) in any app")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(muted == true ? "Unmute" : "Mute") { mute.toggleDefaultMute() }
                    .disabled(device == nil).accessibilityIdentifier("muteButton")
            }
            if mute.currentDefault()?.supportsVolume == true, let volume = mute.currentVolume() {
                Slider(value: Binding(get: { Double(mute.currentVolume() ?? volume) }, set: { mute.setVolume(Float($0)) }), in: 0...1) {
                    Text("Input volume")
                }.font(.caption)
            }
            if !mute.lastOutcome.isEmpty { Text(mute.lastOutcome).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
