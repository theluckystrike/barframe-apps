import Foundation
import Testing
import StepQuayCore
@testable import StepQuay

@MainActor
func isolated(_ body: (AppModel, UserDefaults) throws -> Void) rethrows {
    let name = "StepQuayTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(AppModel(defaults: defaults, timerEnabled: false), defaults)
}
@Test @MainActor func sampleMutationsNeverPersistLiveQueue() throws {
    try isolated { model, defaults in
        model.change { try $0.add(title: "Real task", minutes: 3) }
        let data = defaults.data(forKey: "queue")
        model.toggleSample(true); model.resume(); model.finish(); model.resetSample(); model.toggleSample(false)
        #expect(model.queue.actions.map(\.title) == ["Real task"])
        #expect(defaults.data(forKey: "queue") == data)
    }
}
@Test @MainActor func samplePausesLiveRunningAction() throws {
    try isolated { model, defaults in
        model.change { try $0.add(title: "Real task", minutes: 3) }; model.start()
        model.toggleSample(true); model.toggleSample(false)
        #expect(model.queue.current?.phase == .paused)
        #expect(model.queue.current?.notes.last?.note == "Paused while exploring Sample")
        let restored = try Queue.decoded(defaults.data(forKey: "queue")!)
        #expect(restored.current?.phase == .paused)
    }
}
@Test @MainActor func relaunchRestoresPausedAction() throws {
    try isolated { model, defaults in
        model.change { try $0.add(title: "Live task", minutes: 2) }; model.start()
        let reopened = AppModel(defaults: defaults, timerEnabled: false)
        #expect(reopened.queue.current?.phase == .paused)
        #expect(reopened.queue.current?.notes.last?.note == "Paused when the app closed")
    }
}
@Test @MainActor func corruptStorageBlocksAccidentalOverwrite() throws {
    try isolated { _, defaults in
        let bad = Data("broken queue".utf8); defaults.set(bad, forKey: "queue")
        let reopened = AppModel(defaults: defaults, timerEnabled: false)
        reopened.change { try $0.add(title: "Must not overwrite", minutes: 1) }
        #expect(reopened.storageFailed); #expect(defaults.data(forKey: "queue") == bad)
        reopened.toggleSample(true); reopened.resume(); reopened.finish(); reopened.toggleSample(false)
        #expect(defaults.data(forKey: "queue") == bad)
        #expect(!reopened.message.isEmpty)
    }
}
@Test @MainActor func recoveryResetKeepsBackup() throws {
    try isolated { _, defaults in
        let bad = Data("broken queue".utf8); defaults.set(bad, forKey: "queue")
        let reopened = AppModel(defaults: defaults, timerEnabled: false); reopened.resetStoredQueue()
        #expect(!reopened.storageFailed); #expect(defaults.data(forKey: "queueRecoveryBackup") == bad)
        let restored = try Queue.decoded(defaults.data(forKey: "queue")!)
        #expect(restored.actions.isEmpty)
    }
}
@Test @MainActor func sampleHistoryClearKeepsLiveHistory() throws {
    try isolated { model, _ in
        model.change { try $0.add(title: "Live", minutes: 1) }; model.start(); model.finish()
        model.toggleSample(true); model.change { $0.history = [] }; model.toggleSample(false)
        #expect(model.queue.history.count == 1)
    }
}
@Test @MainActor func spanishLocalizationAndStates() throws {
    try isolated { model, _ in
        model.language = "es"; #expect(model.l("Revise remaining") == "Revisar tiempo restante")
        #expect(model.symbol == "list.bullet")
        model.toggleSample(true); #expect(model.symbol == "pause.circle")
        model.resume(); #expect(model.symbol == "play.circle")
        model.deferAction(); model.start(); #expect(model.symbol == "exclamationmark.circle")
    }
}
@Test @MainActor func invalidActionExposesRecoveryMessage() throws {
    try isolated { model, _ in
        model.change { try $0.add(title: "", minutes: 5) }
        #expect(!model.message.isEmpty); #expect(model.queue.actions.isEmpty)
        model.change { try $0.add(title: "Valid", minutes: 5) }
        #expect(model.message.isEmpty); #expect(model.queue.actions.count == 1)
    }
}

@Test @MainActor func idleOpenAppPeriodicallyPrunesAndPersistsLiveHistory() throws {
    try isolated { model, defaults in
        let now = Date(); model.retention = 7
        model.change {
            try $0.add(title: "Expires shortly", minutes: 1); try $0.start(now: 0)
            try $0.finish(now: 10, date: now.addingTimeInterval(-7 * 86400 + 30))
        }
        model.tick(now: now.addingTimeInterval(61), uptime: 100)
        #expect(model.queue.history.isEmpty)
        let saved = try Queue.decoded(defaults.data(forKey: "queue")!)
        #expect(saved.history.isEmpty)
    }
}
@Test @MainActor func retentionSettingInSamplePrunesLiveWithoutChangingFixtures() throws {
    try isolated { model, defaults in
        model.change {
            try $0.add(title: "Old live", minutes: 1); try $0.start(now: 0)
            try $0.finish(now: 10, date: Date().addingTimeInterval(-10 * 86400))
        }
        model.toggleSample(true); let fixture = model.queue
        model.retention = 7
        #expect(model.queue == fixture)
        let saved = try Queue.decoded(defaults.data(forKey: "queue")!)
        #expect(saved.history.isEmpty)
        model.toggleSample(false); #expect(model.queue.history.isEmpty)
    }
}
@Test @MainActor func periodicRetentionWhileSampleIsOpenPrunesLive() throws {
    try isolated { model, defaults in
        let now = Date(); model.retention = 7
        model.change {
            try $0.add(title: "Expires shortly", minutes: 1); try $0.start(now: 0)
            try $0.finish(now: 10, date: now.addingTimeInterval(-7 * 86400 + 30))
        }
        model.toggleSample(true); let fixture = model.queue
        model.tick(now: now.addingTimeInterval(61), uptime: 100)
        #expect(model.queue == fixture)
        let saved = try Queue.decoded(defaults.data(forKey: "queue")!)
        #expect(saved.history.isEmpty)
        model.toggleSample(false); #expect(model.queue.history.isEmpty)
    }
}
@Test @MainActor func foreverRetentionSurvivesPeriodicCleanup() throws {
    try isolated { model, _ in
        model.retention = 0
        model.change {
            try $0.add(title: "Keep", minutes: 1); try $0.start(now: 0)
            try $0.finish(now: 10, date: Date(timeIntervalSince1970: 0))
        }
        model.tick(now: Date().addingTimeInterval(61), uptime: 100)
        #expect(model.queue.history.count == 1)
    }
}
@Test func unresolvedBrandUsesBundledDocumentsAndFinalURLsRemainUsable() {
    #expect(LocalDocument.validWebURL("https://{DOMAIN}/apps/stepquay/privacy/") == nil)
    #expect(LocalDocument.validWebURL(nil) == nil)
    #expect(LocalDocument.validWebURL("http://barframe.com/apps/stepquay/support/") == nil)
    #expect(LocalDocument.validWebURL("https://barframe.com/apps/stepquay/privacy/")?.absoluteString == "https://barframe.com/apps/stepquay/privacy/")
    for item in LocalDocument.allCases {
        for spanish in [false, true] {
            let text = item.text(spanish: spanish)
            #expect(text.count > 300); #expect(!text.contains("{DOMAIN}")); #expect(!text.contains("{BRAND}"))
        }
    }
}

@Test @MainActor func launchCleanupPersistsExpiredHistory() throws {
    try isolated { model, defaults in
        model.retention = 7
        model.change {
            try $0.add(title: "Expired", minutes: 1); try $0.start(now: 0)
            try $0.finish(now: 10, date: Date().addingTimeInterval(-10 * 86400))
        }
        let reopened = AppModel(defaults: defaults, timerEnabled: false)
        #expect(reopened.queue.history.isEmpty)
        let saved = try Queue.decoded(defaults.data(forKey: "queue")!)
        #expect(saved.history.isEmpty)
    }
}
