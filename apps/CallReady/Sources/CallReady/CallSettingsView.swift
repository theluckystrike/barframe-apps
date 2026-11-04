import SwiftUI
import ServiceManagement
import CallCore

/// One settings window with three sections: Next call, Microphone, Mute.
struct CallSettingsView: View {
    static let width: CGFloat = 520
    static let height: CGFloat = 720
    @ObservedObject var app: CallCoordinator
    @ObservedObject var calendar: CalendarModel
    @ObservedObject var microphone: GuardModel
    @ObservedObject var mute: MuteModel
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Text("CallReady lives in the menu bar as a microphone icon. On a full menu bar, macOS can hide it behind the camera housing. Open CallReady again from Finder or Launchpad to show this window.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Button("Show the menu") { AppWindows.showMenuWindow(app) }
                    .accessibilityIdentifier("showMenuWindow")
            }
            nextCallSection
            microphoneSection
            muteSection
            Section {
                Toggle("Open CallReady at login", isOn: Binding(get: { loginEnabled }, set: setLaunchAtLogin))
                    .accessibilityIdentifier("launchAtLogin")
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                Text("CallReady changes the default microphone and its mute state. It does not record or listen to audio.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    PolicySupportLinks()
                    Spacer()
                    Text("Version \(ProductInfo.version) (\(ProductInfo.build))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.width, height: Self.height)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in readLoginStatus() }
    }

    private var nextCallSection: some View {
        Section("Next call") {
            switch calendar.access {
            case .granted:
                Text("Calendar access: on. CallReady reads event titles, times, locations and notes for today and tomorrow. Events stay on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            case .denied:
                Text("Calendar access: off. Turn it on in System Settings → Privacy & Security → Calendars.").font(.caption).foregroundStyle(.orange)
                Button("Open System Settings") { NSWorkspace.shared.open(AppLinks.calendarPrivacySettings) }
            case .notDetermined:
                Button("Allow calendar access") { calendar.requestAccess() }
            }
            ForEach(calendar.calendars) { item in
                Toggle(item.title, isOn: Binding(get: { calendar.isCalendarSelected(item.id) }, set: { calendar.selectCalendar(item.id, enabled: $0) }))
            }
            Picker("Remind me before a call", selection: $calendar.reminderMinutes) {
                Text("Never").tag(0)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("15 minutes").tag(15)
            }
            .onChange(of: calendar.reminderMinutes) { calendar.requestNotifications() }
            .accessibilityIdentifier("reminderPicker")
            Toggle("Check the microphone one minute before the call", isOn: $app.checkMicBeforeCall)
            Text("If a Bluetooth mic has taken over the input, CallReady puts your preferred microphone back one minute before the call and when you select Join.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show meeting titles in notifications", isOn: $calendar.showTitlesInNotifications)
            Text("Off: notifications say only \"Call in 1 minute\", so a meeting title does not show on an unattended Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Menu bar shows", selection: $app.menuBarStyle) {
                ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
    }

    private var microphoneSection: some View {
        Section("Microphone") {
            Toggle("Put my preferred microphone back when Bluetooth takes over", isOn: Binding(get: { microphone.settings.enabled }, set: microphone.setEnabled))
            Picker("Preferred microphone", selection: Binding(get: { microphone.settings.preferredUID ?? "" }, set: microphone.setPreferred)) {
                Text("Automatic · built-in, then wired").tag("")
                if let uid = microphone.settings.preferredUID, !microphone.safeInputs.contains(where: { $0.uid == uid }) {
                    Text("Saved microphone unavailable · use fallback").tag(uid)
                }
                ForEach(microphone.safeInputs) { Text("\($0.name) · \($0.transport.rawValue)").tag($0.uid) }
            }
            Text(microphone.microphoneProtectionNote).font(.caption).foregroundStyle(.secondary)
            ForEach(microphone.selectableInputs) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name)
                        Text(device.transport.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if device.id == microphone.inputID {
                        Text("Default input").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Set as default input") { microphone.useInputNow(device.id) }
                            .accessibilityIdentifier("setDefaultInput")
                    }
                }
            }
            Text("Set any microphone as the default input by hand. A Bluetooth mic moves back to the preferred mic unless you allow Bluetooth for 1 hour in the menu.")
                .font(.caption).foregroundStyle(.secondary)
            if let note = microphone.manualNote { Text(note).font(.caption) }
            Picker("When the default microphone changes", selection: Binding(get: { mute.intent }, set: { mute.setIntent($0) })) {
                ForEach(ReapplyLogic.Intent.allCases, id: \.self) { Text(intentTitle($0)).tag($0) }
            }
            ForEach(microphone.settings.priorityUIDs, id: \.self) { uid in
                HStack {
                    Text(microphone.devices.first(where: { $0.uid == uid })?.name ?? "Saved microphone unavailable")
                    Spacer()
                    Button("Move up") { microphone.movePriority(uid) }.disabled(microphone.settings.priorityUIDs.first == uid)
                    Button("Remove") { microphone.setPriorities(microphone.settings.priorityUIDs.filter { $0 != uid }) }
                }
            }
            Menu("Add a backup microphone") {
                ForEach(microphone.safeInputs.filter { !microphone.settings.priorityUIDs.contains($0.uid) }) { device in
                    Button(device.name) { microphone.setPriorities(microphone.settings.priorityUIDs + [device.uid]) }
                }
            }
            DisclosureGroup("Recent switches · \(microphone.settings.history.count)") {
                ForEach(microphone.settings.history.reversed()) { item in
                    VStack(alignment: .leading) {
                        Text(item.target)
                        Text("\(item.date.formatted()) · \(item.reason)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Clear history") { microphone.clearHistory() }.disabled(microphone.settings.history.isEmpty)
            }
        }
    }

    private var muteSection: some View {
        Section("Mute") {
            Picker("Shortcut key", selection: Binding(get: { mute.hotKey.keyCode }, set: { code in
                var config = mute.hotKey; config.keyCode = code; mute.setHotKey(config)
            })) {
                ForEach(HotKeyConfig.selectableKeyCodes, id: \.self) { Text(HotKeyConfig.keyName($0)).tag($0) }
            }
            Toggle("Add Shift", isOn: Binding(get: { mute.hotKey.useShift }, set: { value in
                var config = mute.hotKey; config.useShift = value; mute.setHotKey(config)
            }))
            Toggle("Add Option", isOn: Binding(get: { mute.hotKey.useOption }, set: { value in
                var config = mute.hotKey; config.useOption = value; mute.setHotKey(config)
            }))
            if mute.shortcutAvailable {
                Text("Global shortcut \(mute.hotKey.label). It works in every app and needs no Accessibility permission.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Shortcut not available: macOS did not accept \(mute.hotKey.label). Choose a different key.")
                    .font(.caption).foregroundStyle(.red).accessibilityIdentifier("shortcutNotAvailable")
            }
            Toggle("Push-to-talk (hold the shortcut to unmute)", isOn: Binding(get: { mute.pushToTalk }, set: { mute.setPushToTalk($0) }))
            Toggle("Show a floating mute badge", isOn: Binding(get: { mute.showBadge }, set: { mute.setShowBadge($0) }))
            Picker("When a call starts", selection: $app.callStartMute) {
                ForEach(CallStartMute.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Remind me one minute before the call if I am muted", isOn: $app.remindUnmuteAtCall)
            if !mute.lastOutcome.isEmpty { Text(mute.lastOutcome).font(.caption).accessibilityIdentifier("operationStatus") }
            Button("Reset mute preferences") { mute.resetStoredData() }
        }
    }

    private func intentTitle(_ intent: ReapplyLogic.Intent) -> String {
        switch intent {
        case .alwaysMute: return "Always mute the new microphone"
        case .stayMutedOnly: return "Keep it muted if it was muted"
        case .off: return "Do nothing"
        }
    }

    private func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        readLoginStatus()
    }

    private func readLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        if status == .requiresApproval { loginError = "Allow CallReady in System Settings → General → Login Items." }
    }
}
