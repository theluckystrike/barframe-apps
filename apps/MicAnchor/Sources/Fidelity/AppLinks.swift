import AppKit
import SwiftUI

@MainActor enum AppLinks {
    enum Destination: Equatable { case web(URL), local }
    static func destination(_ value: String?) -> Destination {
        guard let value, !value.contains("{"), !value.contains("}"),
              let url = URL(string: value), url.scheme == "https",
              let host = url.host, !host.isEmpty, !host.contains("{"), !host.contains("}"), !host.contains("%") else { return .local }
        return .web(url)
    }
    static var privacyDestination: Destination { destination(Bundle.main.object(forInfoDictionaryKey: "MASPrivacyPolicyURL") as? String ?? "https://{DOMAIN}/micanchor/privacy/") }
    static var supportDestination: Destination { destination(Bundle.main.object(forInfoDictionaryKey: "MASSupportURL") as? String ?? "https://{DOMAIN}/micanchor/support/") }
    static var privacyURL: URL? { if case .web(let url) = privacyDestination { return url }; return nil }
    static var supportURL: URL? { if case .web(let url) = supportDestination { return url }; return nil }
    static var copyright: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        return configured.flatMap { $0.contains("{") || $0.contains("}") ? nil : $0 } ?? "© 2026 Michael Lip"
    }
    // Compiled into the app; available offline without a configured website.
    static let privacyText = """
    Michael Lip provides MicAnchor. MicAnchor reads device names, identifiers, transport types, microphone availability, the default input and output, and lid state. It changes only the system default input. It does not record or listen to audio.

    Guard preferences, microphone priorities, the last 20 confirmed switches (device names, reasons and times), intervention counts and times, temporary Bluetooth allowance and guard pause stay in local preferences on this Mac. Clear history in Settings. Sample mode uses isolated temporary preferences. Launch at login is optional and starts off.

    MicAnchor collects and sends no data. It has no analytics, tracking, advertising, account or network service. Michael Lip does not receive your device details or preferences. Browser links open external pages when a website is configured. The support website is not configured in this build; use the local Support instructions.

    Delete the app's local data to remove saved preferences. If you contact support after a contact destination is configured, Michael Lip receives only the information you choose to send and uses it to answer your request.
    """
    static let supportText = """
    Open Settings to choose a preferred microphone or reorder saved priorities. Connect a separate available built-in or wired microphone. MicAnchor replaces Bluetooth defaults and unavailable inputs; available non-Bluetooth defaults stay selected.

    Use Retry / Refresh after device changes. Allow Bluetooth mic for 1 hour pauses protection temporarily; Resume Guard ends that allowance. Repeated input changes pause protection for five minutes. Turn Guard off to stop automatic changes. Apps with their own microphone selection may ignore the system default.

    Open Sample mode from the menu to test switching, priorities, allowance, pause and history without changing system audio or using an account. Sample Settings exposes the same priority and history controls.

    The support website and contact address are not configured in this build. No account or credentials are needed. Version 1.0.0 · Michael Lip.
    """
    static func credits(_ introduction: String = "") -> NSAttributedString {
        let text = NSMutableAttributedString(string: introduction.isEmpty ? "" : introduction + "\n\n")
        if let privacyURL { text.append(NSAttributedString(string: "Privacy Policy", attributes: [.link: privacyURL])) }
        if let supportURL { text.append(NSAttributedString(string: "    Support", attributes: [.link: supportURL])) }
        if privacyURL == nil || supportURL == nil {
            text.append(NSAttributedString(string: "\nPrivacy Policy and Support are available in Settings."))
        }
        return text
    }
}

struct PolicySupportLinks: View {
    enum LocalPage: String, Identifiable { case privacy, support; var id: String { rawValue } }
    @State private var localPage: LocalPage?
    private func open(_ destination: AppLinks.Destination, fallback: LocalPage) {
        if case .web(let url) = destination { NSWorkspace.shared.open(url) }
        else { localPage = fallback }
    }
    var body: some View {
        HStack {
            Button("Privacy Policy") { open(AppLinks.privacyDestination, fallback: .privacy) }
            Button("Support") { open(AppLinks.supportDestination, fallback: .support) }
            Button("Read local privacy policy") { localPage = .privacy }
        }.sheet(item: $localPage) { page in
            VStack(alignment: .leading, spacing: 16) {
                Text(page == .privacy ? "MicAnchor Privacy Policy" : "MicAnchor Support").font(.title)
                ScrollView { Text(page == .privacy ? AppLinks.privacyText : AppLinks.supportText).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                Button("Done") { localPage = nil }
            }.padding(24).frame(width: 500, height: 480)
        }
    }
}
