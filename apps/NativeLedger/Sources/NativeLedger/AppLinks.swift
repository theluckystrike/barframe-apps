import AppKit
import SwiftUI

enum ProductInfo {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "NativeLedger" }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "4" }
}

/// The privacy policy and the support page. The build writes their web addresses to Info.plist; a copy of each
/// page ships inside the app for when the address is missing or not the expected https page.
enum PolicyPage: CaseIterable {
    case privacy, support

    var infoKey: String {
        switch self {
        case .privacy: "MASPrivacyPolicyURL"
        case .support: "MASSupportURL"
        }
    }
    /// The only path the web address may have.
    var sitePath: String {
        switch self {
        case .privacy: "/apps/nativeledger/privacy/"
        case .support: "/apps/nativeledger/support/"
        }
    }
    var bundledFile: String {
        switch self {
        case .privacy: "privacy"
        case .support: "support"
        }
    }
    var title: String {
        switch self {
        case .privacy: "Privacy Policy"
        case .support: "Support"
        }
    }
}

@MainActor enum AppLinks {
    static let resourceBundleName = "NativeLedger_NativeLedger.bundle"

    static var privacyURL: URL? { address(of: .privacy) }
    static var supportURL: URL? { address(of: .support) }

    /// The web address from Info.plist when it passes `webAddress`, otherwise the page bundled with the app.
    static func address(of page: PolicyPage, info: [String: Any]? = Bundle.main.infoDictionary) -> URL? {
        if let text = info?[page.infoKey] as? String, let url = webAddress(text, path: page.sitePath) { return url }
        return bundledPage(page)
    }

    /// An https address with a host and exactly `path`, without a query, a fragment or template braces.
    static func webAddress(_ text: String, path: String) -> URL? {
        if text.rangeOfCharacter(from: CharacterSet(charactersIn: "{}%")) != nil { return nil }
        guard let parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.path == path,
              parts.query == nil, parts.fragment == nil, parts.user == nil else { return nil }
        return parts.url
    }

    /// The SwiftPM resource bundle: Contents/Resources in the built app, or next to a bare executable.
    static var resourceBundle: Bundle? {
        let main = Bundle.main
        let folders = [main.resourceURL, main.bundleURL, main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        return folders.lazy.compactMap { Bundle(url: $0.appendingPathComponent(resourceBundleName)) }.first
    }

    static func bundledPage(_ page: PolicyPage) -> URL? {
        guard let bundle = resourceBundle else { return nil }
        for folder in ["Resources", nil] as [String?] {
            if let url = bundle.url(forResource: page.bundledFile, withExtension: "html", subdirectory: folder) { return url }
        }
        return nil
    }

    static func credits() -> NSAttributedString {
        let text = NSMutableAttributedString(string: "A tamper evident ledger of app updates.\n\n")
        let links = PolicyPage.allCases.compactMap { page in address(of: page).map { (page.title, $0) } }
        for (index, link) in links.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "    ")) }
            text.append(NSAttributedString(string: link.0, attributes: [.link: link.1]))
        }
        return text
    }
}

struct PolicySupportLinks: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(PolicyPage.allCases, id: \.self) { page in
                if let url = AppLinks.address(of: page) {
                    Link(page.title, destination: url).accessibilityHint(page == .privacy ? "Opens the privacy policy" : "Opens support")
                }
            }
        }.font(.callout).accessibilityIdentifier("policySupportLinks")
    }
}

@MainActor func showAbout() {
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: ProductInfo.name, .applicationVersion: ProductInfo.version, .version: ProductInfo.build,
        .credits: AppLinks.credits(),
        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026"
    ])
}
