import AppKit

@MainActor enum AppLinks {
    static var privacy: URL? { configuredURL("MASPrivacyPolicyURL", fallback: "https://{DOMAIN}/relaynook/privacy/") }
    static var support: URL? { configuredURL("MASSupportURL", fallback: "https://{DOMAIN}/relaynook/support/") }
    static func configuredURL(_ key: String, fallback: String, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> URL? {
        let raw = info[key] as? String ?? fallback
        guard !raw.contains("{"), !raw.contains("}"), let url = URL(string: raw),
              url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }
    private static var windows: [NSWindow] = []
    static func showDocument(privacyPolicy: Bool) {
        if let url = privacyPolicy ? privacy : support { NSWorkspace.shared.open(url); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = privacyPolicy ? "Privacy Policy" : "Support"
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.isSelectable = true
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.font = .systemFont(ofSize: 14); text.textContainerInset = NSSize(width: 20, height: 20)
        text.string = privacyPolicy ? localPrivacy : localSupport
        scroll.documentView = text; window.contentView = scroll
        windows.append(window); window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    static func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "RelayNook", .applicationVersion: "1.0.0",
            .credits: NSAttributedString(string: "Privacy Policy and Support are available in Settings."),
            .init(rawValue: "Copyright"): "Copyright © 2026 Michael Lip"
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
    static let localPrivacy = """
# RelayNook privacy policy

Michael Lip provides RelayNook. For help, use Support in Settings or email support@barframe.com.

RelayNook receives event text from applications on your device through a local URL. Event text includes an agent name, event kind, title, project, and session identifier. The app stores up to 200 events and waiting session identifiers in its private container. Clear deletes event history and waiting session identifiers. The rejected event count remains. Rejected URL text is not stored.

Older history can contain session identifiers without agent identity. The app keeps them separately from the waiting count. Dismiss unresolved sessions deletes only those identifiers. Clear also deletes them.

The app creates a random installation token and stores it in private preferences on your device. Each event must include this token. Keep copied setup commands private. Regenerate token replaces the token and invalidates previously installed hooks. The app also stores notification preferences locally.

Notification content passes to the macOS notification system after you enable notifications. Control delivery in System Settings. Select event kinds and sound in RelayNook Settings. Clear delivered notifications in Notification Center.

RelayNook sends no event data to Michael Lip. It uses no account, analytics, tracking, advertising, or remote event service. It does not read agent configuration or transcript files. Copy places text on the clipboard only when you select Copy. Privacy, support, and documentation links open in your browser when selected. Browser visits follow the destination site's privacy practices.

"""
    static let localSupport = """
RelayNook support

No account or hook installation is needed. Open the menu bar and enable Sample mode to explore fictional events; turn it off to restore your history. Send test event tests local processing. In Settings, Copy Terminal test command tests system URL delivery without installing anything. Change kind=waiting to done, error, or info to try each event kind.

Enable notifications in Settings and check macOS notification settings and Focus. Regenerate token invalidates old commands; copy fresh ones. Optional agent hooks require manual configuration and a separate real-agent test.

Clear removes local history; Notification Center manages delivered notifications. For support, email support@barframe.com or use the hosted support page. Publisher: Michael Lip.
"""
}
