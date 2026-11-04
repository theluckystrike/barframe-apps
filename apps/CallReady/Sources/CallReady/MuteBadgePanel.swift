import AppKit

/// Floating on-screen badge showing mic state (muted / open / push-to-talk).
/// Non-activating panel, floats above apps, positioned near the bottom edge.
final class MicBadgePanel: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 132, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false

        let box = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 132, height: 40))
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        label.frame = box.bounds
        label.alignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.autoresizingMask = [.width, .height]
        box.addSubview(label)
        contentView = box
    }

    func position() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.minY + 48))
        }
    }

    func show(state muted: Bool, pushToTalkActive: Bool) {
        if pushToTalkActive {
            label.stringValue = "🎙 LIVE (hold)"
        } else if muted {
            label.stringValue = "🔒 Muted"
        } else {
            label.stringValue = "🎙 Open"
        }
        position()
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
