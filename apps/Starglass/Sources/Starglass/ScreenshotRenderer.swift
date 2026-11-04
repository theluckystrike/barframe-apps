import AppKit
import SwiftUI
import StarglassCore
import ImageIO
import UniformTypeIdentifiers

@MainActor enum ScreenshotRenderer {
    /// Renders three native 2880x1800 screenshots of the live panel (Sample mode).
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(start: false)
        model.enterSample()

        func capture(_ width: CGFloat, _ height: CGFloat) throws -> NSImage {
            let host = NSHostingView(rootView: ContentView(model: model).environment(\.colorScheme, .dark))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(bitmap)
            return image
        }

        let shots: [(CGFloat, CGFloat, String, String, String)] = [
            (480, 300, "01-tonight-score.png", "See tonight’s stargazing score instantly",
             "See tonight's score, cloud cover and moon light for your saved city."),
            (480, 340, "02-timeline.png", "See clouds through the dark window",
             "See hourly cloud cover during the astronomical dark window."),
            (480, 420, "03-seven-nights.png", "Best night of\nthe next seven",
             "Compare the next seven nights and plan around the clearest, darkest one."),
        ]
        for (w, h, file, title, subtitle) in shots {
            let panel = try capture(w, h)
            let renderer = ImageRenderer(content: ScreenshotView(capture: panel, title: title, subtitle: subtitle)
                .environment(\.colorScheme, .dark))
            renderer.proposedSize = ProposedViewSize(width: 1440, height: 900)
            renderer.scale = 2
            renderer.isOpaque = true
            guard let image = renderer.cgImage, image.width == 2880, image.height == 1800,
                  let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw CocoaError(.fileWriteUnknown)
            }
            context.setFillColor(CGColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
            guard let opaque = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(file) as CFURL,
                    UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, opaque, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        }
    }
}

struct ScreenshotView: View {
    let capture: NSImage
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Starglass").font(.system(size: 23, weight: .semibold)).foregroundStyle(.cyan)
                Text(title).font(.system(size: 49, weight: .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sample · example forecast").font(.system(size: 13, weight: .medium)).tracking(4)
                    .foregroundStyle(.white.opacity(0.45))
            }.frame(width: 470, alignment: .leading)
            Image(nsImage: capture)
                .frame(width: capture.size.width, height: capture.size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.12)))
        }.frame(width: 1440, height: 900)
            .background(LinearGradient(colors: [Color(red: 8/255, green: 10/255, blue: 24/255),
                                                Color(red: 16/255, green: 24/255, blue: 48/255)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
