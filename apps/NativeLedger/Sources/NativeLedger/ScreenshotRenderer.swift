import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import LedgerCore

/// Renders the store screenshots from the real window views, driven by the memory-only Sample.
/// It never opens the saved ledgers, never reads real apps and never creates bookmarks.
@MainActor enum ScreenshotRenderer {
    nonisolated static let canvas = CGSize(width: 1440, height: 900)
    nonisolated static let window = CGSize(width: 1240, height: 716)
    nonisolated static let titleBar: CGFloat = 52
    nonisolated static var content: CGSize { CGSize(width: window.width, height: window.height - titleBar) }

    struct Shot {
        let file: String
        let title: String
        let subtitle: String
        let label: String
    }
    static let shots = [
        Shot(file: "01-recent-changes.png", title: "See every app change in one feed",
             subtitle: "Watch your Applications folder. Recent changes lists the entries of the last seven days, newest at the top.",
             label: "Sample · synthetic ledgers"),
        Shot(file: "02-silent-rebuild.png", title: "Spot a silent rebuild",
             subtitle: "The executable hash changed while version 2.4 build 240 stayed the same. The entry is flagged.",
             label: "Sample · synthetic ledger"),
        Shot(file: "03-background-signature.png", title: "Catch new helpers and failed signatures",
             subtitle: "Entry 3 adds a background item and fails the macOS signature check. Each entry lists what it read.",
             label: "Sample · synthetic ledger"),
        Shot(file: "04-compare-macs.png", title: "Compare ledgers from two Mac computers",
             subtitle: "Open a ledger file exported on another Mac. See which apps match, which differ and which are missing.",
             label: "Sample · synthetic ledger file"),
        Shot(file: "05-verified-baseline.png", title: "Acknowledge and verify the chain",
             subtitle: "The acknowledgement is an entry in the chain. Verify chain recalculates every hash and finds it intact.",
             label: "Sample · synthetic ledger"),
    ]

    static func renderOrReport(to directory: URL) -> Int32 {
        do { try render(to: directory); return 0 }
        catch { fputs("Screenshot render failed: \(error.localizedDescription)\n", stderr); return 1 }
    }

    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = LedgerModel.sample()

        model.showRecentChanges()
        guard model.showingRecent, !model.recentChanges().isEmpty, !model.folders.isEmpty else { throw CocoaError(.featureUnsupported) }
        try write(shots[0], window: capture(LedgerSplitView(model: model, flat: true)), sample: true, to: directory)

        model.selection = SampleLedger.editorID
        try write(shots[1], window: capture(LedgerSplitView(model: model, flat: true, expandedEntries: [])), sample: true, to: directory)

        model.selection = SampleLedger.viewerID
        guard let viewer = model.ledger(SampleLedger.viewerID), let latest = viewer.latest,
              latest.anomalies.contains(.newBackgroundItem), latest.anomalies.contains(.signatureInvalid) else { throw CocoaError(.featureUnsupported) }
        try write(shots[2], window: capture(LedgerSplitView(model: model, flat: true, expandedEntries: [latest.seq],
                                                                         scrollToEntry: latest.seq)), sample: true, to: directory)

        model.selection = SampleLedger.editorID
        model.compareWithSampleFile()
        guard let comparison = model.comparison else { throw CocoaError(.fileReadCorruptFile) }
        let behind = capture(LedgerSplitView(model: model, flat: true, expandedEntries: []))
        let sheet = capture(CompareView(comparison: comparison), size: CGSize(width: 900, height: 470))
        try write(shots[3], window: behind, sheet: sheet, sample: true, to: directory)
        model.comparison = nil

        model.selection = SampleLedger.editorID
        model.acknowledgeImmediately(SampleLedger.editorID)
        guard model.ledger(SampleLedger.editorID)?.latest?.kind == .acknowledged,
              model.verify(SampleLedger.editorID)?.isIntact == true else { throw CocoaError(.featureUnsupported) }
        try write(shots[4], window: capture(LedgerSplitView(model: model, flat: true, expandedEntries: [])), sample: true, to: directory)
    }

    /// Draws an AppKit-hosted view into a 2x bitmap, so lists and controls render as they do on screen.
    static func capture<V: View>(_ view: V, size: CGSize = content) -> NSImage {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light).frame(width: size.width, height: size.height))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
        window.display()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func write(_ shot: Shot, window: NSImage, sheet: NSImage? = nil, sample: Bool, to directory: URL) throws {
        let canvasView = ScreenshotCanvas(shot: shot, window: window, sheet: sheet, sample: sample)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: canvasView)
        renderer.proposedSize = ProposedViewSize(canvas)
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.cgImage, image.width == 2880, image.height == 1800,
              let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
        let url = directory.appendingPathComponent(shot.file)
        guard let opaque = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, opaque, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// The store frame. The window chrome is drawn here because an offscreen view has no title bar or toolbar.
struct ScreenshotCanvas: View {
    let shot: ScreenshotRenderer.Shot
    let window: NSImage
    var sheet: NSImage?
    var sample: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.system(size: 15, weight: .bold))
                        Text("NativeLedger").font(.system(size: 16, weight: .semibold))
                    }.foregroundStyle(Palette.green)
                    Text(shot.title).font(.system(size: 42, weight: .semibold, design: .serif)).foregroundStyle(Color(white: 0.12))
                    Text(shot.subtitle).font(.system(size: 19)).foregroundStyle(Color(white: 0.32))
                        .frame(maxWidth: 900, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(shot.label.uppercased()).font(.system(size: 12.5, weight: .bold)).tracking(2.2)
                    .foregroundStyle(Palette.gold)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Palette.gold.opacity(0.14)))
                    .overlay(Capsule().stroke(Palette.gold.opacity(0.5)))
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 100)
            .frame(height: 166, alignment: .bottom)
            .padding(.bottom, 18)
            frame
            Spacer(minLength: 0)
        }
        .frame(width: ScreenshotRenderer.canvas.width, height: ScreenshotRenderer.canvas.height)
        .background(
            LinearGradient(colors: [Color(red: 0.97, green: 0.955, blue: 0.91), Color(red: 0.90, green: 0.93, blue: 0.89)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var frame: some View {
        VStack(spacing: 0) {
            chrome
            ZStack {
                Image(nsImage: window).resizable().interpolation(.high)
                    .frame(width: ScreenshotRenderer.content.width, height: ScreenshotRenderer.content.height)
                if let sheet {
                    Color.black.opacity(0.18)
                    Image(nsImage: sheet).resizable().interpolation(.high)
                        .frame(width: sheet.size.width, height: sheet.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 8)
                }
            }
            .frame(width: ScreenshotRenderer.content.width, height: ScreenshotRenderer.content.height)
            .clipped()
        }
        .frame(width: ScreenshotRenderer.window.width, height: ScreenshotRenderer.window.height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
    }

    private var chrome: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
            }.padding(.leading, 18)
            Text(sample ? "NativeLedger · Sample" : "NativeLedger").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(white: 0.2)).padding(.leading, 200)
            Spacer()
            HStack(spacing: 18) {
                tool("folder.badge.plus", "Watch a Folder", enabled: !sample)
                tool("plus.app", "Add App", enabled: !sample)
                tool("square.and.arrow.up", "Export Ledger", enabled: !sample)
                tool("arrow.left.arrow.right.square", "Compare with Ledger File", enabled: true)
            }.padding(.trailing, 18)
        }
        .frame(height: ScreenshotRenderer.titleBar)
        .background(Color(white: 0.965))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1) }
    }
    private func tool(_ symbol: String, _ title: String, enabled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
            Text(title).font(.system(size: 13))
        }
        .foregroundStyle(Color(white: enabled ? 0.22 : 0.62))
    }
}
