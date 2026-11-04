import SwiftUI

/// SwiftUI shapes keep the actual control available to both the app and ImageRenderer.
struct InspectorToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button { configuration.isOn.toggle() } label: {
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 30, height: 18)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Include built-in USB devices")
            .accessibilityValue(configuration.isOn ? "On" : "Off")
        }
    }
}
