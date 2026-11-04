import Foundation
import Testing
@testable import StepQuayCore

func queue(_ minutes: [Double] = [5, 10, 15]) throws -> Queue {
    var q = Queue()
    for (i, value) in minutes.enumerated() { try q.add(title: "Action \(i)", minutes: value) }
    return q
}
@Test func persistenceRoundTrip() throws { var q = try queue(); try q.start(now: 10); try q.interrupt(note: "Next paragraph", now: 50); #expect(try Queue.decoded(q.encoded()) == q) }
@Test func blankTitleRejected() throws { var q = Queue(); #expect(throws: QueueError.invalidTitle) { try q.add(title: " \n ", minutes: 5) }; #expect(q.actions.isEmpty) }
@Test func titleTrimmed() throws { var q = Queue(); try q.add(title: "  Next  ", minutes: 5); #expect(q.actions.first?.title == "Next") }
@Test func zeroDurationRejected() { var q = Queue(); #expect(throws: QueueError.invalidDuration) { try q.add(title: "Next", minutes: 0) } }
@Test func negativeDurationRejected() { var q = Queue(); #expect(throws: QueueError.invalidDuration) { try q.add(title: "Next", minutes: -1) } }
@Test func nonFiniteDurationRejected() { var q = Queue(); #expect(throws: QueueError.invalidDuration) { try q.add(title: "Next", minutes: .infinity) } }
@Test func excessiveDurationRejected() { var q = Queue(); #expect(throws: QueueError.invalidDuration) { try q.add(title: "Next", minutes: 1441) } }
@Test func budgetExactBoundary() throws { var q = try queue(); q.budget = 15 * 60; #expect(q.fittingIDs.count == 2) }
@Test func budgetDoesNotSkipOverflow() throws { var q = try queue([20, 2, 1]); q.budget = 5 * 60; #expect(q.fittingIDs.isEmpty); #expect(q.actions.count == 3) }
@Test func budgetChangeRecomputes() throws { var q = try queue(); q.budget = 300; #expect(q.fittingIDs.count == 1); q.budget = 1800; #expect(q.fittingIDs.count == 3) }
@Test func partialRemainingFits() throws { var q = try queue([10, 3]); try q.start(now: 0); q.tick(420); q.budget = 360; #expect(q.fittingIDs.count == 2) }
@Test func startNextUsesQueueOrder() throws { var q = try queue(); try q.start(now: 100); #expect(q.current?.id == q.actions.first?.id) }
@Test func twoConcurrentActionsRejected() throws { var q = try queue(); try q.start(now: 0); #expect(throws: QueueError.busy) { try q.start(q.actions[1].id, now: 20) } }
@Test func monotonicElapsedTime() throws { var q = try queue([5]); try q.start(now: 100); q.tick(125); q.tick(130); #expect(q.current?.active == 30); #expect(q.current?.remaining == 270) }
@Test func backwardClockDoesNotChargeOrResetBaseline() throws { var q = try queue([5]); try q.start(now: 100); q.tick(90); q.tick(120); #expect(q.current?.active == 20) }
@Test func interruptionRequiresNote() throws { var q = try queue(); try q.start(now: 0); #expect(throws: QueueError.invalidNote) { try q.interrupt(note: "  ", now: 30) }; #expect(q.current?.phase == .running); #expect(q.current?.active == 0) }
@Test func longNoteRejected() throws { var q = try queue(); try q.start(now: 0); #expect(throws: QueueError.invalidNote) { try q.interrupt(note: String(repeating: "n", count: 241), now: 30) } }
@Test func pausedClockFrozen() throws { var q = try queue(); try q.start(now: 0); try q.interrupt(note: "Check final link", now: 30); q.tick(300); #expect(q.current?.active == 30); #expect(q.current?.notes.last?.note == "Check final link") }
@Test func resumeExcludesInterruptionTime() throws { var q = try queue(); try q.start(now: 0); try q.interrupt(note: "Continue here", now: 60); try q.resume(now: 600); q.tick(630); #expect(q.current?.active == 90) }
@Test func completionRecordsOriginalEstimateAndActive() throws { var q = try queue([5]); try q.start(now: 0); try q.finish(now: 350); #expect(q.history[0].action.estimate == 300); #expect(q.history[0].action.active == 350); #expect(q.current == nil) }
@Test func completionUndoRestoresPositionAndNote() throws { var q = try queue(); let id = q.actions[1].id; try q.start(id, now: 0); try q.interrupt(note: "Final check", now: 80); try q.finish(now: 90); try q.undo(); #expect(q.actions[1].id == id); #expect(q.actions[1].active == 80); #expect(q.actions[1].notes.last?.note == "Final check"); #expect(q.history.isEmpty) }
@Test func timerDoesNotAutoComplete() throws { var q = try queue([1]); try q.start(now: 0); q.tick(120); #expect(q.current?.remaining == -60); #expect(q.actions.count == 1); #expect(q.history.isEmpty) }
@Test func reviseOverrunKeepsActiveAndOriginalEstimate() throws { var q = try queue([1]); try q.start(now: 0); q.tick(120); try q.reviseRemaining(minutes: 3, now: 130); #expect(q.current?.remaining == 180); #expect(q.current?.active == 130); #expect(q.current?.estimate == 60) }
@Test func invalidRevisionDoesNotChargeTime() throws { var q = try queue([1]); try q.start(now: 0); #expect(throws: QueueError.invalidDuration) { try q.reviseRemaining(minutes: 0, now: 50) }; #expect(q.current?.active == 0) }
@Test func deferRetainsEffortAndMovesToEnd() throws { var q = try queue(); let id = q.actions[0].id; try q.start(now: 0); try q.deferCurrent(now: 60); #expect(q.actions.last?.id == id); #expect(q.actions.last?.remaining == 240); #expect(q.current == nil) }
@Test func reorderPreservesActions() throws { var q = try queue(); let id = q.actions[2].id; q.move(id, by: -1); #expect(q.actions[1].id == id); #expect(q.actions.count == 3) }
@Test func cannotDeleteCurrentAction() throws { var q = try queue(); try q.start(now: 0); q.delete(q.current!.id); #expect(q.actions.count == 3) }
@Test func sleepPausesAndWakeRequiresResume() throws { var q = try queue([5]); try q.start(now: 20); q.sleep(now: 50); q.tick(5000); #expect(q.current?.phase == .paused); #expect(q.current?.active == 30); #expect(q.current?.notes.last?.note == "Paused for sleep"); try q.resume(now: 5010); q.tick(5020); #expect(q.current?.active == 40) }
@Test func sleepAlreadyPausedDoesNotAddNotes() throws { var q = Queue.sample(); let notes = q.current!.notes; q.sleep(now: 100); #expect(q.current?.notes == notes) }
@Test func relaunchDoesNotChargeOfflineTime() throws { var q = try queue(); try q.start(now: 0); q.tick(70); q = try Queue.decoded(q.encoded()); q.recoverAfterLaunch(); q.tick(7000); #expect(q.current?.active == 70); #expect(q.current?.phase == .paused); #expect(q.lastTick == nil) }
@Test func clearHistoryIndependentOfQueue() throws { var q = try queue(); try q.start(now: 0); try q.finish(now: 10); let actions = q.actions; q.history = []; #expect(q.actions == actions) }
@Test func retentionExpiresOnlyOldHistory() throws { var q = try queue([1, 1]); let now = Date(timeIntervalSince1970: 20000000); try q.start(now: 0); try q.finish(now: 10, date: now.addingTimeInterval(-40 * 86400)); try q.start(now: 20); try q.finish(now: 30, date: now); q.retainHistory(days: 30, now: now); #expect(q.history.count == 1) }
@Test func retainForeverKeepsHistory() throws { var q = try queue([1]); try q.start(now: 0); try q.finish(now: 10, date: Date(timeIntervalSince1970: 0)); q.retainHistory(days: 0); #expect(q.history.count == 1) }
@Test func sampleIsolation() throws { let live = try queue([2]); var sample = Queue.sample(); try sample.resume(now: 0); try sample.finish(now: 60); #expect(live.actions.count == 1); #expect(live.history.isEmpty); #expect(sample.history.count == 1) }
@Test func sampleIncludesRecoveryOverrunAndOverflow() { let q = Queue.sample(); #expect(q.current?.phase == .paused); #expect(q.current?.notes.last?.note == "Continue at the support link"); #expect(q.actions.first!.remaining < 0); #expect(!q.fittingIDs.contains(q.actions.last!.id)) }
@Test func malformedPersistenceRejected() { #expect(throws: (any Error).self) { try Queue.decoded(Data("{broken}".utf8)) } }
@Test func durationFormatter() { #expect(TimeText.clock(60) == "01:00"); #expect(TimeText.clock(-61) == "01:01") }

@Test func deferredInterruptionShowsNoteAndRequiresExplicitResume() throws {
    var q = try queue([5]); try q.start(now: 0)
    try q.interrupt(note: "Resume at paragraph", now: 30)
    let remaining = q.current!.remaining
    try q.deferCurrent(now: 40)
    #expect(q.actions.first?.notes.last?.note == "Resume at paragraph")
    try q.start(now: 1000)
    #expect(q.current?.phase == .paused); #expect(q.lastTick == nil)
    q.tick(2000); #expect(q.current?.remaining == remaining)
    try q.resume(now: 2000); q.tick(2010)
    #expect(q.current?.remaining == remaining - 10)
}
@Test func undoInterruptedCompletionRequiresExplicitResume() throws {
    var q = try queue([5]); try q.start(now: 0)
    try q.interrupt(note: "Check conclusion", now: 20); try q.finish(now: 30); try q.undo()
    let restored = try Queue.decoded(q.encoded())
    #expect(restored.actions.first?.notes.last?.note == "Check conclusion")
    try q.start(now: 300); q.tick(600)
    #expect(q.current?.phase == .paused); #expect(q.current?.active == 20)
    try q.resume(now: 600); q.tick(610); #expect(q.current?.active == 30)
}
@Test func undoUninterruptedCompletionAlsoRequiresExplicitResume() throws {
    var q = try queue([5]); try q.start(now: 0); try q.finish(now: 20); try q.undo(); try q.start(now: 300)
    #expect(q.current?.phase == .paused); #expect(q.current?.notes.last?.note == "Completion undone. Review your place before resuming.")
    q.tick(600); #expect(q.current?.active == 20)
}
