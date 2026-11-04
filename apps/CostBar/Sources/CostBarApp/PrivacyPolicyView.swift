import Foundation
import SwiftUI

enum LocalPrivacyPolicy {
    static func load() throws -> String { try LocalDocument.load("PrivacyPolicy") }
}
enum LocalSupport {
    static func load() throws -> String { try LocalDocument.load("Support") }
}
enum LocalDocument {
    static func load(_ document: String) throws -> String {
        let name = "CostBar_CostBarApp.bundle"
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(name),
                          Bundle.main.bundleURL.appendingPathComponent(name),
                          Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name)].compactMap { $0 }
        for bundle in candidates.compactMap({ Bundle(url: $0) }) {
            if let url = bundle.url(forResource: document, withExtension: "txt") {
                return try String(contentsOf: url, encoding: .utf8)
            }
        }
        // CLI tests use SwiftPM's layout; never initialize its accessor in a signed app.
        guard Bundle.main.bundleURL.pathExtension != "app",
              let url = Bundle.module.url(forResource: document, withExtension: "txt") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
struct DocumentLinksView: View {
    private enum Document: String, Identifiable { case privacy = "Privacy Policy", support = "Support"; var id: String { rawValue } }
    @State private var document: Document?
    var body: some View {
        HStack(spacing: 12) {
            if let privacy = CostBarLinks.privacyPolicy() {
                Link("Privacy Policy", destination: privacy).accessibilityLabel("Open CostBar Privacy Policy")
            } else {
                Button("Privacy Policy") { document = .privacy }.accessibilityLabel("Read the bundled CostBar Privacy Policy")
            }
            if let support = CostBarLinks.support() {
                Link("Support", destination: support).accessibilityLabel("Open CostBar Support")
            } else {
                Button("Support") { document = .support }.accessibilityLabel("Read bundled CostBar Support")
            }
        }.sheet(item: $document) { item in
            LocalDocumentView(title: item.rawValue, content: (try? item == .privacy ? LocalPrivacyPolicy.load() : LocalSupport.load()) ?? "The bundled document could not be read.")
        }
    }
}
struct LocalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            ScrollView { Text(content).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 520, height: 540)
    }
}
