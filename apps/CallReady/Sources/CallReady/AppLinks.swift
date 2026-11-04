import AppKit
import SwiftUI

enum ProductInfo {
    static let name = "CallReady"
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static let copyright = "© 2026 Michael Lip"
}

enum AppLinks {
    static let privacy = URL(string: "https://barframe.com/apps/callready/privacy/")!
    static let support = URL(string: "https://barframe.com/apps/callready/support/")!
    static let calendarPrivacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    static func credits() -> NSAttributedString {
        let text = NSMutableAttributedString(string: ProductInfo.copyright + "\n\n")
        text.append(NSAttributedString(string: "Privacy Policy", attributes: [.link: privacy]))
        text.append(NSAttributedString(string: "    "))
        text.append(NSAttributedString(string: "Support", attributes: [.link: support]))
        return text
    }
}

@MainActor func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: ProductInfo.name, .applicationVersion: ProductInfo.version,
        .version: ProductInfo.build, .credits: AppLinks.credits()
    ])
}

struct PolicySupportLinks: View {
    var body: some View {
        HStack(spacing: 16) {
            Link("Privacy Policy", destination: AppLinks.privacy)
            Link("Support", destination: AppLinks.support)
        }.accessibilityIdentifier("policySupportLinks")
    }
}
