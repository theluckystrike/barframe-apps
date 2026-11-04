import AppKit
import SwiftUI
import RouteLoomCore

@MainActor
final class AppModel: ObservableObject {
    @Published var pairName: String { didSet { defaults.set(pairName,forKey:"pairName") } }
    @Published var referenceURL: String { didSet { defaults.set(referenceURL,forKey:"referenceURL") } }
    @Published var workURL: String { didSet { defaults.set(workURL,forKey:"workURL") } }
    @Published var interval: Double { didSet { defaults.set(interval,forKey:"interval") } }
    @Published var timeout: Double { didSet { defaults.set(timeout,forKey:"timeout") } }
    @Published var retention: Int { didSet { defaults.set(retention,forKey:"retention"); prune(); save() } }
    @Published var showMenuText: Bool { didSet { defaults.set(showMenuText,forKey:"menuText") } }
    @Published var shortcut: Int { didSet { defaults.set(shortcut,forKey:"shortcut") } }
    @Published var spanish: Bool { didSet { defaults.set(spanish,forKey:"spanish") } }
    @Published var sample = false
    @Published var running = false
    @Published var checking = false
    @Published var sleeping = false
    @Published var error: String?
    @Published var shortcutError: String?
    @Published var live: [Session] = []
    @Published var samples: [Session] = []
    @Published var selectedID: UUID?
    @Published var earlierID: UUID?
    @Published var showReport = false
    @Published var showCompare = false
    @Published var copied = false
    @Published var scenario: Transport = .timeout
    @Published var now = Date()
    let defaults: UserDefaults
    let storage: URL?
    private var task: Task<Void,Never>?
    private var wakeStart: Date?
    private var generation = UUID()
    private var clock: Timer?
    private var observers: [NSObjectProtocol] = []
    var probe: (URL, URL, Double) async -> PairCheck

    init(defaults: UserDefaults = .standard, storage: URL? = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("RouteLoom/history.json"), observeSystem: Bool = true, probe: @escaping (URL,URL,Double) async -> PairCheck = Probe.pair) {
        self.defaults = defaults; self.storage = storage; self.probe = probe
        pairName = defaults.string(forKey:"pairName") ?? ""
        referenceURL = defaults.string(forKey:"referenceURL") ?? ""
        workURL = defaults.string(forKey:"workURL") ?? ""
        interval = max(10,min(300, defaults.object(forKey:"interval") as? Double ?? 30))
        timeout = max(2,min(30,defaults.object(forKey:"timeout") as? Double ?? 8))
        retention = max(5,min(50,defaults.object(forKey:"retention") as? Int ?? 20))
        showMenuText = defaults.bool(forKey:"menuText")
        shortcut = defaults.integer(forKey:"shortcut")
        spanish = defaults.object(forKey:"spanish") as? Bool ?? Locale.preferredLanguages.first?.hasPrefix("es") ?? false
        if let storage, FileManager.default.fileExists(atPath:storage.path) {
            do {
                live = try JSONDecoder().decode([Session].self,from:Data(contentsOf:storage)).filter { !$0.sample }
                for i in live.indices where live[i].ended == nil {
                    let t = live[i].checks.last?.at ?? live[i].started
                    live[i].gap(Gap(start:t,end:Date(),reason:"App shutdown · time unknown"))
                    live[i].ended = Date()
                }
                prune(); save()
            } catch { self.error = "Local history could not be read. Clear local data in Settings to recover." }
        }
        selectedID = live.first?.id
        if observeSystem {
            clock = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in Task { @MainActor in self?.now = Date() } }
            let n = NSWorkspace.shared.notificationCenter
            observers.append(n.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.sleep() } })
            observers.append(n.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.wake() } })
        }
    }
    var sessions: [Session] { sample ? samples : live }
    var selected: Session? { sessions.first { $0.id == selectedID } ?? sessions.first }
    var current: Session? { sample ? samples.first : live.first }
    var earlier: Session? {
        let candidates = sessions.filter { $0.started < (selected?.started ?? .distantPast) }
        return candidates.first { $0.id == earlierID } ?? candidates.first
    }
    var valid: Bool { (try? Endpoint.validate(referenceURL)) != nil && (try? Endpoint.validate(workURL)) != nil && !pairName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
    var menuSymbol: String {
        guard running else { return "network" }
        if sleeping || isStale { return "questionmark.circle" }
        switch current?.current ?? .insufficient { case .healthy: return "checkmark.circle"; case .insufficient: return "questionmark.circle"; default: return "exclamationmark.triangle" }
    }
    var isStale: Bool { guard running,let at = current?.checks.last?.at else { return running }; return now.timeIntervalSince(at) > interval + timeout + 5 }
    var menuLabel: String { (sample ? "Sample · " : "") + tr(running ? (sleeping || isStale ? "Insufficient evidence" : current?.current.label ?? "Insufficient evidence") : "Stopped") }
    func tr(_ text: String) -> String { spanish ? (Translations.es[text] ?? text) : text }
    func toggleSample(_ value: Bool) {
        stop(); sample = value; copied = false; error = nil
        if value { resetSample() } else { selectedID = live.first?.id; earlierID = live.dropFirst().first?.id }
    }
    func resetSample() {
        guard sample else { return }
        samples = [Fixtures.session(scenario),Fixtures.earlier]; selectedID = samples.first?.id; earlierID = samples.last?.id
    }
    func start() {
        guard !sample,!running else { return }
        do {
            guard !pairName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { error = "Name the endpoint pair in Settings";return }
            let r = try Endpoint.validate(referenceURL), w = try Endpoint.validate(workURL)
            live.insert(Session(name:pairName,referenceHost:Endpoint.host(r),workHost:Endpoint.host(w),started:Date(),sample:false),at:0)
            selectedID = live.first?.id; earlierID = live.dropFirst().first?.id
            running = true; error = nil; generation = UUID(); prune(); save()
            loop(r,w,generation)
        } catch { self.error = error.localizedDescription }
    }
    private func loop(_ r: URL,_ w: URL,_ token: UUID) {
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.running,!self.sample,!self.sleeping,self.generation == token else { return }
                self.checking = true
                let check = await self.probe(r,w,self.timeout)
                guard !Task.isCancelled,self.running,!self.sample,self.generation == token else { return }
                self.checking = false
                if !self.live.isEmpty {
                    if let last = self.live[0].checks.last, check.at.timeIntervalSince(last.at) > self.interval + self.timeout + 5 {
                        self.live[0].gap(Gap(start:last.at,end:check.at,reason:"Scheduling gap · time unknown"))
                    }
                    self.live[0].append(check); self.save()
                    if self.live[0].checks.count >= 1000 { self.error = "Session limit reached. Start a new session to continue."; self.stop(); return }
                }
                try? await Task.sleep(for:.seconds(self.interval))
            }
        }
    }
    func stop() {
        task?.cancel(); task = nil; generation = UUID(); checking = false
        if running,!live.isEmpty {
            if let wakeStart { live[0].gap(Gap(start:wakeStart,end:Date(),reason:"Sleep · time unknown")) }
            live[0].ended = Date(); save()
        }
        running = false; sleeping = false; wakeStart = nil
    }
    func sleep() {
        guard running,!sample else { return }
        wakeStart = live.first?.checks.last?.at ?? Date(); sleeping = true; task?.cancel(); checking = false; generation = UUID()
    }
    func wake() {
        guard running,sleeping,!sample else { return }
        if let wakeStart,!live.isEmpty { live[0].gap(Gap(start:wakeStart,end:Date(),reason:"Sleep · time unknown")); save() }
        wakeStart = nil; sleeping = false
        guard let r = try? Endpoint.validate(referenceURL),let w = try? Endpoint.validate(workURL) else { stop(); return }
        generation = UUID(); loop(r,w,generation)
    }
    private func prune() { if live.count > retention { live = Array(live.prefix(retention)) } }
    func save() {
        guard let storage else { return }
        do {
            try FileManager.default.createDirectory(at:storage.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(live).write(to:storage,options:.atomic)
        } catch { self.error = "Local history could not be saved. Check available storage and try again." }
    }
    func clearData() {
        stop(); live = []; samples = []; selectedID = nil; earlierID = nil
        pairName = ""; referenceURL = ""; workURL = ""
        if let storage {
            do { if FileManager.default.fileExists(atPath:storage.path) { try FileManager.default.removeItem(at:storage) }; error = nil }
            catch { self.error = "Local history could not be removed. Check storage access and try again." }
        }
        if sample { resetSample() }
    }
    var reportText: String { selected.map { Report.text($0, translate:tr) } ?? tr("No session selected") }
    func copyReport() {
        guard let selected else { return }
        NSPasteboard.general.clearContents(); copied = NSPasteboard.general.setString(Report.text(selected,translate:tr),forType:.string)
        if !copied { error = "The clipboard is unavailable. Select and copy text from the report preview." }
    }
}
