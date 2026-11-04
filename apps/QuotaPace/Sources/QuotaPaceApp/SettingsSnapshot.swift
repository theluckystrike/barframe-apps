import AppKit
import SwiftUI

/// Capture production views, including AppKit controls, at 2x Retina resolution.
@MainActor
enum NativeSnapshot {
    static func image<Content: View>(view: Content, width: CGFloat, height: CGFloat? = nil) async throws -> NSImage {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let bounds = NSRect(x: 0, y: 0, width: width, height: height ?? host.fittingSize.height)
        host.frame = bounds
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: bounds.width, height: bounds.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(nanoseconds: 200_000_000)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CocoaError(.coderInvalidValue)
        }
        bitmap.size = bounds.size
        host.cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
enum SettingsSnapshot {
    static func image(model: AppModel) async throws -> NSImage {
        try await NativeSnapshot.image(view: SettingsView(model: model).tint(QuotaPaceBrand.accent), width: 480, height: 530)
    }
}
