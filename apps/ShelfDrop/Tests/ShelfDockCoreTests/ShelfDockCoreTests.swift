import Foundation
import Testing
@testable import ShelfDockCore

@MainActor
struct ShelfDockCoreTests {
    private let defaults = UserDefaults(suiteName: "test-shelfdrop-\(UUID().uuidString)")!

    private func makeStore(clear: Bool? = false) -> ShelfStore {
        ShelfStore(defaults: defaults, clearAfterDragOut: clear)
    }

    // MARK: - Acceptor

    @Test func classifyFilePath() {
        #expect(ShelfAcceptor.classify(DropCandidate(.fileURL("/tmp/report final.pdf"))) == "report final.pdf")
    }

    @Test func classifyRejectsNonPath() {
        #expect(ShelfAcceptor.classify(DropCandidate(.fileURL("not a path"))) == nil)
    }

    @Test func classifyTextCollapsesWhitespace() {
        let result = ShelfAcceptor.classify(DropCandidate(.text("Line one\n\nLine   two")))
        #expect(result == "Line one Line two")
    }

    @Test func classifyRejectsBlankText() {
        #expect(ShelfAcceptor.classify(DropCandidate(.text("   \n\t "))) == nil)
    }

    @Test func classifyTruncatesLongNames() {
        let long = String(repeating: "x", count: 300)
        let result = ShelfAcceptor.classify(DropCandidate(.text(long)))
        #expect(result?.count == ShelfLimits.maxNameLength)
    }

    // MARK: - Add

    @Test func addText() {
        let store = makeStore()
        #expect(store.addText("Hello") == nil)
        #expect(store.items.count == 1)
        #expect(store.items[0].isText)
    }

    @Test func addDuplicateRejected() {
        let store = makeStore()
        _ = store.addText("Same")
        #expect(store.addText("Same") != nil)
        #expect(store.items.count == 1)
    }

    @Test func addCapAtMaxItems() {
        let store = makeStore()
        for index in 0..<ShelfLimits.maxItems {
            #expect(store.addText("Item \(index)") == nil)
        }
        #expect(store.addText("Overflow") != nil)
        #expect(store.items.count == ShelfLimits.maxItems)
    }

    @Test func addFile() {
        let store = makeStore()
        #expect(store.addFile(path: "/tmp/notes.txt", bookmark: Data([1, 2, 3]), isDirectory: false) == nil)
        #expect(store.items.count == 1)
        #expect(store.items[0].name == "notes.txt")
        #expect(!store.items[0].isText)
    }

    // MARK: - Groups

    @Test func createAndAssignGroup() {
        let store = makeStore()
        #expect(store.createGroup(named: "Work") == nil)
        #expect(store.groups.count == 2)
        let work = store.group(named: "Work")!
        _ = store.addText("Task", groupID: work.id)
        #expect(store.items(in: work).count == 1)
        #expect(store.items(in: store.groups[0]).count == 1)
    }

    @Test func duplicateGroupNameRejected() {
        let store = makeStore()
        _ = store.createGroup(named: "Work")
        #expect(store.createGroup(named: "work") != nil)
    }

    @Test func deleteGroupFallsBackToDefault() {
        let store = makeStore()
        _ = store.createGroup(named: "Temp")
        let temp = store.group(named: "Temp")!
        _ = store.addText("Note", groupID: temp.id)
        store.deleteGroup(temp)
        #expect(store.groups.count == 1)
        #expect(store.items.count == 1)
        #expect(store.items[0].groupID == nil)
    }

    @Test func defaultGroupCannotBeDeleted() {
        let store = makeStore()
        store.deleteGroup(store.groups[0])
        #expect(store.groups.count == 1)
    }

    @Test func moveToGroup() {
        let store = makeStore()
        _ = store.createGroup(named: "Later")
        let later = store.group(named: "Later")!
        _ = store.addText("Note")
        store.moveToGroup(id: store.items[0].id, group: later)
        #expect(store.items(in: later).count == 1)
    }

    // MARK: - Drag out / clear

    @Test func dragOutKeepsByDefault() {
        let store = makeStore(clear: false)
        _ = store.addText("Keep")
        store.dragOutCompleted(id: store.items[0].id)
        #expect(store.items.count == 1)
    }

    @Test func dragOutClearsWhenEnabled() {
        let store = makeStore(clear: true)
        _ = store.addText("Gone")
        let id = store.items[0].id
        store.dragOutCompleted(id: id)
        #expect(store.items.isEmpty)
        #expect(store.recentlyClearedIDs == [id])
    }

    @Test func clearAll() {
        let store = makeStore()
        _ = store.addText("A")
        _ = store.addText("B")
        store.clearAll()
        #expect(store.items.isEmpty)
    }

    @Test func remove() {
        let store = makeStore()
        _ = store.addText("A")
        store.remove(id: store.items[0].id)
        #expect(store.items.isEmpty)
    }

    // MARK: - Ordering / filter

    @Test func newestFirst() {
        let now = Date()
        let items = [
            ShelfItem(bookmark: Data(), name: "old", isDirectory: false, isText: true, addedAt: now.addingTimeInterval(-100)),
            ShelfItem(bookmark: Data(), name: "new", isDirectory: false, isText: true, addedAt: now)
        ]
        #expect(ShelfOrdering.newestFirst(items).first?.name == "new")
    }

    @Test func matchingFilter() {
        let items = SampleShelf.items()
        #expect(ShelfOrdering.matching(items, query: "photo").count == 1)
        #expect(ShelfOrdering.matching(items, query: "  ").count == items.count)
        #expect(ShelfOrdering.matching(items, query: "zzz").count == 0)
    }

    // MARK: - Sample data

    @Test func sampleItems() {
        let sample = SampleShelf.items()
        #expect(sample.count == SampleShelf.sampleNames.count)
        #expect(sample.allSatisfy { !$0.name.isEmpty })
    }

    @Test func sampleNamesAreUnique() {
        #expect(Set(SampleShelf.sampleNames).count == SampleShelf.sampleNames.count)
    }

    // MARK: - Persisted preference

    @Test func clearAfterDragOutPersists() {
        let store = makeStore(clear: true)
        #expect(store.clearAfterDragOut)
        let reloaded = ShelfStore(defaults: defaults)
        #expect(reloaded.clearAfterDragOut)
    }
}
