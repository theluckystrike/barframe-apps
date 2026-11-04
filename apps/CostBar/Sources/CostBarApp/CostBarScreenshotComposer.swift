import AppKit
import SwiftUI

/// 1440 by 900 points at Retina scale: the production popover remains exactly 360 points wide.
@MainActor
enum CostBarScreenshotComposer {
    static func render<Content: View>(index: Int, headline: String, subheadline: String,
                                     accent: Color, @ViewBuilder content: () -> Content) throws {
        let canvas = ZStack {
            LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.45), Color(white: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .center, spacing: 100) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(headline).font(.system(size: 58, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(subheadline).font(.system(size: 26, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                }.frame(width: 560, alignment: .leading)
                content().fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            }
        }.frame(width: 1440, height: 900)
        try write(canvas: canvas, index: index)
    }

    /// Render the actual accounts window with AppKit. ImageRenderer alone does not reliably
    /// paint the native scrolling/list views used by AccountsView.
    static func renderAccounts<Content: View>(index: Int, headline: String, subheadline: String,
                                             accent: Color, @ViewBuilder content: () -> Content) throws {
        let size = NSSize(width: 1320, height: 760)
        let hosting = NSHostingView(rootView: content().background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        // Give AppKit a real backing window, without activating the app or changing keyboard focus.
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw CocoaError(.fileWriteUnknown) }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let nativeImage = NSImage(size: size)
        nativeImage.addRepresentation(bitmap)
        let canvas = ZStack {
            LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.45), Color(white: 0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(headline).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(subheadline).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.95))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(nsImage: nativeImage).resizable().interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            }.frame(width: size.width)
        }.frame(width: 1440, height: 900)
        try write(canvas: canvas, index: index)
    }

    private static func write<Content: View>(canvas: Content, index: Int) throws {
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let rendered = renderer.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(String(format: "screenshot-%02d.png", index)), options: .atomic)
    }
}
