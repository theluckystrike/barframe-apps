import AppKit
import Combine
import CallCore

/// Connects the three parts into one product. Rules, in order of precedence:
/// 1. The microphone part is the only owner of the default input. It chooses the device.
/// 2. The mute part changes only the mute state of the current default input.
///    When the guard changes the input, the mute rule for the new device runs once.
/// 3. Push-to-talk pins the device it started on. While it is held, the guard does not switch the input.
/// Shared-state behaviours: one minute before the call the microphone is checked and a muted user is reminded;
/// at call start the mute state follows the user's choice; Join checks the microphone first;
/// the call shows "Ready" only when the preferred microphone is the default input and it is not muted.
@MainActor final class CallCoordinator: ObservableObject {
    let calendar: CalendarModel
    let microphone: GuardModel
    let mute: MuteModel
    @Published private(set) var status = ""
    @Published private(set) var menuBarText = ""
    @Published private(set) var readiness: CallReadiness = .noMicrophone
    @Published private(set) var preCallNote: String?
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarLabel"); recompute() } }
    @Published var checkMicBeforeCall: Bool { didSet { defaults.set(checkMicBeforeCall, forKey: "checkMicBeforeCall") } }
    @Published var callStartMute: CallStartMute { didSet { defaults.set(callStartMute.rawValue, forKey: "callStartMute") } }
    @Published var remindUnmuteAtCall: Bool {
        didSet {
            defaults.set(remindUnmuteAtCall, forKey: "remindUnmuteAtCall")
            if remindUnmuteAtCall { LocalNotifier.requestPermission() }
        }
    }
    private(set) var checkedCalls: [String: Date] = [:]
    private(set) var startedCalls: [String: Date] = [:]
    /// Posts a notification. Tests replace it.
    var notify: (_ id: String, _ title: String, _ body: String) -> Void = { LocalNotifier.post(id: $0, title: $1, body: $2) }
    private let defaults: UserDefaults
    private var bag: Set<AnyCancellable> = []
    private var lastInputID: UInt32?
    private var recomputeQueued = false
    private let muteListener = MuteStateListener()
    private var started = false

    init(calendar: CalendarModel, microphone: GuardModel, mute: MuteModel, defaults: UserDefaults = .standard) {
        self.calendar = calendar; self.microphone = microphone; self.mute = mute; self.defaults = defaults
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarLabel") ?? "") ?? .short
        checkMicBeforeCall = defaults.object(forKey: "checkMicBeforeCall") as? Bool ?? true
        callStartMute = CallStartMute(rawValue: defaults.string(forKey: "callStartMute") ?? "") ?? .keep
        remindUnmuteAtCall = defaults.bool(forKey: "remindUnmuteAtCall")
        calendar.onTick = { [weak self] date in self?.runCallChecks(at: date) }
        for publisher in [calendar.objectWillChange.eraseToAnyPublisher(), microphone.objectWillChange.eraseToAnyPublisher(),
                          mute.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in self?.scheduleRecompute() }.store(in: &bag)
        }
        microphone.$inputID.removeDuplicates().sink { [weak self] id in self?.inputChanged(id) }.store(in: &bag)
        mute.onPushToTalkChange = { [weak self] held in self?.microphone.setInputHeld(held) }
        recompute()
    }

    /// The live app. Built once, on the main actor.
    static let live: CallCoordinator = {
        CallCoordinator(calendar: CalendarModel(), microphone: GuardModel(), mute: MuteModel())
    }()

    func start() {
        guard !started else { return }
        started = true
        mute.badgePanel = MicBadgePanel()
        mute.registerPushToTalkRelease()
        mute.applyHotKey(mute.hotKey)
        mute.start()
        microphone.start()
        muteListener.watch { [weak self] in self?.mute.refresh() }
        recompute()
    }

    func stop() {
        muteListener.stop()
        mute.stop()
        microphone.stop()
        HotKeyCenter.shared.unregister()
    }

    var micName: String? { microphone.currentInput?.name ?? mute.currentDefault()?.name }

    var snapshot: CallSnapshot {
        CallSnapshot(now: calendar.now, access: calendar.access, nextEvent: calendar.nextEvent,
                     micName: micName, muted: mute.muteState(), talking: mute.pttActive)
    }

    func currentReadiness() -> CallReadiness {
        let current = microphone.currentInput
        let preferred = microphone.preferred
        return CallReadiness.evaluate(currentUID: current?.uid ?? mute.currentDefault()?.uid, currentName: micName,
                                      preferredUID: preferred?.uid, preferredName: preferred?.name,
                                      guardEnabled: microphone.settings.enabled && !microphone.bluetoothAllowed,
                                      muted: mute.muteState(), talking: mute.pttActive)
    }

    func recompute() {
        recomputeQueued = false
        let value = snapshot
        let line = CallStatus.line(value), bar = CallStatus.menuBarText(value, style: menuBarStyle)
        if line != status { status = line }
        if bar != menuBarText { menuBarText = bar }
        let ready = currentReadiness()
        if ready != readiness { readiness = ready }
    }

    private func scheduleRecompute() {
        guard !recomputeQueued else { return }
        recomputeQueued = true
        DispatchQueue.main.async { [weak self] in self?.recompute() }
    }

    /// The guard (or the user) changed the default input: apply the mute rule to the new device once.
    func inputChanged(_ id: UInt32) {
        guard id != 0 else { return }
        defer { lastInputID = id }
        guard lastInputID != nil, lastInputID != id else { return }
        mute.defaultDeviceChanged()
        muteListener.rewatch()
    }

    func runCallChecks(at date: Date) {
        runPreCallCheck(at: date)
        runCallStart(at: date)
    }

    /// One minute before the call: keep the preferred microphone as default, then remind a muted user.
    /// The plan is computed after the microphone check finishes, because the guard can move the input
    /// to a device with a different mute state.
    func runPreCallCheck(at date: Date) {
        checkedCalls = PreCallCheck.prune(checkedCalls, now: date)
        guard let event = PreCallCheck.dueEvent(events: calendar.events, now: date, handled: Set(checkedCalls.keys)) else { return }
        checkedCalls[event.id] = date
        if checkMicBeforeCall {
            microphone.refresh(enforce: true) { [weak self] in self?.finishPreCallCheck(event, at: date) }
        } else {
            finishPreCallCheck(event, at: date)
        }
    }

    private func finishPreCallCheck(_ event: MeetEvent, at date: Date) {
        let muted = mute.muteState()
        let plan = PreCallCheck.plan(checkMicrophone: checkMicBeforeCall, remindIfMuted: remindUnmuteAtCall, muted: muted)
        if !plan.isEmpty {
            preCallNote = PreCallCheck.report(event: event, now: date, micName: micName, muted: muted, shortcut: mute.hotKey.label)
        }
        if plan.remindToUnmute {
            let text = CallNotice.unmute(event: event, now: date, shortcut: mute.hotKey.label, showTitle: calendar.showTitlesInNotifications)
            notify("call-" + event.id, text.title, text.body)
        }
        recompute()
    }

    /// At the start time of a call: apply the user's call-start mute choice to the current default input.
    func runCallStart(at date: Date) {
        startedCalls = PreCallCheck.prune(startedCalls, now: date)
        guard let event = PreCallCheck.dueEvent(events: calendar.events, now: date, lead: 0, handled: Set(startedCalls.keys)) else { return }
        startedCalls[event.id] = date
        guard let target = callStartMute.target(currentlyMuted: mute.muteState(), talking: mute.pttActive),
              let device = mute.currentDefault() else { return }
        mute.apply(target: target, device: device)
        recompute()
    }

    /// The longest time Join waits for the microphone check.
    nonisolated static let joinWait: TimeInterval = 0.5
    private var joinToken = 0
    private var pendingJoin: (() -> Void)?

    /// Join: check the microphone first, then open the meeting link. The link opens when the check
    /// finishes, or after `wait` seconds, whichever comes first. It opens one time.
    func join(_ url: URL, wait: TimeInterval = CallCoordinator.joinWait, open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        joinToken += 1
        let token = joinToken
        pendingJoin = { open(url) }
        microphone.refresh(enforce: true) { [weak self] in self?.finishJoin(token) }
        guard pendingJoin != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.finishJoin(token) }
    }

    private func finishJoin(_ token: Int) {
        guard token == joinToken, let action = pendingJoin else { return }
        pendingJoin = nil
        recompute()
        action()
    }

    func dismissPreCallNote() { preCallNote = nil }
}
