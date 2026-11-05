import SwiftUI
import ServiceManagement
import FidelityCore

struct GuardPopover: View {
    @ObservedObject var model: GuardModel
    @State var showDevices = false
    @State private var showSample = false
    @Environment(\.dismiss) private var dismiss
    var screenshot = false
    var sampleSession = false
    @State private var sampleSettings = false
    @Environment(\.openSettings) private var openSettings
    private let teal = Color(red: 0.10, green: 0.68, blue: 0.61)
    private func name(_ name: String) -> String { screenshot ? ScreenshotPrivacy.deviceName(name) : name }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 25, weight: .semibold)).foregroundStyle(teal)
                    .frame(width: 42, height: 42).background(teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("MicAnchor").font(.system(size: 20, weight: .semibold))
                    Text("Keep your preferred system microphone").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Circle().fill(model.settings.enabled && !model.bluetoothAllowed && !model.loopPaused && model.error == nil && model.preferred != nil ? teal : .orange).frame(width: 8, height: 8)
                Text(model.status).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Guard", isOn: Binding(get: { model.settings.enabled }, set: model.setEnabled))
                    .toggleStyle(GuardToggleStyle()).labelsHidden().accessibilityLabel("Guard")
            }.padding(10).background(teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 10) {
                deviceRow("OUTPUT", symbol: model.currentOutput?.transport.isBluetooth == true ? "headphones" : "speaker.wave.2", device: model.currentOutput)
                Divider()
                deviceRow("INPUT", symbol: "mic", device: model.currentInput)
            }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text("Preferred microphone").font(.system(size: 13, weight: .semibold))
                PreferredInputPicker(model: model, screenshot: screenshot)
                Text(model.preferred.map { "Guard target: \(name($0.name))" } ?? "No wired microphone available.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Text(model.microphoneProtectionNote)
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if model.recentIntervention, let moved = model.lastMovedName {
                HStack {
                    Text("Input moved to \(name(moved))").lineLimit(2)
                    Spacer()
                }.font(.system(size: 13))
            }
            HStack {
                if model.bluetoothAllowed {
                    Text("Allowed until \(model.settings.bluetoothAllowedUntil!.formatted(date: .omitted, time: .shortened))").font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Resume Guard") { model.resumeGuard() }
                } else {
                    Button("Allow Bluetooth mic for 1 hour") { model.allowBluetoothForOneHour() }
                }
            }.font(.system(size: 13)).buttonStyle(.plain).foregroundStyle(teal)
            HStack {
                Text("\(model.settings.interventions) interventions").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(model.settings.lastIntervention.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "None yet")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if let note = model.availabilityNote { Text(note).font(.system(size: 13)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let error = model.error { Text(error).font(.system(size: 13)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            DisclosureGroup("Audio devices · \(model.devices.count)", isExpanded: $showDevices) {
                if model.devices.isEmpty { Text("No audio devices found.").font(.caption) }
                if screenshot {
                    deviceList.frame(height: 72, alignment: .top).clipped()
                } else {
                    ScrollView { deviceList }.frame(maxHeight: 120)
                }
            }.font(.system(size: 13))
            if model.needsIntroduction && !screenshot {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Guard is on. It moves Bluetooth input to a wired mic.")
                        Button("Start MicAnchor at login…") { NSApp.activate(ignoringOtherApps: true); openSettings() }
                        Text("Enable Launch at login in Settings to run after a restart.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Got it") { model.dismissIntroduction() }
                }.font(.system(size: 13))
            }
            Divider()
            HStack {
                Button("Settings…") { if sampleSession { sampleSettings = true } else { NSApp.activate(ignoringOtherApps: true); openSettings() } }.keyboardShortcut(",")
                Button("About") { showAbout() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }.font(.system(size: 13)).buttonStyle(.plain)
            HStack {
                Button("Retry / Refresh") { model.refresh(enforce: true) }.accessibilityHint("Read current devices and retry guard protection")
                if !sampleSession { Button("Sample mode") { showSample = true } }
            }
        }.padding(18).frame(width: 440)
            .onExitCommand { dismiss() }
            .sheet(isPresented: $showSample) { SampleSessionView() }
            .sheet(isPresented: $sampleSettings) { GuardSettingsView(model: model, sampleSession: true) }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: screenshot ? 7 : 9) {
            ForEach(model.devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name(device.name)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if !screenshot {
                            Text(device.inputChannels > 0 ? "Microphone\(device.outputChannels > 0 ? " and output" : "")\(device.isAlive ? "" : " · unavailable")" : "Output")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(device.transport.rawValue).font(.system(size: 13)).foregroundStyle(device.transport.isBluetooth ? teal : .secondary)
                }
            }
        }.padding(.top, 6)
    }

    private func deviceRow(_ label: String, symbol: String, device: AudioDevice?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Text(device.map { name($0.name) } ?? "No default device").font(.system(size: 14, weight: .medium)).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let device { Text(device.transport.rawValue).font(.system(size: 13)).foregroundStyle(device.transport.isBluetooth ? teal : .secondary) }
        }
    }
}

struct GuardToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Color(red: 0.10, green: 0.68, blue: 0.61) : Color.secondary.opacity(0.4))
                Circle().fill(.white).padding(3).frame(width: 25, height: 25)
            }.frame(width: 44, height: 25)
        }.buttonStyle(.plain).accessibilityAddTraits(.isToggle)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct PreferredInputPicker: View {
    @ObservedObject var model: GuardModel
    var screenshot = false
    @State private var expanded = false
    private func name(_ device: AudioDevice) -> String {
        "\(screenshot ? ScreenshotPrivacy.deviceName(device.name) : device.name) · \(device.transport.rawValue)"
    }
    private var selection: String {
        guard let uid = model.settings.preferredUID else { return "Automatic · built-in, then wired" }
        return model.safeInputs.first(where: { $0.uid == uid }).map(name) ?? "Saved input unavailable · use fallback"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(selection).font(.system(size: 13)); Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .semibold))
                }.padding(9).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).accessibilityLabel("Preferred microphone: \(selection)")
            if expanded {
                choice("Automatic · built-in, then wired", uid: "")
                ForEach(model.safeInputs) { device in choice(name(device), uid: device.uid) }
            }
        }
    }
    private func choice(_ label: String, uid: String) -> some View {
        Button { model.setPreferred(uid); expanded = false } label: {
            HStack {
                Image(systemName: (model.settings.preferredUID ?? "") == uid ? "checkmark.circle.fill" : "circle")
                Text(label); Spacer()
            }.font(.system(size: 13)).padding(.vertical, 5)
        }.buttonStyle(.plain)
    }
}

@MainActor func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "MicAnchor", .applicationVersion: "1.0.0",
        .credits: AppLinks.credits(AppLinks.copyright)
    ])
}

struct GuardSettingsView: View {
    static let width: CGFloat = 480
    static let height: CGFloat = 680
    @ObservedObject var model: GuardModel
    var sampleSession = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?
    var body: some View {
        Form {
            Toggle("Guard", isOn: Binding(get: { model.settings.enabled }, set: model.setEnabled))
            Picker("Preferred microphone", selection: Binding(get: { model.settings.preferredUID ?? "" }, set: model.setPreferred)) {
                Text("Automatic · built-in, then wired").tag("")
                if let uid = model.settings.preferredUID, !model.safeInputs.contains(where: { $0.uid == uid }) { Text("Saved input unavailable · use fallback").tag(uid) }
                ForEach(model.safeInputs) { Text("\($0.name) · \($0.transport.rawValue)").tag($0.uid) }
            }
            if !sampleSession {
                Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: setLaunchAtLogin))
                Text("Turn this on to protect calls after a restart.").font(.caption).foregroundStyle(.secondary)
            }
            if let loginError { Text(loginError).foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true) }
            Section("Microphone priority order") {
                ForEach(model.settings.priorityUIDs, id: \.self) { uid in
                    HStack {
                        Text(model.devices.first(where: { $0.uid == uid })?.name ?? "Saved microphone unavailable")
                        Spacer()
                        Button("Move up") { model.movePriority(uid) }.disabled(model.settings.priorityUIDs.first == uid)
                        Button("Remove") { model.setPriorities(model.settings.priorityUIDs.filter { $0 != uid }) }
                    }
                }
                Menu("Add preferred microphone") {
                    ForEach(model.safeInputs.filter { !model.settings.priorityUIDs.contains($0.uid) }) { device in
                        Button(device.name) { model.setPriorities(model.settings.priorityUIDs + [device.uid]) }
                    }
                }
            }
            Section("Recent confirmed switches") {
                ForEach(model.settings.history.reversed()) { item in
                    VStack(alignment: .leading) {
                        Text(item.target)
                        Text("\(item.date.formatted()) · \(item.reason)").foregroundStyle(.secondary)
                    }
                }
                Button("Clear history") { model.clearHistory() }.disabled(model.settings.history.isEmpty)
            }
            if !sampleSession { Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() } }
            Text("MicAnchor changes the default microphone. It does not record audio.").font(.caption).foregroundStyle(.secondary)
            PolicySupportLinks()
            HStack { Text("Version 1.0.0").foregroundStyle(.secondary); Spacer(); Button("About MicAnchor") { showAbout() } }
        }.formStyle(.grouped).padding(12).frame(width: Self.width, height: Self.height)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in readLoginStatus() }
    }
    private func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil; readLoginStatus()
        } catch { loginError = error.localizedDescription; readLoginStatus() }
    }
    private func readLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        if status == .requiresApproval { loginError = "Allow launch at login in System Settings → General → Login Items." }
        else if status == .enabled { loginError = nil }
    }
}
