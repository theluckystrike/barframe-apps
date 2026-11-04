import SwiftUI
import AgentPingCore
import UserNotifications
import ServiceManagement

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AgentPing", isDirectory: true)
    }
    static var historyURL: URL { supportDirectory.appendingPathComponent("history.json") }
    private var preferencesURL: URL { Self.supportDirectory.appendingPathComponent("preferences.json") }
    private let storageURL: URL
    private let persistence: HistoryPersistence
    private let notificationAuthorization: () async -> UNAuthorizationStatus
    private let notificationDelivery: (UNNotificationRequest) async throws -> Void
    private var ingress = EventIngress(token: "")
    private(set) var isShuttingDown = false
    @Published private(set) var token = ""
    @Published private(set) var notificationsAllowed = false
    @Published private(set) var isSample = false
    private var liveHistory: History?
    func setSampleMode(_ enabled: Bool) {
        guard enabled != isSample else { return }
        if enabled { liveHistory = history; history = SampleContent.history }
        else { history = liveHistory ?? History(); liveHistory = nil }
        isSample = enabled
        status = enabled ? "Sample: fictional events; changes are not saved." : ""
    }
    @Published var history = History()
    @Published var preferences = Preferences()
    @Published var status = ""
    @Published var notificationStatus = "Check notification settings"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var copied = ""

    init(token testToken: String? = nil, historyURL: URL? = nil,
         historyWriter: @escaping @Sendable (History, URL) throws -> Void = { try $0.save(to: $1) },
         notificationAuthorization: @escaping () async -> UNAuthorizationStatus = {
             await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
         },
         notificationDelivery: @escaping (UNNotificationRequest) async throws -> Void = {
             try await UNUserNotificationCenter.current().add($0)
         }) {
        storageURL = historyURL ?? Self.historyURL
        persistence = HistoryPersistence(url: storageURL, writer: historyWriter)
        self.notificationAuthorization = notificationAuthorization
        self.notificationDelivery = notificationDelivery
        persistence.onError = { [weak self] detail in
            Task { @MainActor in self?.status = "Cannot save history: \(detail)" }
        }
        if let testToken {
            token = testToken
            ingress = EventIngress(token: testToken)
            return
        }
        do { token = try InstallationToken.load(); ingress = EventIngress(token: token) }
        catch { status = "Cannot create event token: \(error.localizedDescription)" }

        if FileManager.default.fileExists(atPath: storageURL.path) {
            do { history = try History.load(from: storageURL) }
            catch { status = "Cannot load history: \(error.localizedDescription)" }
        }
        if FileManager.default.fileExists(atPath: preferencesURL.path) {
            do { preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: preferencesURL)) }
            catch { status = "Cannot load preferences: \(error.localizedDescription)" }
        }
    }
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.updateNotificationStatus(settings.authorizationStatus)
            }
        }
    }
    func updateNotificationStatus(_ authorization: UNAuthorizationStatus) {
        notificationStatus = Self.authorizationName(authorization)
        notificationsAllowed = [.authorized, .provisional].contains(authorization)
    }
    static func authorizationName(_ value: UNAuthorizationStatus) -> String {
        switch value {
        case .notDetermined: return "Permission not requested"
        case .denied: return "Notifications denied in System Settings"
        case .authorized: return "Notifications allowed"
        case .provisional: return "Quiet notifications allowed"
        case .ephemeral: return "Temporary notifications allowed"
        @unknown default: return "Unknown notification status (\(value.rawValue))"
        }
    }
    func enableNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            Task { @MainActor in
                if let error { self.status = error.localizedDescription }
                self.refreshNotificationStatus()
            }
        }
    }
    func regenerateToken() {
        do {
            token = try InstallationToken.regenerate()
            ingress = EventIngress(token: token)
            copied = "Token regenerated. Install the updated snippets."
        } catch { status = "Cannot regenerate event token: \(error.localizedDescription)" }
    }
    var terminalTest: String {
        "open -g \"agentping://event?agent=Terminal&kind=waiting&title=Review%20test&project=&session=terminal-review&token=\(token)\""
    }
    func receive(_ url: URL) {
        guard !isShuttingDown else { return }
        guard let accepted = ingress.receive(url.absoluteString) else {
            history.reject()
            saveHistory()
            status = "Rejected: \(history.rejectedCount). Check the token and the 30 events/minute limit."
            return
        }
        history.receive(accepted.event)
        status = ""
        saveHistory()
        if accepted.shouldNotify && !isSample { notify(accepted.event) }
    }
    func sendTest() {
        let raw = "agentping://event?agent=RelayNook&kind=info&title=Test%20event&project=&session=agentping-test&token=\(token)"
        if let url = URL(string: raw) { receive(url) }
    }
    func saveHistory() {
        guard !isShuttingDown, !isSample else { return }
        persistence.submit(history)
    }
    func beginShutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        persistence.submit(liveHistory ?? history)
    }
    func flushHistory() async { await persistence.flush() }
    func clear() {
        guard !isShuttingDown else { return }
        history.clear(); saveHistory()
    }
    func dismissUnresolvedLegacySessions() {
        guard !isShuttingDown else { return }
        history.dismissUnresolvedLegacySessions(); saveHistory()
    }
    func savePreferences() {
        do {
            try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences).write(to: preferencesURL, options: .atomic)
        } catch { status = "Cannot save preferences: \(error.localizedDescription)" }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch { status = "Launch at login: \(error.localizedDescription)"; launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    func copy(_ text: String, name: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) { copied = "Copied \(name)" }
        else { copied = "Copy failed" }
    }
    private func notify(_ event: AgentEvent) {
        guard preferences.permits(event.kind) else { return }
        Task {
            let authorization = await notificationAuthorization()
            updateNotificationStatus(authorization)
            guard notificationsAllowed, preferences.permits(event.kind) else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(event.agent): \(event.kind.rawValue)"
            content.body = event.title + (event.project.isEmpty ? "" : "\n" + event.project)
            content.threadIdentifier = event.session
            if preferences.sound { content.sound = .default }
            do { try await notificationDelivery(UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)) }
            catch { status = "Notification: \(error.localizedDescription)" }
        }
    }
}
