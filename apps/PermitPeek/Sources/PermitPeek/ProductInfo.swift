import SwiftUI
import MASKit

struct PolicySupportLinks: View {
    @State private var localDocument: String?
    var body: some View {
        HStack(spacing: 12) {
            Button(L("Privacy Policy", "Política de privacidad")) { open(AppLinks.privacy, resource: "privacy") }
            Button(L("Support", "Ayuda")) { open(AppLinks.support, resource: "support") }
        }
        .font(.caption)
        .sheet(isPresented: Binding(get: { localDocument != nil }, set: { if !$0 { localDocument = nil } })) {
            VStack {
                ScrollView { Text(localDocument ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button(L("Done", "Listo")) { localDocument = nil }
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
        return url.scheme == "https" && url.host != nil && !value.contains("{") && !value.contains("}")
    }
    static func localText(_ resource: String) -> String {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "txt", subdirectory: "Resources"),
              let text = try? String(contentsOf: url) else { return "PermitPeek · Michael Lip" }
        return sanitizedLocalText(text)
    }
    static func sanitizedLocalText(_ text: String) -> String {
        let seller = "Michael Lip"
        return text.replacingOccurrences(of: "{BRAND}", with: seller)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("{DOMAIN}") }
            .joined(separator: "\n")
    }
    static func webURL(_ value: String) -> URL {
        guard !value.contains("{"), !value.contains("}"), let url = URL(string: value) else {
            return URL(fileURLWithPath: "/")
        }
        return url
    }
    static let privacy = webURL(Bundle.main.object(forInfoDictionaryKey: "MASPrivacyPolicyURL") as? String ?? "https://{DOMAIN}/apps/permitpeek/privacy/")
    static let support = webURL(Bundle.main.object(forInfoDictionaryKey: "MASSupportURL") as? String ?? "https://{DOMAIN}/apps/permitpeek/support/")
}
