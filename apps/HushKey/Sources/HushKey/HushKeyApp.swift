import SwiftUI
import Combine
import CoreAudio
import HushKeyCore
import MASKit

enum ProductInfo {
    static let name = "HushKey"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    static let source = "https://barframe.com/apps/hushkey/"
}

@main
struct HushKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { SettingsView(model: delegate.model) }
            .commands { CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.openSettings() }.keyboardShortcut(",", modifiers: .command)
            } }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var model = AppModel()
    var lastObservedSample: Bool?
    var subscription: AnyCancellable?
    var settingsWindow: NSWindow?
    var controlsWindow: NSWindow?
    var observedProperties: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []


    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--smoke") { exit(SelfTest.run(writeSmoke: true)) }
        if args.contains("--selftest") { exit(SelfTest.run(writeSmoke: false)) }
        if args.contains("--screenshots") {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) }
            catch { fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let index = args.firstIndex(of: "--render-screenshots"), index + 1 < args.count {
            do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: args[index + 1])); exit(0) }
            catch { fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }

        model.badgePanel = MicBadgePanel()
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.lastObservedSample != self.model.sampleMode {
                    self.lastObservedSample = self.model.sampleMode
                    self.installDeviceStateListeners()
                }
                self.rebuildMenu()
            }
        }
        model.registerPushToTalkRelease()
        let config = HotKeyConfig.decode(UserDefaults.standard.string(forKey: "hotKey") ?? "") ?? .default
        model.applyHotKey(config)

        model.start()
        rebuildMenu()
        installDefaultDeviceListener()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        HotKeyCenter.shared.unregister()
        for (id, var address, block) in observedProperties {
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
    }

    func rebuildMenu() {
        let item = statusItem ?? {
            let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = s
            return s
        }()
        let devices = model.devices()
        let defaultDevice = model.currentDefault()
        let muted = model.isDefaultMuted()
        let volume = model.currentVolume()
        item.button?.title = model.sampleMode
            ? MenuLine.label(muted: muted, volumePercent: volume.map { Int(($0 * 100).rounded()) }, hideVolume: model.hideVolume) + "  Sample"
            : MenuLine.label(
                muted: muted,
                volumePercent: volume.map { Int(($0 * 100).rounded()) },
                hideVolume: model.hideVolume)
        if let button = item.button {
            button.attributedTitle = NSAttributedString(string: (muted ? "● " : "") + button.title, attributes: [.foregroundColor: muted ? NSColor.systemRed : NSColor.labelColor])
        }
        item.button?.isEnabled = true

        let menu = NSMenu()
        let deviceName = defaultDevice?.name
        menu.addItem(withTitle: MenuLine.statusLine(deviceName: deviceName, muted: muted, volumePercent: volume.map { Int(($0 * 100).rounded()) }),
                     action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        if let defaultDevice {
            let isMutedNow = muted
            menu.addItem(withTitle: isMutedNow ? "Unmute Microphone" : "Mute Microphone",
                         action: #selector(toggleMute), keyEquivalent: "m").target = self
            if defaultDevice.supportsVolume {
                menu.addItem(withTitle: "Set Input Volume…", action: #selector(askVolume), keyEquivalent: "").target = self
            }
            menu.addItem(.separator())
            if devices.count > 1 {
                for d in devices where !d.isDefault {
                    let mi = menu.addItem(withTitle: "Switch to \(d.name)", action: #selector(switchDevice(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.representedObject = d.id
                }
                menu.addItem(.separator())
            }
        } else {
            menu.addItem(withTitle: MenuLine.noDevice + "  (no input devices found)", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
        }

        if !model.lastOutcome.isEmpty { menu.addItem(withTitle: model.lastOutcome, action: nil, keyEquivalent: "") }
        menu.addItem(withTitle: "Microphone Controls…", action: #selector(openControls), keyEquivalent: "").target = self
        let sampleItem = menu.addItem(withTitle: model.sampleMode ? "Sample Mode ✓ (simulated devices)" : "Sample Mode",
                                      action: #selector(toggleSample), keyEquivalent: "")
        sampleItem.target = self
        let hotLabel = (HotKeyConfig.decode(UserDefaults.standard.string(forKey: "hotKey") ?? "") ?? .default).label
        menu.addItem(withTitle: "Mute Shortcut: \(hotLabel)", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Run Self Test", action: #selector(runSelfTest), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Privacy Policy", action: #selector(openPrivacy), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Support", action: #selector(openSupport), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(ProductInfo.name)", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
    }

    @objc func toggleMute() {
        model.toggleDefaultMute()
        rebuildMenu()
    }

    @objc func toggleSample() {
        model.setSampleMode(!model.sampleMode)
        installDeviceStateListeners()
        rebuildMenu()
    }

    @objc func askVolume() {
        guard model.currentDefault() != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Input volume"
        alert.informativeText = "0–100"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        if let v = model.currentVolume() { input.stringValue = "\(Int((v * 100).rounded()))" }
        alert.accessoryView = input
        if alert.runModal() == .alertFirstButtonReturn, let pct = Double(input.stringValue), (0...100).contains(pct) {
            model.setVolume(Float32(pct / 100))
        }
        rebuildMenu()
    }

    @objc func switchDevice(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String else { return }
        model.selectDefaultDevice(idString)
        rebuildMenu()
    }

    @objc func openSettings() {
        if settingsWindow == nil { settingsWindow = makeWindow(title: "HushKey Settings", view: SettingsView(model: model)) }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openControls() {
        if controlsWindow == nil { controlsWindow = makeWindow(title: "HushKey Microphone Controls", view: ControlsView(model: model)) }
        NSApp.activate(ignoringOtherApps: true)
        controlsWindow?.makeKeyAndOrderFront(nil)
    }

    func makeWindow<V: View>(title: String, view: V) -> NSWindow {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title; window.contentView = host; window.isReleasedWhenClosed = false; window.center()
        return window
    }

    @objc func runSelfTest() { _ = model.runSelfTestChecks(); rebuildMenu() }

    @objc func openPrivacy() { if let u = AppLinks.privacyURL { NSWorkspace.shared.open(u) } }
    @objc func openSupport() { if let u = AppLinks.supportURL { NSWorkspace.shared.open(u) } }
    @objc func quit() { NSApp.terminate(nil) }

    func installDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            guard let self, !self.model.sampleMode else { return }
            self.model.defaultDeviceChanged()
            self.installDeviceStateListeners()
            self.rebuildMenu()
        }
        installDeviceStateListeners()
    }

    func installDeviceStateListeners() {
        for (id, var address, block) in observedProperties {
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        observedProperties.removeAll()
        guard !model.sampleMode, let id = AudioDevices.defaultInputID() else { return }
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, !self.model.sampleMode else { return }
                self.model.refresh()
            }
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr { observedProperties.append((id, address, block)) }
        }
    }
}

extension AudioObjectID {
    init(idString: String) {
        self = UInt32(idString) ?? 0
    }
}
