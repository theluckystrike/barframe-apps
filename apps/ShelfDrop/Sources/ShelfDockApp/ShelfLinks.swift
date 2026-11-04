import SwiftUI
import AppKit
import ShelfDockCore

enum ShelfPage: String, CaseIterable {
    case privacy, support
    var title: String { self == .privacy ? "ShelfDock Privacy Policy" : "ShelfDock Support" }
    var infoKey: String { self == .privacy ? "MASPrivacyPolicyURL" : "MASSupportURL" }
    // Stored constants keep destination paths in the executable for the privacy gate.
    static let privacyPath = "/shelfdock/privacy/"
    static let supportPath = "/shelfdock/support/"
    var path: String { self == .privacy ? ShelfPage.privacyPath : ShelfPage.supportPath }
}

enum ShelfDestination: Equatable {
    case local(ShelfPage)
    case web(URL)
}

enum ShelfLinks {
    static func destination(_ page: ShelfPage, raw: String?) -> ShelfDestination {
        guard let raw, !raw.contains("{"), !raw.contains("}"), !raw.lowercased().contains("%7b"), !raw.lowercased().contains("%7d"),
              let url = URL(string: raw), url.scheme == "https",
              let host = url.host, !host.isEmpty, !host.contains("{"), !host.contains("}"),
              [page.path, "/mac-apps" + page.path, "/apps" + page.path].contains(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""),
              url.user == nil, url.password == nil else { return .local(page) }
        return .web(url)
    }
    static func destination(_ page: ShelfPage, bundle: Bundle = .main) -> ShelfDestination {
        destination(page, raw: bundle.object(forInfoDictionaryKey: page.infoKey) as? String)
    }
    static func localText(_ page: ShelfPage, bundle: Bundle = .main) -> String {
        guard let url = ShelfResources.contentURL(page.rawValue + ".md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "ShelfDock information could not be loaded. Please reopen the app."
        }
        return text.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func copyright(bundle: Bundle = .main) -> String {
        let value = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        guard let value, !value.contains("{"), !value.contains("}") else { return "© 2026 Michael Lip" }
        return value
    }
}

struct ShelfLinksView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 16) {
            Button("Privacy Policy") { model.openPage(.privacy) }
                .accessibilityLabel("ShelfDock Privacy Policy")
            Button("Support") { model.openPage(.support) }
                .accessibilityLabel("ShelfDock Support")
        }
    }
}

struct LocalPageView: View {
    let page: ShelfPage
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(page.title).font(.title2.bold())
                Text(ShelfLinks.localText(page)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(24)
        }.frame(width: 460, height: 400)
        .onExitCommand { NSApp.keyWindow?.close() }
    }
}
