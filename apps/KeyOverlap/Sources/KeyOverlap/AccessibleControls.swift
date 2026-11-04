import SwiftUI

struct LabeledButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title; self.role = role; self.action = action
    }
    var body: some View { Button(title, role: role, action: action).accessibilityLabel(title) }
}
struct LabeledToggle: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }
    var body: some View { Toggle(title, isOn: $isOn).accessibilityLabel(title) }
}
