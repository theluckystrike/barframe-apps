import SwiftUI
import AppKit
import ShelfDockCore

/// Capture the live native view at its real 400 × 560 point dimensions.
@MainActor
enum ShelfScreenshotComposer {
    static let shots: [(String, String)] = [
        ("Keep every drop within reach", "Files, full text, and images on your open shelf."),
        ("Organize your shelf into groups", "All includes every item. Design keeps a focused selection."),
        ("Find the item you need", "Filter by name, then drag, copy, share, or preview.")
    ]
    static func renderAll() throws -> [URL] {
        NSApp.appearance = NSAppearance(named: .aqua)
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (index, shot) in shots.enumerated() {
            let model = AppModel(loadSample: true, liveStore: ShelfStore(defaults: nil))
            if index == 1 { model.selectedGroupID = model.store.groups[1].id }
            if index == 2 { model.query = "photo" }
            let host = NSHostingView(rootView: ContentView(model: model).environment(\.colorScheme, .light))
            host.frame = NSRect(x: 0, y: 0, width: 400, height: 560)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; window.display(); host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let capture = NSImage(size: host.bounds.size); capture.addRepresentation(bitmap)
            let canvas = ShelfStoreCanvas(capture: capture, headline: shot.0, detail: shot.1).frame(width: 1440, height: 900)
            let renderer = ImageRenderer(content: canvas); renderer.scale = 2; renderer.isOpaque = true
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
            guard let flat = context.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            let url = directory.appendingPathComponent(String(format: "screenshot-%02d.png", index + 1))
            try png.write(to: url); urls.append(url); window.close()
        }
        return urls
    }
}
private struct ShelfStoreCanvas: View {
    let capture: NSImage
    let headline: String
    let detail: String
    var body: some View {
        HStack(spacing: 100) {
            VStack(alignment: .leading, spacing: 24) {
                Text("ShelfDock").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.blue)
                Text(headline).font(.system(size: 54, weight: .bold)).foregroundStyle(Color(white: 0.12)).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.system(size: 24)).foregroundStyle(Color(white: 0.35)).fixedSize(horizontal: false, vertical: true)
                Text("Sample · bundled examples").font(.system(size: 16, weight: .medium)).foregroundStyle(Color(white: 0.4))
            }.frame(width: 520, alignment: .leading)
            Image(nsImage: capture).resizable().frame(width: 400, height: 560)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.18)))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        }.frame(width: 1440, height: 900)
            .background(LinearGradient(colors: [Color(red: 0.9, green: 0.95, blue: 1), .white], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
