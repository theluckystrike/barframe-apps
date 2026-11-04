import AppKit
import SwiftUI

/// Renders Mac App Store screenshots (2880 x 1800, 16:10) from a live SwiftUI view.
/// Output goes to NSHomeDirectory()/screenshots/, which is inside the sandbox container.
@MainActor
enum QuotaPaceScreenshotComposer {
    static let size = CGSize(width: 2880, height: 1800)

    /// Composes one store screenshot: headline, subheadline, and the popover view on a
    /// menu-bar-style canvas. Returns the written PNG URL.
    @discardableResult
    static func render<Content: View>(
        index: Int,
        headline: String,
        subheadline: String,
        accent: Color,
        popoverWidth: CGFloat = 360,
        @ViewBuilder content: () -> Content
    ) throws -> URL {
        let canvas = QuotaPaceStoreCanvas(
            headline: headline,
            subheadline: subheadline,
            accent: accent,
            popoverWidth: popoverWidth,
            popover: AnyView(content())
        )
        .frame(width: size.width / 2, height: size.height / 2)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let rendered = renderer.cgImage,
              let png = opaquePNG(rendered) else {
            throw ScreenshotError.renderFailed
        }
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(String(format: "screenshot-%02d.png", index))
        try png.write(to: url, options: .atomic)
        return url
    }

    enum ScreenshotError: Error { case renderFailed }

    /// App Store Connect rejects screenshots with an alpha channel ("Images can't include
    /// alpha channels"). Redraw into an opaque RGB context (noneSkipLast) before encoding.
    static func opaquePNG(_ image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let flat = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: flat)
        return rep.representation(using: .png, properties: [:])
    }
}

private struct QuotaPaceStoreCanvas: View {
    let headline: String
    let subheadline: String
    let accent: Color
    let popoverWidth: CGFloat
    let popover: AnyView

    /// Layout: text column left (42 %), live interface right at its production size. Canvas is 1440 x 900 pt, rendered at 2x.
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.9), accent.opacity(0.45), Color(white: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.35)).frame(height: 24)
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 60) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(headline)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subheadline)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 520, alignment: .leading)
                popover
                    .frame(width: popoverWidth)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .environment(\.colorScheme, .dark)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                    .frame(width: popoverWidth)
            }
            .padding(.top, 24)
        }
    }
}
