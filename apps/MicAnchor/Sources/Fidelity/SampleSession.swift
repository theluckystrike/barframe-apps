import SwiftUI
import CoreAudio
import FidelityCore

/// Simulated hardware only. No CoreAudio calls or standard preferences.
final class SampleHardware: AudioHardwareAccess {
    var input: UInt32 = 12
    var skippedIDs: [UInt32] { [] }
    var inventory: [AudioDevice] = (1...12).map { index in
        let transport: Transport = index == 12 ? .bluetooth : (index == 1 ? .builtIn : .usb)
        let name = index == 12 ? "Sample Bluetooth headset" : "Sample Microphone \(index)"
        return AudioDevice(id: UInt32(index), uid: "sample-\(index)", name: name, transport: transport, inputChannels: 1, outputChannels: index == 12 ? 2 : 0)
    }
    func devices() throws -> [AudioDevice] { inventory }
    func defaultInput() throws -> UInt32 { input }
    func defaultOutput() throws -> UInt32 { 12 }
    func lidClosed() -> Bool? { false }
    func setInput(_ id: UInt32) throws { input = id }
    func startListening(_ changed: @escaping () -> Void) throws {}
    func stopListening() -> [OSStatus] { [] }
}

@MainActor final class SampleSession: ObservableObject {
    let hardware = SampleHardware()
    let defaults: UserDefaults
    let suite: String
    let model: GuardModel
    init() {
        suite = "MicAnchor.Sample." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        model = GuardModel(hardware: hardware, defaults: defaults, scheduleEvents: false)
        model.dismissIntroduction()
        model.refresh(enforce: true)
    }
    func simulateTakeover() { hardware.input = 12; model.refresh(enforce: true) }
    func close() { model.stop(); defaults.removePersistentDomain(forName: suite) }
}

struct SampleSessionView: View {
    @StateObject private var session = SampleSession()
    var body: some View {
        VStack {
            Text("Sample · simulated audio only").font(.headline)
            Button("Simulate Bluetooth takeover") { session.simulateTakeover() }
            GuardPopover(model: session.model, sampleSession: true)
        }.padding().onDisappear { session.close() }
    }
}
