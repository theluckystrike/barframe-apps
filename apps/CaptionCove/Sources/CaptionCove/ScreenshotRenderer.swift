import AppKit
import SwiftUI
import CaptionCoveCore
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum ScreenshotRenderer {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferences=["language","appearance"]
        let previous=preferences.map { UserDefaults.standard.object(forKey:$0) }
        defer { for (key,value) in zip(preferences,previous) { if let value { UserDefaults.standard.set(value,forKey:key) } else { UserDefaults.standard.removeObject(forKey:key) } } }
        let model = AppModel()
        model.language="en"; model.appearance="dark"
        model.sampleMode=true
        model.previews=Dictionary(([ ("Reference", Samples.reference) ]+Samples.languages).map { ($0.0,SRTParser.parse($0.1)) },uniquingKeysWith: { a,_ in a })
        model.sampleResult=Comparator.scan(reference:SRTParser.parse(Samples.reference),languages:Samples.languages.map{($0.0,SRTParser.parse($0.1))},sample:true)
        model.selected="Spanish"
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
        let detail=AppModel()
        detail.language="en"; detail.appearance="dark"
        detail.sampleMode=true; detail.sampleResult=model.sampleResult; detail.previews=model.previews; detail.selected="French"
        return [
            (AnyView(ContentView(model:model).frame(width:960,height:760)), "01-delivery-matrix.png",
             "Catch gaps across\nevery language delivery",
             "Compare cue IDs across a reference and each language. Missing cues stay separate from text and overlap warnings."),
            (AnyView(ContentView(model:detail).frame(width:960,height:760)), "02-timing-detail.png",
             "Find timing drift\nbefore final delivery",
             "Review signed start and end differences against your own tolerance. Read a short local text preview for context."),
            (AnyView(SettingsView(model:model,advanced:true)), "03-local-rules.png",
             "Set rules for\neach subtitle review",
             "Adjust timing tolerance, text speed and overlap warnings. Sample rules stay separate from your Live project.")
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
                Text("CaptionCove").font(.system(size: 23, weight: .semibold)).foregroundStyle(.cyan)
                Text(title).font(.system(size: 49, weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                Text("Sample · synthetic subtitle fixtures").font(.system(size: 13, weight: .medium)).tracking(4).foregroundStyle(.white.opacity(0.45))
            }.frame(width: 405, alignment: .leading)
            Image(nsImage: capture).frame(width: capture.size.width, height: capture.size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.12)))
        }.frame(width: 1440, height: 900)
            .background(LinearGradient(colors: [Color(red: 12/255, green: 17/255, blue: 27/255), Color(red: 14/255, green: 26/255, blue: 30/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
