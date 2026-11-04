import SwiftUI
import HushKeyCore

struct ControlsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Microphone controls").font(.title2.bold())
                Spacer()
                if model.sampleMode { Text("Sample").foregroundStyle(.secondary) }
            }
            Text(model.currentDefault()?.name ?? "No input device").font(.headline)
            Text(model.isDefaultMuted() ? "Muted" : "Open")
                .font(.largeTitle.bold()).foregroundStyle(model.isDefaultMuted() ? .red : .green)
            Button(model.isDefaultMuted() ? "Unmute Microphone" : "Mute Microphone") { model.toggleDefaultMute() }
            if let volume = model.currentVolume() {
                Slider(value: Binding(get: { Double(model.currentVolume() ?? volume) }, set: { model.setVolume(Float($0)) }), in: 0...1) {
                    Text("Input volume")
                }
                Text("Input volume \(Int(volume * 100))%").font(.caption)
            }
            Picker("Default microphone", selection: Binding(get: { model.currentDefault()?.id ?? "" }, set: { model.selectDefaultDevice($0) })) {
                ForEach(model.devices()) { Text($0.name).tag($0.id) }
            }
            Divider()
            Toggle("Push-to-talk (hold to unmute)", isOn: Binding(get: { model.pushToTalk }, set: { model.setPushToTalk($0) }))
            Text(model.pttActive ? "LIVE. Release shortcut to mute" : "Hold your global shortcut to talk when enabled.").font(.callout)
            Toggle("Show floating mic badge", isOn: Binding(get: { model.showBadge }, set: { model.setShowBadge($0) }))
            Toggle("Sample mode", isOn: Binding(get: { model.sampleMode }, set: { model.setSampleMode($0) }))
            Button("Run Self Test") { _ = model.runSelfTestChecks() }
            Text(model.lastOutcome).font(.caption).fixedSize(horizontal: false, vertical: true)
            Text("Controls the system default input. Check which input your calling app uses.").font(.caption).foregroundStyle(.secondary)
            PolicySupportLinks()
        }.padding(24).frame(width: 520)
    }
}
