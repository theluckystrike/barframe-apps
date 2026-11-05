import AppKit
import SwiftUI
import CronSpindleCore
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum ScreenshotRenderer {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = Model()
        model.toggleSample(true)
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

    private static func shotSpecs(model: Model) -> [(AnyView, String, String, String)] {
        let proposal=Model(); proposal.toggleSample(true)
        proposal.result=try? Planner.analyze(Fixtures.jobs,start:Fixtures.start,days:1)
        proposal.days=1; proposal.expression="0 4 * * *"
        var revised=Fixtures.jobs; revised[1].expression=proposal.expression
        proposal.proposed=try? Planner.analyze(revised,start:Fixtures.start,days:1)
        proposal.busy=false; proposal.stale=false
        let dst=Model(); dst.toggleSample(true); dst.jobs=Fixtures.dst; dst.start=Fixtures.autumn; dst.days=1
        dst.result=try? Planner.analyze(Fixtures.dst,start:Fixtures.autumn,days:1); dst.proposed=nil; dst.busy=false; dst.stale=false; dst.select(Fixtures.dst[0])
        model.result=try? Planner.analyze(Fixtures.jobs,start:Fixtures.start,days:1); model.busy=false; model.stale=false
        return [
            (AnyView(ContentView(model:model).frame(width:870)), "01-contention.png", "Find conflicts before work begins", "Compare scheduled work using your expected durations and shared resources."),
            (AnyView(ContentView(model:proposal).frame(width:870)), "02-proposal.png", "Preview changes before saving them", "See which contention windows a proposed schedule adds or removes."),
            (AnyView(ContentView(model:dst).frame(width:870)), "03-repeated-hour.png", "See repeated hours as instants", "Inspect local times with explicit UTC offsets across daylight saving transitions.")
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
                Text("CronSpindle").font(.system(size: 23, weight: .semibold)).foregroundStyle(.cyan)
                Text(title).font(.system(size: 49, weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                Text("Sample · planning fixtures").font(.system(size: 13, weight: .medium)).tracking(4).foregroundStyle(.white.opacity(0.45))
            }.frame(width: 405, alignment: .leading)
            Image(nsImage: capture).frame(width: capture.size.width, height: capture.size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.12)))
        }.frame(width: 1440, height: 900)
            .background(LinearGradient(colors: [Color(red: 12/255, green: 17/255, blue: 27/255), Color(red: 14/255, green: 26/255, blue: 30/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
