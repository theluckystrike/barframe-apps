import Foundation
import AppKit
import Testing
import PermitPeekCore
@testable import PermitPeek

@Suite(.serialized)
@MainActor
struct RegressionTests {
    func withStorage(_ body: (URL) throws -> Void) throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = app.appendingPathComponent("build/regression-data/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("watches.json"))
    }
    func saveLive(_ url: URL) throws {
        try JSONEncoder().encode(Samples.watches).write(to: url)
    }
    @Test func sampleDeletionKeepsLiveFileAndRestoresLiveWatches() throws {
        try withStorage { url in
            try saveLive(url)
            let original = try Data(contentsOf: url)
            let model = AppModel(storage: url, installShortcut: false)
            model.toggleSample(true)
            model.clearSampleData()
            #expect(model.watches.isEmpty)
            #expect(try Data(contentsOf: url) == original)
            model.toggleSample(false)
            #expect(model.watches.count == Samples.watches.count)
            #expect(model.notice.isEmpty)
        }
    }
    @Test func explicitLiveDeletionWorksDuringSample() throws {
        try withStorage { url in
            try saveLive(url)
            let model = AppModel(storage: url, installShortcut: false)
            model.toggleSample(true)
            model.deleteAllLiveData()
            #expect(model.watches.count == Samples.watches.count)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            model.toggleSample(false)
            #expect(model.watches.isEmpty)
            let restored = AppModel(storage: url, installShortcut: false)
            #expect(restored.watches.isEmpty)
        }
    }
    @Test func sampleDeletionCannotDeleteLiveOutsideSample() throws {
        try withStorage { url in
            try saveLive(url)
            let original = try Data(contentsOf: url)
            let model = AppModel(storage: url, installShortcut: false)
            model.clearSampleData()
            #expect(model.watches.count == Samples.watches.count)
            #expect(try Data(contentsOf: url) == original)
        }
    }
    @Test func corruptSavedDataSurvivesEveryLiveMutation() throws {
        try withStorage { url in
            let corrupt = Data("unreadable baseline".utf8)
            try corrupt.write(to: url)
            let model = AppModel(storage: url, installShortcut: false)
            #expect(model.savedDataUnreadable)
            model.choose() // Must return before presenting a picker.
            model.rescan()
            model.watches = Samples.watches
            model.persist()
            model.acknowledge(model.watches[0].id)
            #expect(!model.watches[0].changes.isEmpty)
            model.remove(model.watches[0].id)
            #expect(model.watches.count == Samples.watches.count)
            model.toggleSample(true)
            model.clearSampleData()
            model.toggleSample(false)
            model.persist()
            #expect(model.savedDataUnreadable)
            #expect(model.notice.contains("Writes are paused"))
            #expect(try Data(contentsOf: url) == corrupt)
        }
    }
    @Test func explicitResetUnlocksCorruptSavedData() throws {
        try withStorage { url in
            try Data("invalid JSON".utf8).write(to: url)
            let model = AppModel(storage: url, installShortcut: false)
            model.toggleSample(true)
            model.deleteAllLiveData()
            #expect(!model.savedDataUnreadable)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            model.toggleSample(false)
            #expect(model.watches.isEmpty)
            model.watches = [Samples.watches[0]]
            model.persist()
            #expect(try JSONDecoder().decode([Watch].self, from: Data(contentsOf: url)).count == 1)
        }
    }
    @Test func retryRecoversWithoutResetAndKeepsSampleSeparate() throws {
        try withStorage { url in
            try Data("invalid JSON".utf8).write(to: url)
            let model = AppModel(storage: url, installShortcut: false)
            model.toggleSample(true)
            model.clearSampleData()
            try saveLive(url)
            model.retrySavedData()
            #expect(!model.savedDataUnreadable)
            #expect(model.watches.isEmpty)
            model.toggleSample(false)
            #expect(model.watches.count == Samples.watches.count)
        }
    }
    @Test func menuChangesSynchronouslyWithSampleAcknowledgementAndRemoval() throws {
        try withStorage { url in
            let model = AppModel(storage: url, installShortcut: false)
            _ = NSApplication.shared
            let delegate = AppDelegate()
            delegate.model = model
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            defer { if let item = delegate.statusItem { NSStatusBar.system.removeStatusItem(item) } }
            #expect(delegate.presentation.symbol == "shield")
            #expect(delegate.statusItem?.button?.image != nil)
            #expect(delegate.statusItem?.button?.accessibilityLabel() == "PermitPeek no watched apps")
            model.toggleSample(true)
            #expect(delegate.presentation.title == "Sample")
            #expect(delegate.statusItem?.button?.title == "Sample")
            #expect(delegate.presentation.symbol == "questionmark.circle")
            #expect(delegate.statusItem?.button?.accessibilityLabel() == "PermitPeek inspection unknown")
            model.remove(Samples.watches[1].id)
            #expect(delegate.presentation.symbol == "exclamationmark.shield")
            #expect(delegate.statusItem?.button?.accessibilityLabel() == "PermitPeek changes to review")
            model.acknowledge(Samples.watches[0].id)
            #expect(delegate.presentation.symbol == "shield.lefthalf.filled")
            #expect(delegate.statusItem?.button?.accessibilityLabel() == "PermitPeek no unreviewed changes")
            model.clearSampleData()
            #expect(delegate.presentation.symbol == "shield")
            model.toggleSample(false)
            #expect(delegate.presentation.title.isEmpty)
            #expect(delegate.statusItem?.button?.title == "")
            let oldModel = model
            let replacement = AppModel(storage: url, installShortcut: false)
            delegate.model = replacement
            oldModel.toggleSample(true)
            #expect(delegate.presentation.title.isEmpty)
        }
    }
    @Test func placeholderURLsSelectLocalPolicyAndNeverLeakBrandTokens() {
        #expect(!AppLinks.isFinal(AppLinks.webURL("https://{DOMAIN}/apps/permitpeek/privacy/")))
        #expect(AppLinks.isFinal(AppLinks.webURL("https://barframe.com/apps/permitpeek/privacy/")))
        #expect(!AppLinks.isFinal(AppLinks.webURL("http://barframe.com/apps/permitpeek/support/")))
        let text = AppLinks.sanitizedLocalText("Privacy by {BRAND}\nhttps://{DOMAIN}/privacy/\nLocal data stays on your Mac")
        #expect(!text.contains("{BRAND}"))
        #expect(!text.contains("{DOMAIN}"))
        #expect(text.contains("Michael Lip"))
        #expect(text.contains("Local data stays on your Mac"))
        #expect(AppLinks.localText("privacy").contains("locally"))
        #expect(AppLinks.localText("support").contains("Sample"))
    }
}
