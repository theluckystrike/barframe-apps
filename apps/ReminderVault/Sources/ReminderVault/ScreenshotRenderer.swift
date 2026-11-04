import AppKit
import SwiftUI
import VaultCore
import ImageIO
import UniformTypeIdentifiers

@MainActor enum ScreenshotRenderer {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Remove only the retired screenshot filename; otherwise the builder copies it back.
        let retired = directory.appendingPathComponent("03-complete.png")
        if FileManager.default.fileExists(atPath: retired.path) { try FileManager.default.removeItem(at: retired) }
        let model = AppModel(start: false)
        model.sample = true; model.folderName = "Sample vault"; model.lastSync = "9.41 AM"
        let sampleText = try String(contentsOf: SampleVault.url!)
        model.rows = TaskText.parse(sampleText).map { Row(id: UUID().uuidString, file: URL(fileURLWithPath: "/Sample/Today.md"), line: $0.line, value: $0.value) }
        for (index, file, title, subtitle) in [
            (0, "01-today.png", "Bring your tasks\ninto focus", "See today’s Markdown tasks and check them off from your menu bar."),
            (1, "02-preview.png", "Review each change\nbefore syncing", "Start with a dry-run preview of your selected vault and reminder lists."),
            (2, "03-settings.png", "Review conflicts before\nyour next sync", "See which edit won and which missing tasks need manual review.")
        ] {
            model.approval.invalidate()
            if index == 1 { model.approval.previewSucceeded() }
            model.conflictLog = index == 2 ? [
                "Sample · Vault → Reminders. Draft release notes · newest edit wins (file time versus reminder time)",
                "Sample · Manual review. Counterpart missing for Review project outline · deletion not propagated"
            ] : []
            model.status = index == 1 ? "Sample · Preview ready. Nothing has been written." : "Sample · Your local example vault is ready."
            model.actions = model.rows.map { Action(id: $0.id, file: $0.file, line: $0.line, value: $0.value, reminderID: nil, writeRemote: false, summary: "Sample link. " + $0.value.title, conflict: false, review: TaskReview(file: "Today.md", list: "Sample (no live list)", taskID: $0.id, vaultBefore: $0.value, reminderBefore: nil, proposed: $0.value)) }
            // Capture the same live view, dimensions and Sample records used by the menu panel.
            let view = index == 2 ? AnyView(SettingsView(model: model)) : AnyView(ContentView(model: model))
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
            // Use each live view's intrinsic size. No enlarged or alternate panel layout.
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
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
            context.setFillColor(CGColor(red: 0.078, green: 0.063, blue: 0.063, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
            guard let opaque = context.makeImage(), let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(file) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
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
                Text("ReminderVault").font(.system(size: 23, weight: .semibold)).foregroundStyle(.teal)
                Text(title).font(.system(size: 49, weight: .semibold, design: .default)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                Text("Sample · example tasks").font(.system(size: 13, weight: .medium)).tracking(4).foregroundStyle(.white.opacity(0.45))
            }.frame(width: 405, alignment: .leading)
            Image(nsImage: capture).frame(width: capture.size.width, height: capture.size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.12)))
        }.frame(width: 1440, height: 900)
            .background(LinearGradient(colors: [Color(red: 20/255, green: 16/255, blue: 16/255), Color(red: 14/255, green: 26/255, blue: 23/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
