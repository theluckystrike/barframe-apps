import AppKit
import SwiftUI
import RevPulseCore

/// Capture the actual native views before composing text around their bitmaps.
@MainActor enum NativeScreenshots {
    static func render() async throws {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let defaults = UserDefaults(suiteName: "revpulse.screenshot")!
        defaults.removePersistentDomain(forName: "revpulse.screenshot")
        let model = AppModel(defaults: defaults, keyStore: KeyStore(service: "revpulse.screenshot"), start: false, loginStatus: false)
        model.loadSample()
        let args = ProcessInfo.processInfo.arguments
        let outputIndex = args.firstIndex(of: "--screenshot-output")
        let directory = outputIndex.flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 1...3 {
            let content: AnyView = index == 3 ? AnyView(SettingsView(model: model)) : AnyView(PopoverView(model: model))
            let host = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
            let size = index == 3 ? NSSize(width: 420, height: 720) : NSSize(width: 320, height: host.fittingSize.height)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .windowBackgroundColor
            host.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: 100, y: 100))
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            window.display()
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let capture = NSImage(size: size); capture.addRepresentation(bitmap)
            window.orderOut(nil)
            let headlines = ["Today's net payments at a glance", "Track your weekly payment rhythm", "Control refresh and local alerts"]
            let captions = ["Net payment movements in the menu bar", "Daily trend and monthly goal progress", "Sample mode needs no credentials"]
            let canvas = ScreenshotCanvas(capture: capture, title: headlines[index - 1], subtitle: captions[index - 1])
            let renderer = ImageRenderer(content: canvas)
            renderer.proposedSize = ProposedViewSize(width: 1440, height: 900)
            renderer.scale = 2; renderer.isOpaque = true
            guard let image = renderer.cgImage,
                  let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
            context.setFillColor(CGColor(gray: 0.08, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
            guard let opaque = context.makeImage(), let png = NSBitmapImageRep(cgImage: opaque).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: directory.appendingPathComponent(String(format: "screenshot-%02d.png", index)))
        }
    }
}
private struct ScreenshotCanvas: View {
    let capture: NSImage
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 100) {
            VStack(alignment: .leading, spacing: 24) {
                Text("RevPulse").font(.system(size: 26, weight: .semibold)).foregroundStyle(.mint)
                Text(title).font(.system(size: 52, weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 24)).foregroundStyle(.white.opacity(0.75))
                Text("Sample data").font(.system(size: 17)).foregroundStyle(.mint)
            }.frame(width: 500, alignment: .leading)
            // One point per interface point; no scaling or alternate layout.
            Image(nsImage: capture).resizable().frame(width: capture.size.width, height: capture.size.height)
                .background(Color(nsColor: .windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.frame(width: 1440, height: 900)
        .background(LinearGradient(colors: [Color(red: 0.08, green: 0.18, blue: 0.19), Color(red: 0.06, green: 0.07, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
