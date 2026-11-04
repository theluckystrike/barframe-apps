import SwiftUI

public enum PopoverLayout {
    public static func maximumHeight(visibleHeight: Double) -> Double { min(740, max(300, visibleHeight - 60)) }
    public static func bodyHeight(visibleHeight: Double) -> Double { max(60, maximumHeight(visibleHeight: visibleHeight) - 250) }
}

struct ControlFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    func measureControl(_ name: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: ControlFrames.self, value: [name: geometry.frame(in: .named("popover"))])
        })
    }
}
