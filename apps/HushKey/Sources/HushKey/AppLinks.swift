import AppKit
import SwiftUI
import MASKit

@MainActor enum AppLinks {
    static var privacyURL: URL? { resolvedURL("MASPrivacyPolicyURL", path: privacyPath) }
    static var supportURL: URL? { resolvedURL("MASSupportURL", path: supportPath) }
    static let privacyPath = "/mac-apps/hushkey/privacy/"
    static let supportPath = "/mac-apps/hushkey/support/"
    static func resolvedURL(_ key: String, path: String, bundle: Bundle = .main) -> URL? {
        let resources = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("HushKey_HushKey.bundle")) } ?? Bundle.module
        let local = resources.url(forResource: path == privacyPath ? "privacy" : "support", withExtension: "html", subdirectory: "Resources")
        guard path == privacyPath || path == supportPath else { return nil }
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String,
              !raw.contains("{"), !raw.contains("}"), !raw.lowercased().contains("%7b"),
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              !raw.isEmpty else { return local }
        return url
    }
}

struct PolicySupportLinks: View {
    var body: some View {
        HStack(spacing: 16) {
            if let privacy = AppLinks.privacyURL { Link("Privacy Policy", destination: privacy) }
            if let support = AppLinks.supportURL { Link("Support", destination: support) }
        }.font(.callout).accessibilityIdentifier("policySupportLinks")
    }
}
