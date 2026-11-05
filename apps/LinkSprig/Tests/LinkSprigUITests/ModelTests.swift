import Testing
import AppKit
import SwiftUI
@testable import LinkSprigCore
@testable import LinkSprig

@Test @MainActor func detailCanReopenWithoutAnExistingWindow() {
    _ = NSApplication.shared
    let model = AppModel(persistent: false)
    let delegate = AppDelegate()
    #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    var opened = 0
    delegate.connect(model, openDetail: { opened += 1 })
    delegate.showWindow()
    delegate.showWindow()
    #expect(opened == 2)
}
@Test @MainActor func modelShortcutDefaultsAndResetAreDisabled() {
    _ = NSApplication.shared
    let model = AppModel(persistent: false)
    #expect(model.shortcutKey == UInt32.max)
    model.shortcutKey = 35
    model.clearLocalData()
    #expect(model.shortcutKey == UInt32.max)
}
@Test @MainActor func spanishModelErrorsAndCountAreComplete() {
    _ = NSApplication.shared
    let model = AppModel(persistent: false)
    model.language = "es"; model.setSample(true)
    #expect(model.status == "3 afectados · Incompleto")
    #expect(model.localized(ProposalError.invalid) == ProposalError.invalid.spanish)
    #expect(model.localized(ScanError.symlinkRoot) == ScanError.symlinkRoot.spanish)
    #expect(!model.localized(NSError(domain: "test", code: 1)).contains("operation"))
}

@Test @MainActor func shortcutRecorderCapturesAndCancels() throws {
    _ = NSApplication.shared
    let model = AppModel(persistent: false)
    let button = RecorderButton(); button.model = model
    let mouse = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option, .shift], timestamp: 0, windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
    button.mouseDown(with: mouse)
    #expect(button.performKeyEquivalent(with: key))
    #expect(model.shortcutKey == 6); #expect(model.shortcutModifiers == 2816)
    button.mouseDown(with: mouse)
    #expect(model.shortcutKey == UInt32.max)
    let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53))
    button.keyDown(with: escape)
    #expect(model.shortcutKey == 6); #expect(!button.recording)
}

@Test @MainActor func largeCoverageReportRendersCollapsed() {
    _ = NSApplication.shared
    let model = AppModel(persistent: false)
    let findings = (0..<10000).map { Finding(link: DocumentLink(source: "sample.md", line: $0 + 1, target: "#fragment"), sourceAfter: "sample.md", kind: .fragment) }
    let plan = Plan(proposal: Sample.proposal, findings: findings, warnings: [], scannedAt: Date())
    let host = NSHostingView(rootView: ReportView(model: model, plan: plan))
    host.frame = NSRect(x: 0, y: 0, width: 820, height: 400)
    let start = ContinuousClock.now
    host.layoutSubtreeIfNeeded()
    #expect(start.duration(to: .now) < .seconds(5))
    #expect(host.fittingSize.height < 1000)
}
