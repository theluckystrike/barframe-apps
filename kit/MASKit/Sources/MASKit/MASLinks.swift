import SwiftUI

/// Privacy-policy and support links (App Review Guideline 5.1.1(i): the policy must be
/// reachable inside the app). Values come from Info.plist keys written by kit/gen_plists.py
/// from mas.json, so the app, the listing, and the gate share one source.
public enum MASLinks {
    public static func privacyPolicy(_ bundle: Bundle = .main) -> URL? {
        url(for: "MASPrivacyPolicyURL", in: bundle)
    }

    public static func support(_ bundle: Bundle = .main) -> URL? {
        url(for: "MASSupportURL", in: bundle)
    }

    static func url(for key: String, in bundle: Bundle) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String,
              raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }
}

/// Drop-in row for Settings > About and the popover footer menu.
public struct MASLinksView: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 16) {
            if let privacy = MASLinks.privacyPolicy() {
                Link("Privacy Policy", destination: privacy)
                    .accessibilityHint("Opens the privacy policy in your browser")
            }
            if let support = MASLinks.support() {
                Link("Support", destination: support)
                    .accessibilityHint("Opens the support page in your browser")
            }
        }
        .font(.callout)
    }
}
