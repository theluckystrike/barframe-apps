import Foundation
import Testing
import RevPulseCore
import MASKit

struct LaunchModeTests {
    @Test func smokeArg() {
        #expect(LaunchMode.current(["RevPulse", "--smoke"]) == .smoke)
    }
    @Test func screenshotsArg() {
        #expect(LaunchMode.current(["RevPulse", "--screenshots"]) == .screenshots)
    }
    @Test func normal() {
        #expect(LaunchMode.current(["RevPulse"]) == .normal)
    }
}
