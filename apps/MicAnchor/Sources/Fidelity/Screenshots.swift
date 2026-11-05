import AppKit
import SwiftUI
import FidelityCore

// Capture the shipping views through AppKit, including native Form controls.
@MainActor func captureNativeView<V: View>(_ content: V, size: CGSize) throws -> NSImage {
    _ = NSApplication.shared
    let view = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
    let size = CGSize(width: size.width, height: size.height > 0 ? size.height : view.fittingSize.height)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = view
    window.setContentSize(size)
    view.frame = CGRect(origin: .zero, size: size)
    window.orderFront(nil)
    defer { window.orderOut(nil); window.close() }
    // Native controls settle through the same layout/display cycle as normal UI.
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw NSError(domain: "MicAnchor.Screenshots", code: 1)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let image = NSImage(size: size)
    image.addRepresentation(bitmap)
    return image
}

private struct ScreenshotPage: View {
    let interface: NSImage
    let page: Int
    static let headlines = ["Restore your preferred system microphone", "Choose microphones in priority order", "Review each confirmed input change"]
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.10, blue: 0.12)
            HStack(spacing: 90) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("MICANCHOR").font(.system(size: 18, weight: .bold)).foregroundStyle(.mint)
                    Text(Self.headlines[page]).font(.system(size: 52, weight: .semibold)).foregroundStyle(.white)
                    Text("Sample · simulated devices").font(.system(size: 22)).foregroundStyle(.mint)
                    Text(page == 0 ? "Bluetooth takeover detected.\nDefault input restored to a separate mic." : page == 1 ? "Saved preferences survive disconnects.\nUnavailable inputs use a safe fallback." : "Only confirmed switches are recorded.\nKeep the last 20 or clear history.")
                        .font(.system(size: 24)).foregroundStyle(.white.opacity(0.8))
                }.frame(width: 580, alignment: .leading)
                Image(nsImage: interface).frame(width: interface.size.width, height: interface.size.height)
            }.padding(60)
        }.frame(width: 1440, height: 900).environment(\.colorScheme, .dark)
    }
}

@MainActor func renderScreenshots(to path: String) throws {
    let hardware = SampleHardware()
    let suite = "MicAnchor.Screenshots." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var time = Date(timeIntervalSince1970: 1780308000)
    let model = GuardModel(hardware: hardware, defaults: defaults, now: { time }, scheduleEvents: false)
    model.dismissIntroduction()
    model.refresh(enforce: true)
    let directory = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for page in 0..<3 {
        let interface: NSImage
        if page == 0 {
            interface = try captureNativeView(GuardPopover(model: model, sampleSession: true), size: CGSize(width: 440, height: 0))
        } else {
            model.clearHistory()
            if page == 1 { model.setPriorities(["sample-1", "sample-2", "sample-3"]) }
            else {
                model.setPriorities([])
                for _ in 0..<3 { time = time.addingTimeInterval(60); hardware.input = 12; model.refresh(enforce: true) }
            }
            interface = try captureNativeView(GuardSettingsView(model: model, sampleSession: true),
                size: CGSize(width: GuardSettingsView.width, height: GuardSettingsView.height))
        }
        let renderer = ImageRenderer(content: ScreenshotPage(interface: interface, page: page))
        renderer.scale = 2; renderer.isOpaque = true
        guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw NSError(domain: "MicAnchor", code: 1) }
        try data.write(to: directory.appendingPathComponent("0\(page + 1)-feature.png"))
    }
}
