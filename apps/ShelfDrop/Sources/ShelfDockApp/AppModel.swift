import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine
import Quartz
import ShelfDockCore
import MASKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var store: ShelfStore
    @Published var selectedGroupID: UUID?
    @Published var query = ""
    @Published private(set) var isSample = false
    private let liveStore: ShelfStore
    private var sampleStore: ShelfStore?
    private var observation: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var privacyWindow: NSWindow?
    private var supportWindow: NSWindow?
    private var preview: PreviewController?
    private var sharing: [UUID: SharingController] = [:]

    init(loadSample: Bool = false, liveStore: ShelfStore? = nil) {
        let live = liveStore ?? ShelfStore()
        self.liveStore = live; store = live
        observeStore()
        if loadSample { setSample(true) }
    }
    private func observeStore() {
        observation = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    var items: [ShelfItem] { ShelfOrdering.newestFirst(ShelfOrdering.matching(store.items(in: currentGroup), query: query)) }
    var currentGroup: ShelfGroup { store.groups.first { $0.id == selectedGroupID } ?? store.groups[0] }
    var insertionGroupID: UUID? { currentGroup.id == store.groups[0].id ? nil : currentGroup.id }
    var menuBarTitle: String { store.items.isEmpty ? "" : "\(store.items.count)" }
    var emptyStateMessage: String { query.isEmpty ? store.emptyStateMessage : "No matching items. Clear the filter to see your shelf." }
    func setSample(_ on: Bool) {
        guard on != isSample else { return }
        if on {
            let sample = ShelfStore(defaults: nil)
            for name in SampleShelf.sampleNames {
                guard let url = ShelfResources.contentURL("Samples/" + name) else { sample.fail("Bundled sample file missing."); continue }
                switch BookmarkResolver.make(for: url, readOnly: true) {
                case .success(let bookmark): sample.addFile(path: url.path, bookmark: bookmark, isDirectory: false)
                case .failure(let error): sample.fail(error.localizedDescription)
                }
            }
            sample.addText("Sample note\nKeep the original text, including line breaks.")
            if let url = ShelfResources.contentURL("Samples/Team-photo.png"), let data = try? Data(contentsOf: url) { sample.addImage(data, type: UTType.png.identifier) }
            sample.createGroup(named: "Design")
            if let item = sample.items.first(where: { $0.name == "Design-tokens.json" }) { sample.moveToGroup(id: item.id, group: sample.groups[1]) }
            sampleStore = sample; store = sample
        } else { store = liveStore; sampleStore = nil }
        isSample = on; selectedGroupID = nil; query = ""; observeStore()
    }
    /// Capture the destination at drop time; toggling Sample cannot mix stores.
    func addDrop(providers: [NSItemProvider]) {
        let target = store; let group = insertionGroupID
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    Task { @MainActor in
                        let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                        guard let url, url.isFileURL else { target.fail("That file drop could not be read. " + (error?.localizedDescription ?? "")); return }
                        Self.ingestFile(url, into: target, groupID: group)
                    }
                }
            } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    Task { @MainActor in
                        guard let data, NSImage(data: data) != nil else { target.fail("That image could not be read. " + (error?.localizedDescription ?? "")); return }
                        target.addImage(data, type: type, groupID: group)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                    Task { @MainActor in
                        let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                        guard let text else { target.fail("That text could not be read. " + (error?.localizedDescription ?? "")); return }
                        target.addText(text, groupID: group)
                    }
                }
            } else { target.fail("Use a file, folder, plain text, or image drop.") }
        }
    }
    static func ingestFile(_ url: URL, into store: ShelfStore, groupID: UUID?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        switch BookmarkResolver.make(for: url) {
        case .success(let bookmark):
            var directory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            store.addFile(path: url.path, bookmark: bookmark, isDirectory: directory.boolValue, groupID: groupID)
        case .failure(let error): store.fail(error.localizedDescription)
        }
    }
    func addPasteboardText() {
        guard let text = NSPasteboard.general.string(forType: .string) else { store.fail("The clipboard has no text."); return }
        store.addText(text, groupID: insertionGroupID)
    }
    func access(_ item: ShelfItem) -> BookmarkAccess? {
        switch BookmarkResolver.access(item.bookmark) {
        case .success(let lease):
            if let fresh = lease.refreshedBookmark { store.refreshBookmark(id: item.id, data: fresh) }
            return lease
        case .failure(let error): store.fail(error.localizedDescription); return nil
        }
    }
    func fileIssue(_ item: ShelfItem) -> String? {
        guard item.text == nil, item.imageData == nil else { return nil }
        if case .failure(let error) = BookmarkResolver.access(item.bookmark) { return error == .missing ? "Missing — restore or remove" : "Permission — drop again" }
        return nil
    }
    func payload(_ item: ShelfItem) -> ShelfPayload? {
        if let text = item.text { return ShelfPayload(writer: text as NSString, provider: NSItemProvider(object: text as NSString)) }
        if let data = item.imageData, let image = NSImage(data: data) {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: item.imageType ?? UTType.png.identifier, visibility: .all) { completion in completion(data, nil); return nil }
            return ShelfPayload(writer: ImagePasteboardPayload(data: data, type: item.imageType ?? UTType.png.identifier, image: image), provider: provider, shareObject: image)
        }
        guard let lease = access(item) else { return nil }
        let provider = NSItemProvider(contentsOf: lease.url) ?? NSItemProvider(object: lease.url as NSURL)
        return ShelfPayload(writer: lease.url as NSURL, provider: provider, lease: lease)
    }
    @discardableResult func copy(_ item: ShelfItem, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let payload = payload(item) else { return false }
        pasteboard.clearContents()
        let wrote = pasteboard.writeObjects([payload.writer])
        if !wrote { store.fail("Could not copy this item.") }
        return wrote
    }
    func share(_ item: ShelfItem) {
        guard let view = NSApp.keyWindow?.contentView else { store.fail("Open the shelf and try sharing again."); return }
        guard let payload = payload(item) else { return }
        let id = UUID(); let target = store
        let controller = SharingController(payload: payload) { [weak self] error in
            self?.sharing.removeValue(forKey: id)
            if let error { target.fail("Sharing failed: " + error.localizedDescription) }
        }
        sharing[id] = controller; controller.show(in: view)
    }
    func previewURL(_ item: ShelfItem) throws -> (URL, BookmarkAccess?) {
        if item.text == nil, item.imageData == nil {
            guard let lease = access(item) else { throw BookmarkError.unresolvable("Permission unavailable") }
            return (lease.url, lease)
        }
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ShelfDockPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let ext = item.text != nil ? "txt" : (UTType(item.imageType ?? UTType.png.identifier)?.preferredFilenameExtension ?? "png")
        let url = cache.appendingPathComponent(item.id.uuidString).appendingPathExtension(ext)
        try (item.text.map { Data($0.utf8) } ?? item.imageData ?? Data()).write(to: url, options: .atomic)
        return (url, nil)
    }
    func quickLook(_ item: ShelfItem) {
        do {
            let (url, lease) = try previewURL(item)
            preview?.close()
            preview = PreviewController(url: url, lease: lease, temporary: item.text != nil || item.imageData != nil)
            preview?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        } catch { store.fail("Preview unavailable. " + error.localizedDescription) }
    }
    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: self)))
            window.styleMask = [.titled, .closable]
            window.title = "ShelfDock Settings"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openPage(_ page: ShelfPage) {
        // Prefer the live web page when a valid HTTPS URL is configured;
        // otherwise open the bundled local copy.
        let raw = Bundle.main.object(forInfoDictionaryKey: page.infoKey) as? String
        if case .web(let url) = ShelfLinks.destination(page, raw: raw) {
            NSWorkspace.shared.open(url)
            return
        }
        let window: NSWindow
        switch page {
        case .privacy:
            if privacyWindow == nil {
                let w = NSWindow(contentViewController: NSHostingController(rootView: LocalPageView(page: .privacy)))
                configure(w)
                privacyWindow = w
            }
            window = privacyWindow!
        case .support:
            if supportWindow == nil {
                let w = NSWindow(contentViewController: NSHostingController(rootView: LocalPageView(page: .support)))
                configure(w)
                supportWindow = w
            }
            window = supportWindow!
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configure(_ window: NSWindow) {
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }
}
