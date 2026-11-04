import AppKit
import SwiftUI
import HushKeyCore

/// Capture the same views at their intrinsic window dimensions; no alternate controls.
@MainActor enum ScreenshotRenderer {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "HushKey-screenshot-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "sampleMode")
        let model = AppModel(live: SampleDevices(), defaults: defaults)
        model.start()
        try capture(ControlsView(model: model), title: "See your microphone mute state", name: "01-menu-mic-state", to: directory)
        try capture(SettingsView(model: model), title: "Choose your own global shortcut", name: "02-settings-shortcut", to: directory)
        model.setPushToTalk(true)
        model.beginPushToTalk()
        try capture(ControlsView(model: model), title: "Hold to talk release to mute", name: "03-badge-push-to-talk", to: directory)
        model.endPushToTalk()
    }

    private static func capture<V: View>(_ view: V, title: String, name: String, to directory: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        window.display(); host.layoutSubtreeIfNeeded()
        guard size.height < 800, let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: size); image.addRepresentation(bitmap)
        let content = HStack(spacing: 72) {
            VStack(alignment: .leading, spacing: 24) {
                Text("HushKey").font(.system(size: 24, weight: .semibold)).foregroundStyle(.mint)
                Text(title).font(.system(size: 48, weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text("Sample").font(.system(size: 20)).foregroundStyle(.white.opacity(0.75))
            }.frame(width: 440, alignment: .leading)
            Image(nsImage: image).frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.frame(width: 1440, height: 900)
            .background(Color(red: 0.06, green: 0.10, blue: 0.22))
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .light))
        renderer.scale = 2; renderer.isOpaque = true
        guard let cgImage = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.orderOut(nil)
    }
}
