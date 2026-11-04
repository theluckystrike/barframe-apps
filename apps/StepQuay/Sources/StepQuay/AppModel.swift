import SwiftUI
import AppKit
import StepQuayCore

@MainActor
final class AppModel: ObservableObject {
    @Published var queue = Queue()
    @Published var sampleMode = false
    @Published var message = ""
    @Published var shortcutError = ""
    @Published var storageFailed = false
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var defaultMinutes: Double { didSet { defaults.set(defaultMinutes, forKey: "defaultMinutes") } }
    @Published var showTime: Bool { didSet { defaults.set(showTime, forKey: "showTime") } }
    @Published var retention: Int { didSet { defaults.set(retention, forKey: "retention"); pruneLiveHistory() } }
    @Published var shortcutKey: String { didSet { defaults.set(shortcutKey, forKey: "shortcutKey"); shortcutChanged?() } }
    @Published var shortcutModifiers: String { didSet { defaults.set(shortcutModifiers, forKey: "shortcutModifiers"); shortcutChanged?() } }
    var shortcutChanged: (() -> Void)?
    private let defaults: UserDefaults
    private var live = Queue()
    private var timer: Timer?
    private var lastHistoryCleanup = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    init(defaults: UserDefaults = .standard, timerEnabled: Bool = true) {
        self.defaults = defaults
        language = defaults.string(forKey: "language") ?? "auto"
        defaultMinutes = defaults.object(forKey: "defaultMinutes") as? Double ?? 10
        showTime = defaults.object(forKey: "showTime") as? Bool ?? true
        retention = defaults.object(forKey: "retention") as? Int ?? 30
        shortcutKey = defaults.string(forKey: "shortcutKey") ?? "K"
        shortcutModifiers = defaults.string(forKey: "shortcutModifiers") ?? "commandOption"
        if let data = defaults.data(forKey: "queue") {
            do { queue = try Queue.decoded(data); queue.recoverAfterLaunch() }
            catch { storageFailed = true; message = l("Saved tasks could not be read. Restore the saved data or reset the queue in Settings.") }
        }
        live = queue
        pruneLiveHistory()
        if timerEnabled {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.change { $0.sleep(now: ProcessInfo.processInfo.systemUptime) } }
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.queue.current?.phase == .paused else { return }
                    self.message = self.l("Sleep paused your action. Read the note and resume when ready.")
                }
            })
        }
    }
    var spanish: Bool { language == "es" || (language == "auto" && Locale.preferredLanguages.first?.hasPrefix("es") == true) }
    func l(_ text: String) -> String { spanish ? (Translations.spanish[text] ?? text) : text }
    func tick(now: Date = Date(), uptime: Double = ProcessInfo.processInfo.systemUptime) {
        if now.timeIntervalSince(lastHistoryCleanup) >= 60 { pruneLiveHistory(now: now) }
        guard queue.current?.phase == .running else { return }
        change(clearMessage: false) { $0.tick(uptime) }
    }
    func pruneLiveHistory(now: Date = Date()) {
        lastHistoryCleanup = now
        guard !storageFailed else { return }
        var updated = sampleMode ? live : queue
        updated.retainHistory(days: retention, now: now)
        let previous = sampleMode ? live : queue
        guard updated.history != previous.history else { return }
        do {
            defaults.set(try updated.encoded(), forKey: "queue")
            live = updated
            if !sampleMode { queue = updated }
        } catch { message = error.localizedDescription }
    }
    func change(clearMessage: Bool = true, _ operation: (inout Queue) throws -> Void) {
        guard sampleMode || !storageFailed else {
            message = l("Saved tasks could not be read. Restore the saved data or reset the queue in Settings.")
            return
        }
        do {
            var updated = queue; try operation(&updated); queue = updated
            if !sampleMode { live = queue; defaults.set(try queue.encoded(), forKey: "queue") }
            if clearMessage { message = "" }
        } catch let error as QueueError {
            switch error {
            case .invalidTitle: message = l("Enter a task title with up to 120 characters.")
            case .invalidDuration: message = l("Enter minutes greater than zero and no more than 1440.")
            case .invalidNote: message = l("Add a resume note with up to 240 characters.")
            case .busy: message = l("Finish or defer the current action first.")
            case .missing: message = l("That action is no longer available.")
            }
        } catch { message = error.localizedDescription }
    }
    func toggleSample(_ on: Bool) {
        guard on != sampleMode else { return }
        if on {
            // Freeze a live running task before switching so sample time is never charged to it.
            if queue.current?.phase == .running { change { try $0.interrupt(note: l("Paused while exploring Sample"), now: ProcessInfo.processInfo.systemUptime) } }
            live = queue; sampleMode = true; queue = Queue.sample()
        } else { sampleMode = false; queue = live }
        message = !on && storageFailed ? l("Saved tasks could not be read. Restore the saved data or reset the queue in Settings.") : ""
    }
    func resetSample() { if sampleMode { queue = Queue.sample(); message = "" } }
    func resetStoredQueue() {
        if let old = defaults.data(forKey: "queue") { defaults.set(old, forKey: "queueRecoveryBackup") }
        storageFailed = false; live = Queue()
        if !sampleMode { queue = live }
        defaults.set(try? live.encoded(), forKey: "queue"); message = l("Queue reset. A local recovery backup was kept.")
    }
    func restoreSavedData() {
        guard let data = defaults.data(forKey: "queueRecoveryBackup") ?? defaults.data(forKey: "queue") else { return }
        do {
            var recovered = try Queue.decoded(data); recovered.recoverAfterLaunch()
            recovered.retainHistory(days: retention)
            live = recovered; if !sampleMode { queue = recovered }
            defaults.set(try recovered.encoded(), forKey: "queue"); storageFailed = false; message = l("Saved tasks restored.")
        } catch { message = l("Saved tasks could not be read. Restore the saved data or reset the queue in Settings.") }
    }
    func start() { change { try $0.start(now: ProcessInfo.processInfo.systemUptime) } }
    func resume() { change { try $0.resume(now: ProcessInfo.processInfo.systemUptime) } }
    func finish() { change { try $0.finish(now: ProcessInfo.processInfo.systemUptime) } }
    func deferAction() { change { try $0.deferCurrent(now: ProcessInfo.processInfo.systemUptime) } }
    var symbol: String {
        guard let action = queue.current else { return queue.actions.contains { $0.remaining <= 0 } ? "exclamationmark.circle" : "list.bullet" }
        if action.phase == .paused { return "pause.circle" }
        return action.remaining <= 0 ? "exclamationmark.circle" : "play.circle"
    }
    var menuLabel: String {
        let state: String
        if let action = queue.current { state = l(action.phase == .paused ? "Paused" : action.remaining <= 0 ? "Overdue" : "Running") + " " + action.title }
        else { state = l(queue.actions.isEmpty ? "No actions yet" : "Ready for your next action") }
        return "StepQuay " + (sampleMode ? "Sample " : "") + state
    }
}
