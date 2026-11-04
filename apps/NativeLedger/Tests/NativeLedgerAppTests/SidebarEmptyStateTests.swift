import AppKit
import SwiftUI
import Testing
import LedgerCore
@testable import NativeLedger

@MainActor @Suite struct SidebarEmptyStateTests {
    private func expectAllSections(_ content: SidebarContent) {
        #expect(SidebarContent.recentTitle == "Recent changes")
        #expect(content.recentCount == 0)
        #expect(content.folders.title == "Watched folders" && content.folders.rowCount == 0)
        #expect(content.folders.placeholder == "No watched folders yet")
        #expect(content.apps.title == "Tracked apps" && content.apps.rowCount == 0)
        #expect(content.apps.placeholder == "No apps yet")
        #expect(content.footer == "Open Sample")
    }

    @Test func emptyModelHasEverySection() {
        expectAllSections(SidebarContent(model: LedgerModel(store: nil, seed: [])))
    }

    @Test func sectionsReturnAfterLeaveSample() {
        let state = AppState(live: LedgerModel(store: nil, seed: []), alerts: AlertController(poster: FakeNotifier(answer: .denied), defaults: freshDefaults()))
        state.openSample()
        let sample = SidebarContent(model: state.current)
        #expect(sample.folders.placeholder == nil && sample.apps.placeholder == nil && sample.footer != "Open Sample")
        state.leaveSample()
        expectAllSections(SidebarContent(model: state.current))
    }

    @Test func emptyStateNeverGrowsTheWindow() {
        let model = LedgerModel(store: nil, seed: [])
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: LedgerSplitView(model: model))
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize.height <= 760, "fitting height \(host.fittingSize.height)")
            let empty = NSHostingView(rootView: EmptyStateView(model: model, openSample: {}))
            #expect(empty.fittingSize.height <= 760, "empty state fitting height \(empty.fittingSize.height)")
        }
    }

    @Test func flatSidebarRendersInLightAndDark() throws {
        let model = LedgerModel(store: nil, seed: [])
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: Sidebar(model: model, actions: SampleActions(), staleDays: 30, flat: true)
                .frame(width: 280, height: 600).background(Palette.sidebar))
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(x: 0, y: 0, width: 280, height: 600)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            // Some pixels differ from the background: the rows were drawn.
            let background = rep.colorAt(x: 2, y: 300)
            var differing = 0
            for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 4) where rep.colorAt(x: x, y: y) != background { differing += 1 }
            }
            #expect(differing > 50, "\(appearance.rawValue): \(differing) drawn pixels")
        }
    }
}
