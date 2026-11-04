import SwiftUI
import AppKit
import MASKit

enum AppLinks {
    static let privacyPath = "/mac-apps/quotapace/privacy/"
    static let supportPath = "/mac-apps/quotapace/support/"
    static func privacyPolicy() -> URL? {
        policyURL(MASLinks.privacyPolicy(), path: privacyPath, resource: "privacy")
    }
    static func support() -> URL? {
        policyURL(MASLinks.support(), path: supportPath, resource: "support")
    }
    static func policyURL(_ configured: URL?, path: String, resource: String) -> URL? {
        if let url = configured, url.scheme == "https",
           URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == path,
           let host = url.host, host.contains("."),
           !host.contains("{"), !host.contains("}"), !host.contains("%"),
           url.user == nil, url.password == nil {
            return url
        }
        return try? FixtureFiles.url(resource, extension: "html")
    }
}

enum PolicyPage: String, CaseIterable {
    case privacy, support
    var title: String { self == .privacy ? "Privacy Policy" : "Support" }
    var destination: URL? { self == .privacy ? AppLinks.privacyPolicy() : AppLinks.support() }
    var hint: String {
        destination?.isFileURL == false ? "Opens the \(title.lowercased()) in your browser" : "Shows the bundled \(title.lowercased()) in QuotaPace"
    }
    func text() throws -> String {
        try String(contentsOf: FixtureFiles.url(rawValue, extension: "txt"), encoding: .utf8)
    }
}

@MainActor
enum PolicyWindow {
    private static var windows: [String: NSWindow] = [:]
    static func open(_ page: PolicyPage) {
        if let url = page.destination, !url.isFileURL {
            NSWorkspace.shared.open(url)
            return
        }
        if windows[page.rawValue] == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "QuotaPace \(page.title)"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LocalPolicyView(page: page))
            window.center()
            windows[page.rawValue] = window
        }
        NSApp.activate(ignoringOtherApps: true)
        windows[page.rawValue]?.makeKeyAndOrderFront(nil)
    }
}

struct LocalPolicyView: View {
    let page: PolicyPage
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(page.title).font(.title.weight(.bold))
                Text((try? page.text()) ?? "The bundled page could not be read. Reopen QuotaPace to try again.")
                    .font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 400, minHeight: 360)
    }
}

struct AppPolicyButton: NSViewRepresentable {
    let page: PolicyPage
    func makeCoordinator() -> Coordinator { Coordinator(page: page) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: page.title, target: context.coordinator, action: #selector(Coordinator.openPage))
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = NSColor(calibratedRed: 94 / 255, green: 92 / 255, blue: 230 / 255, alpha: 1)
        update(button)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) { update(button) }
    private func update(_ button: NSButton) {
        button.title = page.title
        button.setAccessibilityLabel(page.title)
        button.setAccessibilityTitle(page.title)
        button.setAccessibilityHelp(page.hint)
        button.toolTip = page.hint
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize {
        nsView.intrinsicContentSize
    }
    @MainActor final class Coordinator: NSObject {
        let page: PolicyPage
        init(page: PolicyPage) { self.page = page }
        @objc func openPage() { PolicyWindow.open(page) }
    }
}
struct AppLinksView: View {
    var body: some View {
        HStack(spacing: 16) {
            AppPolicyButton(page: .privacy)
            AppPolicyButton(page: .support)
        }.font(.callout)
    }
}
