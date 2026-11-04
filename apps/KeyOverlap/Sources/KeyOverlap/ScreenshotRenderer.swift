import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum ScreenshotRenderer {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let specs = [
            (0, "01-scope-plan.png", "Catch conflicts before\nyou change shortcuts", "Compare global actions, separate apps and your own exclusive contexts in one local plan."),
            (1, "02-candidate-preview.png", "Check a candidate\nwithout changing records", "Preview the exact chord and app scope against your saved baseline. Your plan stays separate."),
            (2, "03-change-plan.png", "Turn overlaps into\na clearer plan", "Stage replacements, compare before and after, then copy a checklist for manual setup.")
        ]
        for (tab, filename, title, subtitle) in specs {
            let model = AppModel(screenshot: true); model.toggleSample(true); model.tab = tab
            let host = NSHostingView(rootView: ContentView(model: model).environment(\.colorScheme, .dark))
            host.frame = NSRect(x: 0, y: 0, width: 940, height: 740)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.display(); host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let capture = NSImage(size: host.bounds.size); capture.addRepresentation(bitmap)
            let renderer = ImageRenderer(content: StoreScreenshot(capture: capture, title: title, subtitle: subtitle).environment(\.colorScheme, .dark))
            renderer.proposedSize = ProposedViewSize(width: 1440, height: 900); renderer.scale = 2; renderer.isOpaque = true
            guard let image = renderer.cgImage, image.width == 2880, image.height == 1800,
                  let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
            context.setFillColor(CGColor(red: 0.025, green: 0.075, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
            guard let opaque = context.makeImage(), let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, opaque, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            window.close()
        }
    }
}
struct StoreScreenshot: View {
    let capture: NSImage
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 35) {
            VStack(alignment: .leading, spacing: 26) {
                Text("KeyOverlap").font(.system(size: 23, weight: .semibold)).foregroundStyle(.teal)
                Text(title).font(.system(size: 43, weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 21)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                Text("Sample").font(.system(size: 14, weight: .semibold)).tracking(3).foregroundStyle(.teal)
            }.frame(width: 365, alignment: .leading)
            Image(nsImage: capture).frame(width: 940, height: 740).background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12)))
        }.frame(width: 1440, height: 900).background(LinearGradient(colors: [Color(red: 0.025, green: 0.06, blue: 0.095), Color(red: 0.035, green: 0.13, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
