import Foundation
import MASKit
import MeetNextCore

/// Smoke run: builds a SmokeReport from the sample model and writes smoke.json
/// into the sandbox container home (proves App Sandbox is active).
enum SelfTest {
    @MainActor
    static func run(writeSmoke: Bool) -> Int32 {
        let model = AppModel()
        model.toggleSample(true)
        let events = model.events
        let next = model.nextEvent
        var checks: [SmokeCheck] = []

        checks.append(SmokeCheck(
            name: "sample events populated",
            pass: !events.isEmpty,
            detail: "\(events.count) fixture events"))

        checks.append(SmokeCheck(
            name: "next event available",
            pass: next != nil,
            detail: next.map { "next: \($0.title)" } ?? "none"))

        checks.append(SmokeCheck(
            name: "timeline blocks present",
            pass: !DayTimeline.blocks(events: events, dayStart: SampleCalendar.dayWindow(for: Date()).start,
                                      dayEnd: SampleCalendar.dayWindow(for: Date()).end).isEmpty,
            detail: "day timeline has busy/free blocks"))

        checks.append(SmokeCheck(
            name: "menu bar title includes Sample",
            pass: model.menuBarTitle.hasPrefix("Sample ·"),
            detail: model.menuBarTitle))

        checks.append(SmokeCheck(
            name: "join parser finds link in sample data",
            pass: events.contains { JoinParser.firstJoinLink(in: $0.searchText) != nil },
            detail: "Zoom/Meet/Teams/Webex link detected"))

        let report = SmokeReport(
            app: "MeetNext",
            bundleID: "com.michaellip.meetnext",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
            checks: checks)

        if writeSmoke {
            do {
                let url = try report.write()
                FileHandle.standardError.write(Data("smoke.json written to \(url.path)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("smoke.json write failed: \(error.localizedDescription)\n".utf8))
                return 1
            }
        }
        for check in checks where !check.pass {
            FileHandle.standardError.write(Data("SMOKE FAIL: \(check.name): \(check.detail)\n".utf8))
        }
        return report.pass ? 0 : 1
    }
}
