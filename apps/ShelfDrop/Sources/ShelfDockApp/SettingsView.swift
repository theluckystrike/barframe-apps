import SwiftUI
import AppKit
import ServiceManagement
import ShelfDockCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var login = LoginStatusModel()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch ShelfDock at login", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.setEnabled($0) }))
                if let message = login.message { Text(message).font(.caption).foregroundStyle(.orange) }
                Toggle("Clear items after drag out", isOn: Binding(
                    get: { model.store.clearAfterDragOut },
                    set: { model.store.clearAfterDragOut = $0 }))
                Toggle("Show sample shelf", isOn: Binding(
                    get: { model.isSample },
                    set: { model.setSample($0) }))
            }
            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Items on shelf", value: "\(model.store.items.count)")
            }
            Section("Links") {
                ShelfLinksView(model: model)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

@MainActor
final class LoginStatusModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?
    private var failure: String?
    private let status: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    init(status: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status }, register: @escaping () throws -> Void = { try SMAppService.mainApp.register() }, unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.status = status; self.register = register; self.unregister = unregister; refresh()
    }
    func refresh() {
        let current = status()
        isEnabled = current == .enabled || current == .requiresApproval
        if current == .requiresApproval { message = "Approve ShelfDock in System Settings → General → Login Items." }
        else if current == .enabled { failure = nil; message = nil }
        else { message = failure }
    }
    func setEnabled(_ on: Bool) {
        do { if on { try register() } else { try unregister() }; failure = nil }
        catch { failure = "Could not update login item: " + error.localizedDescription }
        refresh()
    }
}
