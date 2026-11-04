import AppKit
import Testing
@testable import RevPulse

struct GoalSymbolTests {
    @Test @MainActor func goalSymbolExistsOnThisSystem() {
        #expect(NSImage(systemSymbolName: PopoverView.goalSymbolName, accessibilityDescription: nil) != nil)
    }
}
