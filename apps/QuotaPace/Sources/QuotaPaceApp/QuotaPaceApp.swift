import SwiftUI
import MASKit
import QuotaPaceCore

@main
struct QuotaPaceApp: App {
    private static let launchMode = LaunchMode.current()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    init() { _ = Self.launchMode }
    var body: some Scene {
        MenuBarExtra(isInserted: .constant(Self.launchMode == .normal)) {
            PopoverView(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "speedometer").renderingMode(.template).font(.system(size: 16))
                if !model.menuValue.isEmpty { Text(model.menuValue).monospacedDigit() }
            }.accessibilityLabel("QuotaPace \(model.menuValue)")
                .onAppear { if Self.launchMode == .normal { delegate.model = model; model.start() } }
        }.menuBarExtraStyle(.window)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        switch LaunchMode.current() {
        case .normal: break
        case .smoke: SmokeRunner.run()
        case .screenshots:
            Task { @MainActor in
                do { try await renderScreenshots(); exit(0) }
                catch { NSLog("QuotaPace screenshot error: %@", error.localizedDescription); exit(1) }
            }
        }
    }
    @MainActor private func renderScreenshots() async throws {
        let model = AppModel(sampleMode: true)
        try model.loadSampleData()
        let usage = try await NativeSnapshot.image(view: PopoverView(model: model), width: 360)
        try QuotaPaceScreenshotComposer.render(index: 1, headline: "Keep your token pace in view", subheadline: "Sample data · rolling five-hour and seven-day usage", accent: QuotaPaceBrand.accent) { Image(nsImage: usage) }
        let settings = try await SettingsSnapshot.image(model: model)
        try QuotaPaceScreenshotComposer.render(index: 2, headline: "Set budgets for each window", subheadline: "Sample data · limits you can change in Settings", accent: QuotaPaceBrand.accent, popoverWidth: 480) { Image(nsImage: settings) }
        model.selected = .codex
        model.saveLimits(Limits(fiveHours: 15_000_000, sevenDays: 200_000_000), for: .codex)
        let pace = try await NativeSnapshot.image(view: PaceDetailsView(model: model), width: 360, height: 480)
        try QuotaPaceScreenshotComposer.render(index: 3, headline: "Plan around your observed pace", subheadline: "Sample data · forecast with rolling event expiry", accent: QuotaPaceBrand.accent) { Image(nsImage: pace) }
    }
}
