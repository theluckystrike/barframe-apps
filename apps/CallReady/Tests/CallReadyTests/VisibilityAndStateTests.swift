import AppKit
import Foundation
import Testing
@testable import CallReady
import CallCore

/// Round 4: the app is never invisible, one copy owns the shortcut, and the mute text never contradicts the state.
@Suite(.serialized) @MainActor struct VisibilityAndStateTests {
    @Test func secondCopyYieldsToTheFirst() {
        let early = Date(timeIntervalSince1970: 100), late = Date(timeIntervalSince1970: 200)
        let first = SingleInstance.Copy(pid: 500, launched: early)
        let second = SingleInstance.Copy(pid: 400, launched: late)
        #expect(SingleInstance.shouldYield(me: second, others: [first, second]))
        #expect(!SingleInstance.shouldYield(me: first, others: [first, second]))
        #expect(!SingleInstance.shouldYield(me: first, others: [first]))
        let tieLow = SingleInstance.Copy(pid: 10, launched: early), tieHigh = SingleInstance.Copy(pid: 11, launched: early)
        #expect(SingleInstance.shouldYield(me: tieHigh, others: [tieLow]))
        #expect(!SingleInstance.shouldYield(me: tieLow, others: [tieHigh]))
        #expect(SingleInstance.shouldYield(me: SingleInstance.Copy(pid: 9, launched: nil), others: [SingleInstance.Copy(pid: 3, launched: nil)]))
    }

    /// Regression for L2's report: "Open at 29%" next to "Muted". Another owner of the mute state
    /// (here a second model on the same device) changes it; this model's text must follow the live state.
    @Test func muteTextNeverContradictsLiveStateAfterAnExternalChange() {
        let shared = FixtureDevices()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        func model() -> MuteModel {
            let m = MuteModel(storeDirectory: dir.appendingPathComponent(UUID().uuidString), backend: shared,
                              defaults: UserDefaults(suiteName: UUID().uuidString)!)
            m.registerShortcut = { _, _ in true }
            m.start(); return m
        }
        let mine = model(), other = model()
        _ = shared.setMute(shared.devices()[0], false)
        mine.toggleDefaultMute()
        #expect(mine.muteState() == true)
        #expect(mine.lastOutcome.isEmpty)
        for _ in 0..<6 {
            other.toggleDefaultMute()
            mine.refresh()
            let live = mine.muteState() == true
            let line = MenuLine.statusLine(deviceName: "Mic", muted: live, volumePercent: 29)
            #expect(live ? line.hasSuffix("Muted") : line.hasSuffix("Open at 29%"))
            #expect(!mine.lastOutcome.contains("Muted") && !mine.lastOutcome.contains("Microphone on"))
        }
    }

    @Test func pushToTalkLeavesNoHeldStateAfterRelease() {
        let backend = FixtureDevices()
        let m = MuteModel(storeDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                          backend: backend, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        m.registerShortcut = { _, _ in true }
        m.start(); m.setPushToTalk(true)
        var changes: [Bool] = []
        m.onPushToTalkChange = { changes.append($0) }
        for _ in 0..<5 { m.beginPushToTalk(); m.endPushToTalk() }
        #expect(changes == [true, false, true, false, true, false, true, false, true, false])
        #expect(!m.pttActive && m.muteState() == true)
    }

    @Test func rejectedShortcutShowsNotAvailable() throws {
        let f = FixtureApp(); defer { f.close() }
        f.mute.registerShortcut = { _, _ in false }
        f.mute.applyHotKey(.default)
        #expect(!f.mute.shortcutAvailable)
        #expect(f.mute.lastOutcome.contains("Shortcut not available"))
        f.mute.registerShortcut = { _, _ in true }
        f.mute.applyHotKey(.default)
        #expect(f.mute.shortcutAvailable)
    }

    @Test func settingsAndMenuWindowsOpenWithoutTheMenuBar() {
        _ = NSApplication.shared
        let f = FixtureApp(); defer { f.close(); AppWindows.closeAll() }
        AppWindows.showSettings(f.app)
        let settings = AppWindows.settingsWindow
        #expect(settings?.title == "CallReady Settings")
        #expect(settings?.isVisible == true)
        AppWindows.showSettings(f.app)
        #expect(AppWindows.settingsWindow === settings)
        AppWindows.showMenuWindow(f.app)
        #expect(AppWindows.menuWindow?.title == "CallReady")
        #expect(AppWindows.menuWindow?.isVisible == true)
    }

    @Test func reopenShowsSettingsAndDoesNotAskForADefaultWindow() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/CallReady/CallReadyApp.swift"))
        #expect(source.contains("func applicationShouldHandleReopen"))
        #expect(source.contains("AppWindows.showSettings()"))
        #expect(source.contains("\"welcomeShown\""))
    }

    #if DEBUG
    @Test func demoCanHideContinuityInputs() throws {
        let hardware = TwelveDeviceHardware()
        hardware.inventory.append(AudioDevice(id: 40, uid: "phone", name: "Owner's iPhone Microphone", transport: .continuity, inputChannels: 1, outputChannels: 0))
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let model = GuardModel(hardware: hardware, defaults: defaults, scheduleEvents: false)
        defer { GuardModel.hideContinuityForDemo = false; model.stop() }
        model.refresh(enforce: false)
        #expect(model.selectableInputs.contains { $0.uid == "phone" })
        GuardModel.hideContinuityForDemo = true
        model.refresh(enforce: false)
        #expect(!model.devices.contains { $0.transport == .continuity })
        #expect(!model.selectableInputs.contains { $0.uid == "phone" })
    }
    #endif
}
