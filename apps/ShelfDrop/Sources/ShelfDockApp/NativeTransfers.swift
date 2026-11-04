import AppKit
import SwiftUI
import Quartz
import ShelfDockCore

@MainActor
final class ShelfPayload {
    let writer: NSPasteboardWriting
    let provider: NSItemProvider
    let lease: BookmarkAccess?
    let shareObject: Any
    init(writer: NSPasteboardWriting, provider: NSItemProvider, lease: BookmarkAccess? = nil, shareObject: Any? = nil) { self.writer = writer; self.provider = provider; self.lease = lease; self.shareObject = shareObject ?? writer }
}
struct DragSource: NSViewRepresentable {
    let item: ShelfItem
    let model: AppModel
    func makeNSView(context: Context) -> ShelfDragView { let view = ShelfDragView(); view.item = item; view.model = model; return view }
    func updateNSView(_ view: ShelfDragView, context: Context) { view.item = item; view.model = model }
}
@MainActor
final class ShelfDragView: NSView, NSDraggingSource {
    var item: ShelfItem?
    weak var model: AppModel?
    private var start: NSEvent?
    private var activePayload: ShelfPayload?
    private var activeStore: ShelfStore?
    private var activeID: UUID?
    override func mouseDown(with event: NSEvent) { start = event }
    override func mouseDragged(with event: NSEvent) {
        guard let start, hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) > 3,
              let item, let model, let payload = model.payload(item) else { return }
        self.start = nil
        activePayload = payload; activeStore = model.store; activeID = item.id
        let drag = NSDraggingItem(pasteboardWriter: payload.writer)
        let label = NSImage(size: NSSize(width: 240, height: 36), flipped: false) { rect in
            NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            (item.name as NSString).draw(in: rect.insetBy(dx: 10, dy: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            return true
        }
        let point = convert(event.locationInWindow, from: nil)
        drag.setDraggingFrame(NSRect(x: point.x, y: point.y - 18, width: 240, height: 36), contents: label)
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    override func mouseUp(with event: NSEvent) { start = nil }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let id = activeID { activeStore?.dragOutEnded(id: id, accepted: operation.contains(.copy)) }
        activeID = nil; activePayload = nil; activeStore = nil
    }
}
@MainActor
final class SharingController: NSObject, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private var payload: ShelfPayload?
    private var picker: NSSharingServicePicker?
    private let onFinish: (Error?) -> Void
    init(payload: ShelfPayload, onFinish: @escaping (Error?) -> Void) { self.payload = payload; self.onFinish = onFinish }
    private func finish(_ error: Error? = nil) { payload = nil; picker = nil; onFinish(error) }
    func show(in view: NSView) {
        guard let payload else { return }
        let content: Any = payload.shareObject
        picker = NSSharingServicePicker(items: [content]); picker?.delegate = self
        picker?.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? { self }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) { if service == nil { finish() } }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish(error) }
}
@MainActor
final class PreviewController: NSWindowController, NSWindowDelegate {
    private var lease: BookmarkAccess?
    private let url: URL
    private let temporary: Bool
    init(url: URL, lease: BookmarkAccess?, temporary: Bool) {
        self.url = url; self.lease = lease; self.temporary = temporary
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let preview = QLPreviewView(frame: window.contentLayoutRect, style: .normal)!
        preview.autoresizingMask = [.width, .height]; preview.previewItem = url as NSURL
        window.contentView = preview; window.title = "Quick Look — " + url.lastPathComponent; window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    func windowWillClose(_ notification: Notification) {
        (window?.contentView as? QLPreviewView)?.close()
        lease = nil
        if temporary { try? FileManager.default.removeItem(at: url) }
    }
}
enum ShelfResources {
    static var bundle: Bundle {
        let name = "ShelfDock_ShelfDockApp.bundle"
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name), let bundle = Bundle(url: url) { return bundle }
        if let bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent(name)) { return bundle }
        return Bundle.module
    }
    static func contentURL(_ relative: String) -> URL? {
        guard let root = bundle.resourceURL else { return nil }
        let url = root.appendingPathComponent("Content/" + relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// The original encoded image is the primary pasteboard representation.
final class ImagePasteboardPayload: NSObject, NSPasteboardWriting {
    let data: Data
    let type: NSPasteboard.PasteboardType
    let image: NSImage
    init(data: Data, type: String, image: NSImage) { self.data = data; self.type = NSPasteboard.PasteboardType(type); self.image = image }
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { type == .tiff ? [.tiff] : [type, .tiff] }
    func pasteboardPropertyList(forType requested: NSPasteboard.PasteboardType) -> Any? { requested == type ? data : requested == .tiff ? image.tiffRepresentation : nil }
}
