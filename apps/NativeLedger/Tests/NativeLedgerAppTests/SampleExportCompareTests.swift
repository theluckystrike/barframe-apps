import Foundation
import Testing
import LedgerCore
@testable import NativeLedger

@MainActor @Suite struct SampleIsolationTests {
    private func savedFileStamp() -> Date? {
        let file = LedgerModel.defaultDirectory.appendingPathComponent(LedgerStore.fileName)
        return (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    @Test func sampleLaunchNeverOpensTheSavedLedgers() {
        let state = AppState.launch(arguments: ["NativeLedger", "--ledger-sample"])
        #expect(state.sampleOnly)
        #expect(state.current.isSample)
        #expect(!state.live.hasStore)
        #expect(!state.current.hasStore)
        state.leaveSample()
        #expect(state.current.isSample)
    }

    @Test func sampleActionsWriteNothing() async throws {
        let before = savedFileStamp()
        let sample = LedgerModel.sample()
        #expect(!sample.hasStore)
        #expect(!sample.canAddApps)
        #expect(!sample.canExport)
        #expect(sample.add(urls: [URL(fileURLWithPath: "/System/Applications/Calculator.app")]).isEmpty)
        await sample.inspect(SampleLedger.notesID)?.value
        await sample.acknowledge(SampleLedger.editorID)?.value
        sample.remove(SampleLedger.clockID)
        #expect(sample.ledgers.count == 3)
        #expect(sample.ledger(SampleLedger.editorID)?.latest?.kind == .acknowledged)
        #expect(savedFileStamp() == before)
    }

    @Test func sampleHasRebuildTeamChangeAndBaseline() {
        let sample = LedgerModel.sample()
        let editor = sample.ledger(SampleLedger.editorID)!
        let viewer = sample.ledger(SampleLedger.viewerID)!
        let notes = sample.ledger(SampleLedger.notesID)!
        #expect(editor.openAnomalies.contains(.silentRebuild))
        #expect(viewer.openAnomalies.contains(.teamChange))
        #expect(notes.baseline != nil)
        #expect(sample.badge(editor) == .anomaly)
        #expect(sample.badge(notes) == .intact)
        #expect(sample.ledgers.allSatisfy { sample.verdicts[$0.id]?.isIntact == true })
    }

    @Test func openAndLeaveSampleKeepsLiveModel() {
        let live = LedgerModel(store: nil)
        let state = AppState(live: live)
        #expect(!state.showingSample)
        state.openSample()
        #expect(state.current.isSample)
        state.leaveSample()
        #expect(state.current === live)
    }

    @Test func sampleCompareCoversEveryVerdict() throws {
        let sample = LedgerModel.sample()
        sample.chooseCompare()
        let comparison = try #require(sample.comparison)
        #expect(comparison.sample)
        #expect(Set(comparison.rows.map(\.verdict)) == Set(CrossMacVerdict.allCases))
        #expect(comparison.brokenInFile == 0)
    }
}

@MainActor @Suite struct ExportCompareTests {
    private func trackedModel() -> LedgerModel {
        var ledger = AppLedger(displayName: "/Users/someone/Applications/Tool.app", bookmark: Data(repeating: 9, count: 48))
        LedgerChain.append(observation(), kind: .observed, to: &ledger)
        return LedgerModel(store: nil, seed: [ledger], now: { appT0 })
    }

    @Test func exportStripsBookmarksAndPaths() throws {
        let model = trackedModel()
        let data = try model.exportData()
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("/Users"))
        #expect(!text.contains("\"bookmark\""))
        #expect(text.contains(LedgerFile.currentFormat))
        let file = try LedgerFile.decode(data)
        #expect(file.ledgers.first?.displayName == "com.example.tool")
        #expect(file.ledgers.allSatisfy { LedgerChain.verify($0).isIntact })
    }

    @Test func exportWritesChosenFile() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = trackedModel()
        let url = folder.appendingPathComponent(LedgerModel.suggestedFileName(appT0))
        #expect(model.export(to: url))
        #expect(url.pathExtension == "nativeledger")
        #expect(!url.lastPathComponent.contains(":"))
        #expect(try LedgerFile.decode(Data(contentsOf: url)).ledgers.count == 1)
        #expect(model.notice.hasPrefix("Exported 1 ledger"))
        #expect(!model.export(to: folder.appendingPathComponent("missing/nested/file.nativeledger")))
    }

    @Test func compareLoadsExportedFile() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let here = trackedModel()
        let url = folder.appendingPathComponent("other.nativeledger")
        #expect(here.export(to: url))
        var changed = AppLedger(displayName: "Tool")
        LedgerChain.append(observation(sha: String(repeating: "f", count: 64)), kind: .observed, to: &changed)
        var extra = AppLedger(displayName: "Extra")
        LedgerChain.append(observation("com.example.extra"), kind: .observed, to: &extra)
        let there = LedgerModel(store: nil, seed: [changed, extra])
        #expect(there.compare(fileAt: url))
        let comparison = try #require(there.comparison)
        #expect(comparison.source == "other.nativeledger")
        #expect(comparison.rows.map(\.bundleID) == ["com.example.extra", "com.example.tool"])
        #expect(comparison.rows.map(\.verdict) == [.onlyHere, .differentBinarySameVersion])
        let same = trackedModel()
        #expect(same.compare(fileAt: url))
        #expect(same.comparison?.rows.map(\.verdict) == [.sameBuild])
    }

    @Test func compareRejectsGarbageAndOtherFormats() throws {
        let model = trackedModel()
        #expect(!model.compare(data: Data("hello".utf8), source: "x"))
        #expect(model.comparison == nil)
        #expect(model.notice == "That file is not a NativeLedger ledger file.")
        #expect(!model.compare(data: Data(#"{"format":"other.v9","exportedAt":"2026-10-16T00:00:00.000Z","ledgers":[]}"#.utf8), source: "x"))
        #expect(model.notice.contains("other.v9"))
    }

    @Test func compareFlagsTamperedLedgersInFile() throws {
        var ledger = AppLedger(displayName: "Tool")
        LedgerChain.append(observation(), kind: .observed, to: &ledger)
        ledger.entries[0].observation.version = "9.9"
        let data = try LedgerFile(ledgers: [ledger], exportedAt: appT0).encoded()
        let model = trackedModel()
        #expect(model.compare(data: data, source: "tampered"))
        #expect(model.comparison?.brokenInFile == 1)
        #expect(model.comparison?.unverified == ["com.example.tool"])
    }

    @Test func compareMarksBrokenLedgersOnThisMac() throws {
        var mine = AppLedger(displayName: "Tool")
        LedgerChain.append(observation(), kind: .observed, to: &mine)
        LedgerChain.append(observation(version: "1.1", build: "110"), kind: .observed, to: &mine)
        mine.entries[0].observation.build = "999"
        var theirs = AppLedger(displayName: "Tool")
        LedgerChain.append(observation(version: "1.1", build: "110"), kind: .observed, to: &theirs)
        let model = LedgerModel(store: nil, seed: [mine])
        #expect(model.compare(data: try LedgerFile(ledgers: [theirs], exportedAt: appT0).encoded(), source: "other"))
        #expect(model.comparison?.brokenInFile == 0)
        #expect(model.comparison?.brokenHere == 1)
        #expect(model.comparison?.unverified == ["com.example.tool"])
    }
}
