import SwiftUI
import AppKit

enum PortPage: String, CaseIterable {
    case privacy, support
    var title: String { self == .privacy ? "PortSense Privacy Policy" : "PortSense Support" }
    var infoKey: String { self == .privacy ? "MASPrivacyPolicyURL" : "MASSupportURL" }
    // Keep destination paths in the executable for the privacy gate.
    var path: String { self == .privacy ? "/portsense/privacy/" : "/portsense/support/" }
}

enum PortDestination: Equatable {
    case local(PortPage)
    case web(URL)
}

enum PortLinks {
    static func destination(_ page: PortPage, raw: String?) -> PortDestination {
        guard let raw, !raw.contains("{"), !raw.contains("}"),
              let url = URL(string: raw), url.scheme == "https",
              let host = url.host, !host.isEmpty, !host.contains("{"), !host.contains("}"), [page.path, "/mac-apps" + page.path, "/apps" + page.path].contains(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""),
              url.user == nil, url.password == nil else { return .local(page) }
        return .web(url)
    }
    static func destination(_ page: PortPage, bundle: Bundle = .main) -> PortDestination {
        destination(page, raw: bundle.object(forInfoDictionaryKey: page.infoKey) as? String)
    }
    static func localText(_ page: PortPage, bundle: Bundle = .main) -> String {
        // The app builder places SwiftPM resources in Contents/Resources.
        // SwiftPM's default accessor looks at the .app root and can trap in the sandbox.
        var contentBundle = bundle.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("PortSense_PortSenseApp.bundle"))
        }
        if contentBundle == nil {
            contentBundle = Bundle(url: bundle.bundleURL.appendingPathComponent("PortSense_PortSenseApp.bundle"))
        }
        #if DEBUG
        if contentBundle == nil && bundle == .main { contentBundle = Bundle.module }
        #endif
        guard let url = contentBundle?.url(forResource: page.rawValue, withExtension: "md", subdirectory: "Content"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "PortSense information could not be loaded. Please reopen the app."
        }
        return text.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func copyright(bundle: Bundle = .main) -> String {
        let value = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        guard let value, !value.contains("{"), !value.contains("}") else { return "© 2026 Michael Lip" }
        return value
    }
}

struct PortLinksView: View {
    @ObservedObject var model: AppState
    var body: some View {
        HStack(spacing: 16) {
            Button("Privacy Policy") { model.openPage(.privacy) }
                .accessibilityLabel("PortSense Privacy Policy")
            Button("Support") { model.openPage(.support) }
                .accessibilityLabel("PortSense Support")
        }
    }
}
