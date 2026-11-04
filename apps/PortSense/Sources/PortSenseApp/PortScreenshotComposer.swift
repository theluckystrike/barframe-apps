import AppKit
import SwiftUI

/// Compose the normal, scrolling Sample panel at its native point size.
@MainActor enum PortScreenshotComposer {
    static func panelScale(width: Double, height: Double) -> Double {
        min(1, 740 / max(1, height), 680 / max(1, width))
    }
    @discardableResult static func render<Content: View>(index: Int, headline: String, subheadline: String,
        accent: Color, @ViewBuilder content: () -> Content) throws -> URL {
        let panelImage = try capturePanel(content: content)
        let width = Double(panelImage.width) / 2
        let height = Double(panelImage.height) / 2
        let scale = panelScale(width: width, height: height)
        let canvas = ZStack {
            LinearGradient(colors: [accent.opacity(0.8), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.3)).frame(height: 24)
                Spacer(minLength: 0)
            }
            HStack(spacing: 60) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(headline).font(.system(size: 60, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(subheadline).font(.system(size: 26, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                }.frame(width: 520, alignment: .leading)
                Image(decorative: panelImage, scale: 2).resizable()
                    .frame(width: width * scale, height: height * scale)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
            }
        }.frame(width: 1440, height: 900)
        let renderer = ImageRenderer(content: canvas); renderer.scale = 2
        guard let image = renderer.cgImage, let png = opaquePNG(image) else { throw RenderError.failed }
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(String(format: "screenshot-%02d.png", index))
        try png.write(to: file, options: .atomic)
        return file
    }
    /// NSHostingView captures AppKit-backed ScrollView content that ImageRenderer omits.
    static func capturePanel<Content: View>(@ViewBuilder content: () -> Content) throws -> CGImage {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: content().frame(width: 360)
            .environment(\.colorScheme, .dark)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14)))
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw RenderError.failed }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let image = rep.cgImage else { throw RenderError.failed }
        return image
    }
    private static func opaquePNG(_ image: CGImage) -> Data? {
        guard let color = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: color, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:])
    }
    enum RenderError: Error { case failed }
}
