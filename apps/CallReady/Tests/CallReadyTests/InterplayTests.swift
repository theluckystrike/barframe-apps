import Foundation
import Testing
@testable import CallReady
import CallCore

/// Behaviours that exist only because the three parts share state.
@Suite(.serialized) @MainActor struct InterplayTests {
    /// Mirrors the guard's default input in the mute fixture: id 1 is the built-in mic, id 12 the Bluetooth headset.
    private func linked(async asyncHardware: Bool = false) -> FixtureApp {
        let f = FixtureApp(asyncHardware: asyncHardware)
        f.micHardware.inventory[0] = AudioDevice(id: 1, uid: "fixture-1", name: "MacBook Pro Microphone", transport: .builtIn, inputChannels: 1, outputChannels: 0)
        f.muteBackend.list = [
            InputDevice(id: "12", name: "Fixture Bluetooth headset", supportsMute: true, supportsVolume: true, isDefault: true),
            InputDevice(id: "1", name: "MacBook Pro Microphone", supportsMute: true, supportsVolume: true, isDefault: false),
        ]
        f.muteBackend.mutes = ["12": false, "1": false]
        // The async path writes on the audio worker queue; mirror the change on the main queue.
        f.micHardware.onSet = { [unowned f] id in
            if Thread.isMainThread { _ = f.muteBackend.select(String(id)) }
            else { DispatchQueue.main.async { _ = f.muteBackend.select(String(id)) } }
        }
        return f
    }
    /// Starts on the preferred built-in mic.
    private func onBuiltIn(_ f: FixtureApp, muted: Bool) {
        f.micHardware.input = 1; _ = f.muteBackend.select("1"); f.muteBackend.mutes["1"] = muted
        f.microphone.refresh(enforce: false)
    }
    private func call(_ f: FixtureApp, inMinutes minutes: Double, title: String = "Standup", link: String = "https://zoom.us/j/1") -> MeetEvent {
        let start = f.calendar.now.addingTimeInterval(minutes * 60)
        let e = MeetEvent(id: "call-1", title: title, start: start, end: start.addingTimeInterval(1800), searchText: link)
        f.grant([e])
        return e
    }

    @Test func statusLineShowsMeetingMicAndMute() {
        let f = linked(); defer { f.close() }
        onBuiltIn(f, muted: true)
        f.microphone.refresh(enforce: false)
        _ = call(f, inMinutes: 4)
        f.app.recompute()
        #expect(f.app.status == "Standup in 4 min · MacBook Pro mic · Muted")
        #expect(f.app.readiness == .muted)
    }

    @Test func oneMinuteBeforeCallMovesBluetoothInputBackToPreferredMic() {
        let f = linked(); defer { f.close() }
        let e = call(f, inMinutes: 5)
        f.micHardware.input = 12
        f.app.runCallChecks(at: e.start.addingTimeInterval(-120))
        #expect(f.micHardware.writes.isEmpty)
        f.app.runCallChecks(at: e.start.addingTimeInterval(-60))
        #expect(f.micHardware.input == 1)
        #expect(f.app.preCallNote?.contains("MacBook Pro mic") == true)
        f.app.runCallChecks(at: e.start.addingTimeInterval(-30))
        #expect(f.micHardware.writes == [1])
        #expect(f.app.checkedCalls.count == 1)
    }

    @Test func preCallMicCheckRespectsTheSetting() {
        let f = linked(); defer { f.close() }
        f.app.checkMicBeforeCall = false
        let e = call(f, inMinutes: 5)
        f.micHardware.input = 12
        f.app.runCallChecks(at: e.start.addingTimeInterval(-60))
        #expect(f.micHardware.writes.isEmpty)
        #expect(f.app.preCallNote == nil)
    }

    @Test func mutedUserGetsOneReminderWithTheShortcut() {
        let f = linked(); defer { f.close() }
        f.app.remindUnmuteAtCall = true
        onBuiltIn(f, muted: true)
        let e = call(f, inMinutes: 5)
        f.app.runCallChecks(at: e.start.addingTimeInterval(-50))
        f.app.runCallChecks(at: e.start.addingTimeInterval(-40))
        #expect(f.notifications.count == 1)
        #expect(f.notifications.first?.1 == "Call in 1 minute")
        #expect(f.notifications.first?.2 == "You're muted. Press ⇧⌥M to unmute.")
        #expect(f.notifications.allSatisfy { !$0.1.contains("Standup") && !$0.2.contains("Standup") })
    }

    /// The mic check runs before the reminder: a guard switch to an open mic cancels the reminder.
    @Test func reminderUsesMuteStateAfterTheMicCheck() {
        let f = linked(); defer { f.close() }
        f.app.remindUnmuteAtCall = true
        f.micHardware.input = 12; f.muteBackend.mutes["12"] = true
        let e = call(f, inMinutes: 5)
        f.app.runCallChecks(at: e.start.addingTimeInterval(-50))
        #expect(f.micHardware.input == 1)
        #expect(f.notifications.isEmpty)
    }

    @Test func openMicGetsNoReminder() {
        let f = linked(); defer { f.close() }
        f.app.remindUnmuteAtCall = true
        let e = call(f, inMinutes: 5)
        f.app.runCallChecks(at: e.start.addingTimeInterval(-50))
        #expect(f.notifications.isEmpty)
    }

    @Test func callStartAppliesTheMuteChoiceOnce() {
        let f = linked(); defer { f.close() }
        f.app.callStartMute = .unmute
        onBuiltIn(f, muted: true)
        let e = call(f, inMinutes: 5)
        f.app.checkMicBeforeCall = false
        f.app.runCallChecks(at: e.start.addingTimeInterval(-10))
        #expect(f.mute.muteState() == true)
        f.app.runCallChecks(at: e.start)
        #expect(f.mute.muteState() == false)
        f.mute.muteDefault()
        f.app.runCallChecks(at: e.start.addingTimeInterval(20))
        #expect(f.mute.muteState() == true)
    }

    @Test func callStartKeepLeavesMuteStateAlone() {
        let f = linked(); defer { f.close() }
        onBuiltIn(f, muted: true)
        let e = call(f, inMinutes: 5)
        f.app.runCallChecks(at: e.start)
        #expect(f.app.callStartMute == .keep)
        #expect(f.mute.muteState() == true)
    }

    /// Sequence 1 from the review: the guard switches input; the mute rule must keep a muted user muted.
    @Test func guardSwitchKeepsMutedUserMutedOnTheNewMic() {
        let f = linked(); defer { f.close() }
        f.mute.setIntent(.stayMutedOnly)
        f.micHardware.input = 12
        f.mute.start()
        f.mute.muteDefault()
        f.microphone.refresh(enforce: true)
        #expect(f.micHardware.input == 1)
        #expect(f.mute.currentDefault()?.id == "1")
        #expect(f.muteBackend.mutes["1"] == true)
    }

    /// Sequence 1, other branch: the guard switch must not mute a mic the user left open.
    @Test func guardSwitchDoesNotMuteAnOpenUser() {
        let f = linked(); defer { f.close() }
        f.mute.setIntent(.stayMutedOnly)
        f.micHardware.input = 12
        f.mute.start()
        f.microphone.refresh(enforce: true)
        #expect(f.micHardware.input == 1)
        #expect(f.muteBackend.mutes["1"] == false)
    }

    /// Sequence 2 from the review: push-to-talk pins the input; the guard waits until release.
    @Test func pushToTalkPinsTheInputUntilRelease() {
        let f = linked(); defer { f.close() }
        f.micHardware.input = 12
        f.mute.start()
        f.muteBackend.mutes["12"] = true
        f.mute.setPushToTalk(true)
        f.mute.beginPushToTalk()
        #expect(f.mute.pttActive)
        #expect(f.microphone.inputHeld)
        f.microphone.refresh(enforce: true)
        #expect(f.micHardware.writes.isEmpty)
        #expect(f.micHardware.input == 12)
        f.mute.endPushToTalk()
        #expect(!f.microphone.inputHeld)
        #expect(f.muteBackend.mutes["12"] == true)
        #expect(f.micHardware.input == 1)
    }

    @Test func joinChecksTheMicrophoneBeforeOpeningTheLink() {
        let f = linked(); defer { f.close() }
        let e = call(f, inMinutes: 2)
        f.micHardware.input = 12
        var inputAtOpen: UInt32?
        let link = JoinParser.firstJoinLink(in: e.searchText)!
        f.app.join(link) { _ in inputAtOpen = f.micHardware.input }
        #expect(inputAtOpen == 1)
    }

    @Test func readinessTracksMicAndMute() {
        let f = linked(); defer { f.close() }
        f.micHardware.input = 12
        f.microphone.refresh(enforce: false)
        f.app.recompute()
        #expect(f.app.readiness == .wrongMicrophone(preferred: "MacBook Pro Microphone"))
        f.microphone.refresh(enforce: true)
        f.app.recompute()
        #expect(f.app.readiness == .ready)
        f.mute.muteDefault()
        f.app.recompute()
        #expect(f.app.readiness == .muted)
    }

    @Test func settingsPersistAcrossLaunches() {
        let f = linked(); defer { f.close() }
        f.app.menuBarStyle = .compact; f.app.callStartMute = .mute; f.app.checkMicBeforeCall = false
        let again = CallCoordinator(calendar: f.calendar, microphone: f.microphone, mute: f.mute, defaults: f.defaults)
        let fresh = FixtureApp(); defer { fresh.close() }
        #expect(fresh.app.menuBarStyle == .short)
        #expect(again.menuBarStyle == .compact && again.callStartMute == .mute && !again.checkMicBeforeCall)
        #expect(!again.remindUnmuteAtCall)
    }

    @Test func meetingTitleShowsInNotificationOnlyWhenTurnedOn() {
        let f = linked(); defer { f.close() }
        f.app.remindUnmuteAtCall = true
        f.calendar.showTitlesInNotifications = true
        onBuiltIn(f, muted: true)
        let e = call(f, inMinutes: 5)
        f.app.runCallChecks(at: e.start.addingTimeInterval(-50))
        #expect(f.notifications.first?.1 == "Standup")
        #expect(f.notifications.first?.2 == "Starts in 1 minute. You're muted. Press ⇧⌥M to unmute.")
    }

    @Test func setAsDefaultInputDrivesTheGuard() {
        let f = linked(); defer { f.close() }
        onBuiltIn(f, muted: false)
        f.microphone.useInputNow(5)
        #expect(f.micHardware.input == 5)
        #expect(f.microphone.manualNote?.contains("Fixture Microphone 5") == true)
        f.microphone.refresh(enforce: true)
        #expect(f.micHardware.input == 5)
        f.microphone.useInputNow(12)
        #expect(f.micHardware.input == 12)
        f.microphone.refresh(enforce: true)
        #expect(f.micHardware.input == 1)
        #expect(f.microphone.settings.history.last?.reason == "Bluetooth input replaced")
        f.microphone.useInputNow(1)
        #expect(f.microphone.manualNote == "This microphone is already the default input.")
        #expect(f.microphone.selectableInputs.count == 12)
    }

    /// Two wired inputs, as in the review notes: built-in (id 1) and USB (id 2). Returns a closure that presses the mute shortcut.
    private func twoInputs(intent: ReapplyLogic.Intent = .stayMutedOnly) -> (FixtureApp, () -> Void) {
        let f = linked()
        f.micHardware.inventory[1] = AudioDevice(id: 2, uid: "fixture-2", name: "USB Microphone", transport: .usb, inputChannels: 1, outputChannels: 0)
        f.muteBackend.list = [
            InputDevice(id: "1", name: "MacBook Pro Microphone", supportsMute: true, supportsVolume: true, isDefault: true),
            InputDevice(id: "2", name: "USB Microphone", supportsMute: true, supportsVolume: true, isDefault: false),
        ]
        f.muteBackend.mutes = ["1": false, "2": false]
        f.mute.setIntent(intent)
        var shortcut: () -> Void = {}
        f.mute.registerShortcut = { _, action in shortcut = action; return true }
        f.mute.applyHotKey(.default)
        f.micHardware.input = 1
        f.microphone.refresh(enforce: false)
        f.mute.start()
        return (f, { shortcut() })
    }
    /// A person needs some seconds per step. Manual clicks do not use the automatic budget (3 writes in 30 s), so the pace is free.
    private func pause(_ f: FixtureApp, _ seconds: TimeInterval = 15) { f.calendar.now = f.calendar.now.addingTimeInterval(seconds) }
    /// The readiness label as CallMenuView shows it next to the meeting.
    private func readinessLabel(_ f: FixtureApp) -> String {
        f.app.recompute()
        return f.app.readiness.isReady ? "Ready for this call" : f.app.readiness.text
    }

    /// Review notes, "TEST WITH ANY TWO INPUTS", steps 1 to 4, with the default mute rule.
    @Test func reviewNotesTwoInputSteps() {
        let (f, pressShortcut) = twoInputs(); defer { f.close() }
        _ = call(f, inMinutes: 10)
        // Step 1: Settings > Microphone, select the preferred microphone.
        f.microphone.setPreferred("fixture-1")
        #expect(f.microphone.preferred?.name == "MacBook Pro Microphone")
        #expect(readinessLabel(f) == "Ready for this call")
        // Step 2: "Set as default input" next to the other microphone. The guard does not move a wired mic back.
        pause(f); f.microphone.useInputNow(2)
        f.microphone.refresh(enforce: true)
        #expect(f.micHardware.input == 2)
        #expect(f.mute.currentDefault()?.id == "2")
        #expect(readinessLabel(f) == "Not on MacBook Pro mic")
        #expect(f.app.readiness == .wrongMicrophone(preferred: "MacBook Pro Microphone"))
        // Step 3: mute with the shortcut, then select the preferred mic, then the other mic again. Mute follows.
        pressShortcut()
        #expect(f.muteBackend.mutes["2"] == true)
        #expect(readinessLabel(f) == "Not on MacBook Pro mic")
        pause(f); f.microphone.useInputNow(1)
        #expect(f.micHardware.input == 1)
        #expect(f.muteBackend.mutes["1"] == true)
        #expect(readinessLabel(f) == "Muted")
        pause(f); f.microphone.useInputNow(2)
        #expect(f.micHardware.input == 2)
        #expect(f.muteBackend.mutes["2"] == true)
        #expect(readinessLabel(f) == "Not on MacBook Pro mic")
        // Step 4: "Set as default input" next to the preferred mic, then unmute with the shortcut.
        pause(f); f.microphone.useInputNow(1)
        #expect(f.micHardware.input == 1)
        #expect(f.muteBackend.mutes["1"] == true)
        #expect(readinessLabel(f) == "Muted")
        pressShortcut()
        #expect(f.muteBackend.mutes["1"] == false)
        #expect(readinessLabel(f) == "Ready for this call")
        #expect(f.app.readiness == .ready)
        #expect(f.app.status == "Standup in 9 min · MacBook Pro mic · Mic on")
    }

    /// Six quick "Set as default input" clicks, as a reviewer may do: each one changes the input. No pause starts.
    @Test func sixQuickManualClicksAllSucceed() {
        let (f, _) = twoInputs(); defer { f.close() }
        _ = call(f, inMinutes: 10)
        f.microphone.setPreferred("fixture-1")
        let before = f.micHardware.writes.count
        for id: UInt32 in [2, 1, 2, 1, 2, 1] {
            f.microphone.useInputNow(id)
            #expect(f.micHardware.input == id)
            #expect(f.mute.currentDefault()?.id == String(id))
            #expect(f.microphone.manualNote == "Default input set to \(id == 1 ? "MacBook Pro Microphone" : "USB Microphone").")
            #expect(!f.microphone.loopPaused)
        }
        #expect(Array(f.micHardware.writes.dropFirst(before)) == [2, 1, 2, 1, 2, 1])
        #expect(f.microphone.status == "Bluetooth guard is on")
        #expect(readinessLabel(f) == "Ready for this call")
    }

    /// The note says "Default input set" only after the read-back shows the new default.
    @Test func manualClickWithoutEffectSaysSo() {
        let (f, _) = twoInputs(); defer { f.close() }
        // Another app puts the built-in mic back at once.
        f.micHardware.onSet = { [unowned f] _ in f.micHardware.input = 1 }
        f.microphone.useInputNow(2)
        #expect(f.micHardware.input == 1)
        #expect(f.microphone.manualNote == "Setting USB Microphone as the default input…")
        pause(f, 3); f.microphone.processDeadline()
        #expect(f.microphone.manualNote == "CallReady could not confirm that USB Microphone is the default input. Check the input and try again.")
        #expect(!f.microphone.loopPaused)
        f.micHardware.onSet = nil
        f.microphone.useInputNow(2)
        #expect(f.micHardware.input == 2)
        #expect(f.microphone.manualNote == "Default input set to USB Microphone.")
    }

    /// Review notes step 3 for each "When the default microphone changes" choice: muted, muted, unchanged.
    @Test(arguments: [ReapplyLogic.Intent.stayMutedOnly, .alwaysMute, .off])
    func reviewNotesStepThreeFollowsTheMuteRule(intent: ReapplyLogic.Intent) {
        let (f, pressShortcut) = twoInputs(intent: intent); defer { f.close() }
        f.microphone.setPreferred("fixture-1")
        pause(f); f.microphone.useInputNow(2)
        // "Always mute the new microphone" already muted it at step 2; the shortcut would unmute it.
        #expect(f.muteBackend.mutes["2"] == (intent == .alwaysMute))
        if intent != .alwaysMute { pressShortcut() }
        #expect(f.muteBackend.mutes["2"] == true)
        pause(f); f.microphone.useInputNow(1)
        #expect(f.micHardware.input == 1)
        #expect(f.muteBackend.mutes["1"] == (intent != .off))
        #expect(readinessLabel(f) == (intent == .off ? "Ready for this call" : "Muted"))
        pause(f); f.microphone.useInputNow(2)
        #expect(f.muteBackend.mutes["2"] == true)
        #expect(readinessLabel(f) == "Not on MacBook Pro mic")
    }

    // Async path (scheduleEvents: true): the shipping order of read, write and plan.

    @Test func asyncManualNoteWaitsForTheReadBack() async {
        let f = linked(async: true); defer { f.close() }
        f.micHardware.input = 1
        f.microphone.refresh(enforce: false)
        await spin { f.microphone.inputID == 1 }
        f.microphone.useInputNow(5)
        #expect(f.microphone.manualNote == "Setting Fixture Microphone 5 as the default input…")
        await spin { f.microphone.manualNote != "Setting Fixture Microphone 5 as the default input…" }
        #expect(f.micHardware.input == 5)
        #expect(f.microphone.manualNote == "Default input set to Fixture Microphone 5.")
    }

    @Test func asyncPreCallPlanUsesMuteStateAfterTheGuardSwitch() async {
        let f = linked(async: true); defer { f.close() }
        f.app.remindUnmuteAtCall = true
        f.micHardware.input = 12; f.muteBackend.mutes["12"] = true
        let e = call(f, inMinutes: 5)
        f.app.runCallChecks(at: e.start.addingTimeInterval(-50))
        #expect(f.app.preCallNote == nil)
        await spin { f.app.preCallNote != nil }
        #expect(f.micHardware.input == 1)
        #expect(f.mute.currentDefault()?.id == "1")
        #expect(f.app.preCallNote?.contains("MacBook Pro mic") == true)
        #expect(f.notifications.isEmpty)
    }

    @Test func asyncPreCallReminderStillFiresWhenMutedAfterTheCheck() async {
        let f = linked(async: true); defer { f.close() }
        f.app.remindUnmuteAtCall = true
        f.micHardware.input = 1; _ = f.muteBackend.select("1"); f.muteBackend.mutes["1"] = true
        let e = call(f, inMinutes: 5)
        f.app.runCallChecks(at: e.start.addingTimeInterval(-50))
        await spin { !f.notifications.isEmpty }
        #expect(f.notifications.count == 1)
        #expect(f.micHardware.writes.isEmpty)
    }

    @Test func asyncJoinOpensAfterTheMicCheck() async {
        let f = linked(async: true); defer { f.close() }
        let e = call(f, inMinutes: 2)
        f.micHardware.input = 12
        var inputAtOpen: UInt32?
        var opens = 0
        f.app.join(JoinParser.firstJoinLink(in: e.searchText)!) { _ in opens += 1; inputAtOpen = f.micHardware.input }
        #expect(opens == 0)
        await spin { opens > 0 }
        #expect(inputAtOpen == 1)
        await spin(until: { false }, timeout: 0.7)
        #expect(opens == 1)
    }

    @Test func asyncJoinNeverWaitsLongerThanTheCap() async {
        let f = linked(async: true); defer { f.close() }
        let e = call(f, inMinutes: 2)
        f.micHardware.readDelay = 2
        let started = Date()
        var openedAfter: TimeInterval?
        var opens = 0
        f.app.join(JoinParser.firstJoinLink(in: e.searchText)!) { _ in opens += 1; openedAfter = Date().timeIntervalSince(started) }
        await spin { opens > 0 }
        #expect(opens == 1)
        #expect((openedAfter ?? 9) >= 0.45 && (openedAfter ?? 9) < 1.5)
        await spin(until: { false }, timeout: 2.2)
        #expect(opens == 1)
    }

    #if DEBUG
    @Test func debugDemoEventNeedsNoEventKitAndSurvivesTicks() {
        let f = FixtureApp(); defer { f.close() }
        f.calendar.useDemoEvent(now: f.calendar.now)
        #expect(f.calendar.access == .granted)
        #expect(f.calendar.nextEvent?.title == "Design review")
        let link = JoinParser.firstJoinLink(in: f.calendar.nextEvent?.searchText ?? "")
        #expect(link?.absoluteString == "https://example.com/j/123")
        f.calendar.tick(at: f.calendar.now.addingTimeInterval(31))
        #expect(f.calendar.events.count == 1)
        f.app.recompute()
        #expect(f.app.menuBarText == "4m")
        f.microphone.hideIntroductionForDemo()
        #expect(!f.microphone.needsIntroduction)
        #expect(f.defaults.object(forKey: "introductionSeen") == nil)
    }
    #endif
}
