import SwiftUI

/// Bundled policy stays available without a network connection.
struct PrivacyPolicyView: View {
    static var policy: String { PortLinks.localText(.privacy) }
    var body: some View { LocalPageView(page: .privacy) }
}

struct LocalPageView: View {
    let page: PortPage
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(page.title).font(.title2.bold())
                Text(PortLinks.localText(page)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(24)
        }.frame(width: 460, height: 400)
        .onExitCommand { NSApp.keyWindow?.close() }
    }
}
