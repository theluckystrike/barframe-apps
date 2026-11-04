import Foundation
import MASKit
import ShelfDockCore

/// CLI smoke run: exercises the core against a real sandbox container and
/// writes smoke.json to NSHomeDirectory() (the container Data dir).
enum SmokeRunner {
    @MainActor static func run() -> Never {
        var checks: [SmokeCheck] = []
        func check(_ name: String, _ pass: Bool, _ detail: String) {
            checks.append(SmokeCheck(name: name, pass: pass, detail: detail))
        }

        let suite = UserDefaults(suiteName: "smoke-shelfdrop")!
        suite.removePersistentDomain(forName: "smoke-shelfdrop")
        let store = ShelfStore(defaults: suite, clearAfterDragOut: false)
        check("store.empty", store.items.isEmpty, "items=\(store.items.count)")

        let addError = store.addText("Smoke sample note")
        check("add.text", addError == nil && store.items.count == 1, "error=\(addError ?? "none")")

        let duplicate = store.addText("Smoke sample note")
        check("add.duplicate", duplicate != nil && store.items.count == 1, "error=\(duplicate ?? "none")")

        let bad = store.add(DropCandidate(.text("   ")))
        check("add.reject-blank", bad != nil, "error=\(bad ?? "none")")

        let groupError = store.createGroup(named: "Smoke")
        check("group.create", groupError == nil && store.groups.count == 2, "groups=\(store.groups.count)")

        let dupGroup = store.createGroup(named: "smoke")
        check("group.duplicate", dupGroup != nil, "error=\(dupGroup ?? "none")")

        let group = store.groups[1]
        let moved = store.addText("Grouped note", groupID: group.id)
        check("group.assign", moved == nil && store.items(in: group).count == 1, "error=\(moved ?? "none")")

        store.clearAll(in: group)
        check("group.clear", store.items(in: group).isEmpty && store.items.count == 1, "items=\(store.items.count)")

        let before = store.items.count
        store.dragOutCompleted(id: store.items[0].id)
        check("dragout.keeps", before == 1 && store.items.count == 1, "items=\(store.items.count)")

        store.clearAfterDragOut = true
        store.addText("Clear me")
        if let last = store.items.last {
            store.dragOutCompleted(id: last.id)
        }
        check("dragout.clears", !store.items.contains(where: { $0.name == "Clear me" }), "items=\(store.items.count)")
        store.clearAfterDragOut = false

        let sampleModel = AppModel(loadSample: true, liveStore: ShelfStore(defaults: nil))
        check("sample.files", sampleModel.store.items.filter { !$0.bookmark.isEmpty }.count == SampleShelf.sampleNames.count, "bundled sample references")
        check("sample.image", sampleModel.store.items.contains { $0.imageData != nil }, "stored sample image")
        check("persist.items", ShelfStore(defaults: suite).items == store.items, "snapshot round trip")
        let sample = SampleShelf.items()
        check("sample.count", sample.count == SampleShelf.sampleNames.count, "count=\(sample.count)")
        check("sample.names", sample.allSatisfy { !$0.name.isEmpty && $0.text != nil }, "names ok")

        let ordered = ShelfOrdering.newestFirst(sample)
        check("order.newest", ordered.first!.addedAt >= ordered.last!.addedAt, "ok")

        let filtered = ShelfOrdering.matching(sample, query: "photo")
        check("filter.match", filtered.count == 1, "count=\(filtered.count)")

        let blankFilter = ShelfOrdering.matching(sample, query: "   ")
        check("filter.blank", blankFilter.count == sample.count, "count=\(blankFilter.count)")

        let classified = ShelfAcceptor.classify(DropCandidate(.fileURL("/tmp/report final.pdf")))
        check("classify.file", classified == "report final.pdf", "name=\(classified ?? "nil")")

        let rejectedPath = ShelfAcceptor.classify(DropCandidate(.fileURL("not a path")))
        check("classify.reject", rejectedPath == nil, "ok")

        check("sandbox", SmokeReport.isSandboxed, "container=\(NSHomeDirectory())")

        let report = SmokeReport(app: "ShelfDock", bundleID: Bundle.main.bundleIdentifier ?? "com.michaellip.shelfdock",
                                 version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                                 checks: checks)
        do { try report.write() } catch {
            FileHandle.standardError.write(Data("smoke write failed: \(error)\n".utf8))
            exit(1)
        }
        exit(report.pass ? 0 : 2)
    }
}
