import Foundation

enum LocalDocument: String, CaseIterable, Identifiable {
    case privacy, support
    var id: String { rawValue }
    var title: String { self == .privacy ? "Privacy Policy" : "Support" }
    var plistKey: String { self == .privacy ? "MASPrivacyPolicyURL" : "MASSupportURL" }
    func webURL(bundle: Bundle = .main) -> URL? {
        Self.validWebURL(bundle.object(forInfoDictionaryKey: plistKey) as? String ?? "https://{DOMAIN}" + (self == .privacy ? Self.productPrivacyPath : "/apps/stepquay/support/"))
    }
    static func validWebURL(_ text: String?) -> URL? {
        guard let text, !text.contains("{"), !text.contains("}"),
              let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    func text(spanish: Bool = false) -> String {
        let name = rawValue + (spanish ? "-es" : "")
        guard let url = Self.documentBundle()?.url(forResource: name, withExtension: "txt", subdirectory: "LocalDocuments"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return title }
        return text
    }
    static func documentBundle(in app: Bundle = .main) -> Bundle? {
        if let resources = app.resourceURL,
           let bundled = Bundle(url: resources.appendingPathComponent("StepQuay_StepQuay.bundle")) { return bundled }
        // SwiftPM's generated accessor points to the build tree. Use it only for command-line tests.
        return app.bundleURL.pathExtension == "app" ? nil : Bundle.module
    }
    // Product paths remain embedded for the in-app privacy gate, while actual destinations come from branding in Info.plist.
    static let productPrivacyPath = "/apps/stepquay/privacy/"
}
