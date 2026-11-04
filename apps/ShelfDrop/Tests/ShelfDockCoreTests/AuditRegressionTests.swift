import Foundation
import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers
import Testing
@testable import ShelfDockCore
@testable import ShelfDockApp

@MainActor
struct AuditRegressionTests {
    func temporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Regression sample file".utf8).write(to: url); return url
    }
    @Test func P1_01_textDragRegistersOriginalPayload() async throws {
        let store = ShelfStore(defaults: nil); let original = "Line one\n" + String(repeating: "payload ", count: 50)
        store.addText(original); let model = AppModel(liveStore: store)
        let payload = try #require(model.payload(store.items[0]))
        #expect(!payload.provider.registeredTypeIdentifiers.isEmpty)
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            payload.provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
        #expect(String(data: data, encoding: .utf8) == original)
    }
    @Test func P1_01_fileDragCarriesURL() throws {
        let url = try temporaryFile(); defer { try? FileManager.default.removeItem(at: url) }
        let store = ShelfStore(defaults: nil); AppModel.ingestFile(url, into: store, groupID: nil)
        let model = AppModel(liveStore: store); let item = try #require(store.items.first); let payload = try #require(model.payload(item))
        #expect(payload.writer is NSURL); #expect(payload.lease?.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
        #expect(!payload.provider.registeredTypeIdentifiers.isEmpty)
    }
    @Test func P1_02_cancelledDragRetainsPayloadAcceptedDragHasUndo() {
        let store = ShelfStore(defaults: nil, clearAfterDragOut: true); store.addText("full\ntext")
        let item = store.items[0]; store.dragOutEnded(id: item.id, accepted: false); #expect(store.items == [item])
        store.dragOutEnded(id: item.id, accepted: true); #expect(store.items.isEmpty)
        store.restoreRecentlyCleared(); #expect(store.items == [item])
    }
    @Test func P1_02_copyDoesNotClear() throws {
        let store = ShelfStore(defaults: nil, clearAfterDragOut: true); store.addText("keep\nme")
        let model = AppModel(liveStore: store); let clipboard = NSPasteboard.withUniqueName(); defer { clipboard.releaseGlobally() }
        #expect(model.copy(store.items[0], to: clipboard)); #expect(clipboard.string(forType: .string) == "keep\nme"); #expect(store.items.count == 1)
    }
    @Test func P1_03_reloadRestoresGroupsPayloadsBookmarksAndUndo() throws {
        let suiteName = "shelf-regression-" + UUID().uuidString; let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let url = try temporaryFile(); defer { try? FileManager.default.removeItem(at: url) }
        let store = ShelfStore(defaults: defaults, clearAfterDragOut: true); store.createGroup(named: "Saved")
        store.addText("long\ntext", groupID: store.groups[1].id); AppModel.ingestFile(url, into: store, groupID: nil)
        let bookmark = store.items.last!.bookmark; store.refreshBookmark(id: store.items.last!.id, data: bookmark)
        store.addImage(Data([1, 2, 3]), type: "public.png")
        store.dragOutEnded(id: store.items[0].id, accepted: true)
        let reload = ShelfStore(defaults: defaults)
        #expect(reload.items == store.items); #expect(reload.groups == store.groups); #expect(reload.recentlyClearedIDs == store.recentlyClearedIDs)
        reload.restoreRecentlyCleared(); #expect(reload.items.last?.text == "long\ntext"); #expect(reload.items.last?.groupID == store.groups[1].id)
        #expect(reload.items.contains { $0.bookmark == bookmark })
    }
    @Test func P1_04_nestedChangesReachModelObservers() {
        let store = ShelfStore(defaults: nil); let model = AppModel(liveStore: store); var count = 0
        let observation = model.objectWillChange.sink { count += 1 }; defer { observation.cancel() }
        store.addText("visible immediately"); #expect(count > 0); #expect(model.items.count == 1)
    }
    @Test func P1_05_allAggregatesAndSelectedGroupAcceptsItems() {
        let store = ShelfStore(defaults: nil); store.addText("ungrouped"); store.createGroup(named: "Work")
        let model = AppModel(liveStore: store); model.selectedGroupID = store.groups[1].id
        store.addText("selected", groupID: model.insertionGroupID)
        #expect(model.items.count == 1); #expect(store.items(in: store.groups[0]).count == 2)
        store.moveToGroup(id: store.items[0].id, group: store.groups[1]); #expect(model.items.count == 2)
    }
    @Test func P1_06_sampleIsIsolatedAndBundledFilesResolve() throws {
        let live = ShelfStore(defaults: nil); live.addText("private live text"); let saved = live.items
        let model = AppModel(liveStore: live); model.setSample(true)
        #expect(!model.store.items.contains { $0.text == "private live text" })
        let files = model.store.items.filter { !$0.bookmark.isEmpty }; #expect(files.count == SampleShelf.sampleNames.count)
        for file in files { let access = try #require(model.access(file)); #expect(FileManager.default.fileExists(atPath: access.url.path)) }
        model.store.clearAll(); model.store.addText("sample only"); model.setSample(false); #expect(model.store === live); #expect(live.items == saved)
        model.setSample(true); #expect(!model.store.items.contains { $0.text == "sample only" })
    }
    @Test func P1_07_fullTextAndRawImageSurvive() throws {
        let store = ShelfStore(defaults: nil); let text = String(repeating: "first\nsecond\t ", count: 50); store.addText(text)
        #expect(store.items[0].text == text); #expect(store.items[0].name.count == ShelfLimits.maxNameLength)
        let url = try #require(ShelfResources.contentURL("Samples/Team-photo.png")); let image = try Data(contentsOf: url)
        store.addImage(image, type: UTType.png.identifier); #expect(store.items[1].imageData == image)
        let model = AppModel(liveStore: store); let clipboard = NSPasteboard.withUniqueName(); defer { clipboard.releaseGlobally() }
        #expect(model.copy(store.items[1], to: clipboard)); #expect(clipboard.data(forType: .png) == image)
    }
    @Test func P1_08_screenshotHeadlinesMeetBrief() {
        #expect(ShelfScreenshotComposer.shots.count == 3)
        for shot in ShelfScreenshotComposer.shots { #expect((4...7).contains(shot.0.split(separator: " ").count)) }
    }
    @Test func P2_01_previewExportsFullTextAndImage() throws {
        let model = AppModel(loadSample: true, liveStore: ShelfStore(defaults: nil))
        for item in model.store.items.filter({ $0.text != nil || $0.imageData != nil }) {
            let (url, _) = try model.previewURL(item); defer { try? FileManager.default.removeItem(at: url) }
            #expect(try Data(contentsOf: url) == (item.text.map { Data($0.utf8) } ?? item.imageData))
        }
    }
    @Test func P2_02_emptyStateNamesSupportedDropSurface() {
        #expect(ShelfStore(defaults: nil).emptyStateMessage.contains("open shelf window"))
    }
    @Test func P2_03_noMatchCanResetWithoutLosingShelf() {
        let model = AppModel(liveStore: ShelfStore(defaults: nil)); model.store.addText("known")
        model.query = "no such result"; #expect(model.items.isEmpty); #expect(model.emptyStateMessage.contains("Clear the filter"))
        model.query = ""; #expect(model.items.count == 1)
    }
    @Test func P2_04_missingFilesAndEmptyBookmarksFailExplicitly() throws {
        let store = ShelfStore(defaults: nil)
        #expect(store.addFile(path: "/missing", bookmark: Data(), isDirectory: false) != nil); #expect(store.items.isEmpty)
        let url = try temporaryFile(); let lease = try BookmarkAccess(url: url, stale: true); #expect(lease.refreshedBookmark?.isEmpty == false)
        AppModel.ingestFile(url, into: store, groupID: nil); let item = try #require(store.items.first)
        try FileManager.default.removeItem(at: url); let model = AppModel(liveStore: store)
        #expect(model.fileIssue(item) != nil); #expect(model.payload(item) == nil); #expect(store.lastError != nil)
    }
    @Test func P2_05_policyAndSupportLocalFallbackIsReadable() {
        for page in ShelfPage.allCases {
            #expect(ShelfLinks.destination(page, raw: "https://{DOMAIN}" + page.path) == .local(page))
            #expect(ShelfLinks.destination(page, raw: "https://%7BDOMAIN%7D" + page.path) == .local(page))
            let text = ShelfLinks.localText(page); #expect(text.contains("Sharing") || text.contains("sharing")); #expect(!text.contains("{BRAND}")); #expect(!text.contains("{DOMAIN}"))
        }
    }
    @Test func P3_01_loginFailureReconcilesSystemStatus() {
        var status = SMAppService.Status.notRegistered
        let login = LoginStatusModel(status: { status }, register: { throw CocoaError(.fileWriteNoPermission) }, unregister: {})
        login.setEnabled(true); #expect(!login.isEnabled); #expect(login.message != nil)
        status = .requiresApproval; login.refresh(); #expect(login.isEnabled); #expect(login.message?.contains("Approve") == true)
        status = .enabled; login.refresh(); #expect(login.isEnabled); #expect(login.message == nil)
    }
    @Test func ingestProvidersUsesSelectedGroupAndOriginalPayloads() async throws {
        let url = try temporaryFile(); defer { try? FileManager.default.removeItem(at: url) }
        let store = ShelfStore(defaults: nil); store.createGroup(named: "Dropped"); let model = AppModel(liveStore: store); model.selectedGroupID = store.groups[1].id
        let imageURL = try #require(ShelfResources.contentURL("Samples/Team-photo.png")); let bytes = try Data(contentsOf: imageURL)
        let image = NSItemProvider(); image.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { callback in callback(bytes, nil); return nil }
        model.addDrop(providers: [NSItemProvider(object: "Original\nprovider text" as NSString), NSItemProvider(object: url as NSURL), image])
        let deadline = Date().addingTimeInterval(5)
        while store.items.count < 3 && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(store.items.count == 3); #expect(store.items.allSatisfy { $0.groupID == store.groups[1].id })
        #expect(store.items.contains { $0.text == "Original\nprovider text" }); #expect(store.items.contains { $0.imageData == bytes })
    }

}
