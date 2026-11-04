import Testing
@testable import MASKit

// swift-testing, not XCTest: Command Line Tools ship Testing.framework but no XCTest.
@Test func passRequiresAllChecks() {
    let ok = SmokeReport(app: "A", bundleID: "b", version: "1", checks: [
        SmokeCheck(name: "x", pass: true, detail: "1")
    ])
    #expect(ok.pass)
    let bad = SmokeReport(app: "A", bundleID: "b", version: "1", checks: [
        SmokeCheck(name: "x", pass: true, detail: "1"),
        SmokeCheck(name: "y", pass: false, detail: "0")
    ])
    #expect(!bad.pass)
}

@Test func emptyChecksFail() {
    #expect(!SmokeReport(app: "A", bundleID: "b", version: "1", checks: []).pass)
}

@Test func launchModeParsing() {
    #expect(LaunchMode.current(["x", "--smoke"]) == .smoke)
    #expect(LaunchMode.current(["x", "--screenshots"]) == .screenshots)
    #expect(LaunchMode.current(["x"]) == .normal)
}
