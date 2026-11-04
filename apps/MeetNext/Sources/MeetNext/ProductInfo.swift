import SwiftUI
import MASKit

struct PolicySupportLinks: View {
    @State private var localDocument: String?
    var body: some View {
        HStack(spacing: 12) {
            Button("Privacy Policy") { open(AppLinks.privacy, resource: "privacy") }
            Button("Support") { open(AppLinks.support, resource: "support") }
        }
        .font(.caption)
        .sheet(isPresented: Binding(get: { localDocument != nil }, set: { if !$0 { localDocument = nil } })) {
            VStack {
                ScrollView { Text(localDocument ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Done") { localDocument = nil }
            }.padding(24).frame(width: 520, height: 500)
        }
    }
    private func open(_ url: URL, resource: String) {
        if AppLinks.isFinal(url) { NSWorkspace.shared.open(url) }
        else { localDocument = AppLinks.localText(resource) }
    }
}

enum ProductInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
}

enum AppLinks {
    static func isFinal(_ url: URL) -> Bool {
        let value = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        return url.scheme == "https" && !value.contains("{") && !value.contains("}")
    }
    static func localText(_ resource: String) -> String {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "txt", subdirectory: "Resources"),
              let text = try? String(contentsOf: url) else { return "MeetNext · Michael Lip" }
        return text
    }
    static func webURL(_ value: String) -> URL {
        guard !value.contains("{"), !value.contains("}"), let url = URL(string: value) else {
            return URL(fileURLWithPath: "/")
        }
        return url
    }
    static let privacy = webURL( "https://barframe.com/apps/meetnext/privacy/")
    static let support = webURL( "https://barframe.com/apps/meetnext/support/")
}
