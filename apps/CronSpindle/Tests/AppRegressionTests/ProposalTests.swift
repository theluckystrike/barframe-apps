import Foundation
import Testing
import CronSpindleCore
@testable import CronSpindle

@Test @MainActor func editingDuringComparisonDiscardsOldResult() async throws {
    let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model=Model(file:file)
    model.jobs=Fixtures.jobs
    model.start=Fixtures.start
    model.days=1
    model.select(Fixtures.jobs[1])
    model.expression="0 4 * * *"
    model.analyze(compare:true)
    #expect(model.busy)
    model.expression="0 5 * * *"
    model.draftChanged()
    #expect(!model.busy)
    try await Task.sleep(for:.milliseconds(50))
    #expect(model.proposed == nil)
    #expect(model.jobs == Fixtures.jobs)
    #expect(model.cancelled)
}

@Test @MainActor func leavingSampleClearsItsDraftAndPendingResult() async throws {
    let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model=Model(file:file)
    model.toggleSample(true)
    model.toggleSample(false)
    try await Task.sleep(for:.milliseconds(50))
    #expect(model.jobs.isEmpty)
    #expect(model.result == nil)
    #expect(model.proposed == nil)
    #expect(model.name.isEmpty)
    #expect(!model.sample)
}
