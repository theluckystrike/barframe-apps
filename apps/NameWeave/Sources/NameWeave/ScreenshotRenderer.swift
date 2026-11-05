import AppKit
import SwiftUI
import NameWeaveCore
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum ScreenshotRenderer {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel()
        model.toggleSample(true)
        model.shortcutKey = ""
        for (content, file, title, subtitle) in shotSpecs(model: model) {
            let host = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
            host.frame = NSRect(x: 0, y: 0, width: host.fittingSize.width, height: host.fittingSize.height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.display()
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let capture = NSImage(size: host.bounds.size)
            capture.addRepresentation(bitmap)
            let renderer = ImageRenderer(content: ScreenshotView(capture: capture, title: title, subtitle: subtitle).environment(\.colorScheme, .dark))
            renderer.proposedSize = ProposedViewSize(width: 1440, height: 900)
            renderer.scale = 2
            renderer.isOpaque = true
            guard let image = renderer.cgImage, image.width == 2880, image.height == 1800,
                  let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
            context.setFillColor(CGColor(red: 0.055, green: 0.071, blue: 0.110, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
            guard let opaque = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(file) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, opaque, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        }
    }

    private static func shotSpecs(model: AppModel) -> [(AnyView, String, String, String)] {
        [
            (AnyView(ContentView(model: model).frame(width: 1050, height: 730)), "01-source-risks.png",
             "Catch conflicts before your folder handoff",
             "Review reserved names and portability risks across a whole tree before sharing."),
            (AnyView(ContentView(model: resolvedModel()).frame(width: 1050, height: 730)), "02-repair-plan.png",
             "Test every replacement across the tree",
             "Resolve repair collisions and preview child paths when a parent name changes."),
            (AnyView(SettingsView(model: model)), "03-destination-policy.png",
             "Choose the destination rules that matter",
             "Set a compatibility target and explore Sample without granting folder access.")
        ]
    }
    private static func resolvedModel() -> AppModel { let m = AppModel(); m.toggleSample(true); m.shortcutKey = ""; m.resolve(); return m }
}

struct ScreenshotView: View {
    let capture: NSImage
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 24) {
                Text("NameWeave").font(.system(size: 23, weight: .semibold)).foregroundStyle(.cyan)
                Text(title).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 18)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                Text("Sample synthetic handoff names").font(.system(size: 13, weight: .medium)).tracking(1).foregroundStyle(.white.opacity(0.45))
            }.frame(width: 290, alignment: .leading)
            Image(nsImage: capture).frame(width: capture.size.width, height: capture.size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.12)))
        }.frame(width: 1440, height: 900)
            .background(LinearGradient(colors: [Color(red: 12/255, green: 17/255, blue: 27/255), Color(red: 14/255, green: 26/255, blue: 30/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
