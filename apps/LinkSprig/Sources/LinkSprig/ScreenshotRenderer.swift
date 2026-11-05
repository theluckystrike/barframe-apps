import AppKit
import SwiftUI
import LinkSprigCore
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum ScreenshotRenderer {
    static func render() throws {
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(persistent: false)
        model.setSample(true)
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
            (AnyView(ContentView(model: model).frame(width: 820, height: 640)), "01-move-preview.png",
             "Preview links before moving documents",
             "See incoming and outgoing link changes before changing a documentation tree."),
            (AnyView(PanelView(model: model, openWindow: {})), "02-change-plan.png",
             "Monitor changes from the menu bar",
             "Keep affected link counts and the last check time close at hand."),
            (AnyView(SettingsView(model: model)), "03-settings.png",
             "Read your docs without changing files",
             "Choose read access, review Sample and set a shortcut. Processing stays on your computer."),
        ]
    }
}

struct ScreenshotView: View {
    let capture: NSImage
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 24) {
                Text("LinkSprig").font(.system(size: 23, weight: .semibold)).foregroundStyle(.cyan)
                Text(title).font(.system(size: 49, weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                Text("Sample · example documents").font(.system(size: 13, weight: .medium)).tracking(4).foregroundStyle(.white.opacity(0.45))
            }.frame(width: 405, alignment: .leading)
            Image(nsImage: capture).frame(width: capture.size.width, height: capture.size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.12)))
        }.frame(width: 1440, height: 900)
            .background(LinearGradient(colors: [Color(red: 12/255, green: 17/255, blue: 27/255), Color(red: 14/255, green: 26/255, blue: 30/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
