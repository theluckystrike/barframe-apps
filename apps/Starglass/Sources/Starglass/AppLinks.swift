import AppKit
import SwiftUI
import MASKit
import StarglassCore

@MainActor enum AppLinks {
    static var privacyURL: URL? { resolvedURL("MASPrivacyPolicyURL", path: privacyPath) }
    static var supportURL: URL? { resolvedURL("MASSupportURL", path: supportPath) }
    // Slug paths are also compiled for local verification of the policy route.
    static let privacyPath = "/starglass/privacy/"
    static let supportPath = "/starglass/support/"
    static func resolvedURL(_ key: String, path: String, bundle: Bundle = .main) -> URL? {
        let resources = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("Starglass_Starglass.bundle"))
        } ?? Bundle.module
        let local = resources.url(forResource: path == privacyPath ? "privacy" : "support", withExtension: "html", subdirectory: "Resources")
        guard path == privacyPath || path == supportPath else { return nil }
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String,
              !raw.contains("{"), !raw.contains("}"), !raw.lowercased().contains("%7b"),
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              raw.hasSuffix(path) else { return local }
        return url
    }
}
struct PolicySupportLinks: View {
    var body: some View {
        HStack(spacing: 16) {
            if let privacy = AppLinks.privacyURL { Link("Privacy Policy", destination: privacy).accessibilityHint("Opens the privacy policy; bundled locally when a web address is not configured") }
            if let support = AppLinks.supportURL { Link("Support", destination: support).accessibilityHint("Opens support; bundled locally when a web address is not configured") }
        }.font(.callout).accessibilityIdentifier("policySupportLinks")
    }
}
enum ProductInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2" }
}
