import AppKit
import SwiftUI
import RevPulseCore

@MainActor enum AppLinks {
    static let privacyPath = "/revpulse/privacy/"
    static let supportPath = "/revpulse/support/"
    static func webURL(_ kind: String) -> URL? {
        let key = kind == "privacy" ? "MASPrivacyPolicyURL" : "MASSupportURL"
        return PublicLink.webURL(Bundle.main.object(forInfoDictionaryKey: key) as? String,
                                 path: kind == "privacy" ? privacyPath : supportPath)
    }
    static func text(_ kind: String) -> String {
        let bundled = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("RevPulse_RevPulse.bundle")) } ?? Bundle.module
        guard let url = bundled.url(forResource: kind, withExtension: "txt", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Contact Michael Lip at support@barframe.com." }
        return text
    }
}
struct PolicySupportLinks: View {
    @State private var document: String?
    var body: some View {
        HStack(spacing: 16) {
            Button("Privacy Policy") { document = "privacy" }
            Button("Support") { document = "support" }
        }.font(.caption).accessibilityIdentifier("policySupportLinks")
        .sheet(isPresented: Binding(get: { document != nil }, set: { if !$0 { document = nil } })) {
            let kind = document ?? "privacy"
            VStack(alignment: .leading, spacing: 12) {
                ScrollView { Text(AppLinks.text(kind)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                HStack {
                    if let url = AppLinks.webURL(kind) { Link("Open website", destination: url) }
                    Spacer()
                    Button("Done") { document = nil }
                }.padding()
            }.frame(width: 560, height: 600)
        }
    }
}
