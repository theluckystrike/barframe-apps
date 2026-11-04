import SwiftUI
import AgentPingCore

enum SampleContent {
    static let token = "00000000000000000000000000000000"
    static let headlines = ["Keep every agent in view", "Connect agents to your workflow", "Control your incoming agent events"]
    static var history: History {
        var result = History()
        let titles = ["Review the next step", "Checks completed", "Build needs attention", "Index updated", "Approve the change", "Documentation complete", "Retry the check", "Plan is ready", "Choose the next task", "Tests completed"]
        for i in 0..<10 {
            result.receive(AgentEvent(agent: "Sample Agent \(i + 1)", kind: EventKind.allCases[i % 4], title: titles[i], project: "Sample Project", session: "sample-\(i + 1)", receivedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i))))
        }
        return result
    }
}
