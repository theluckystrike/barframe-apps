import Foundation
public enum PublicLink {
    public static func webURL(_ raw: String?, path: String) -> URL? {
        guard let raw, !raw.contains("{"), !raw.contains("}"), !raw.lowercased().contains("%7b"),
            let url = URL(string: raw), url.scheme == "https", url.host != nil, raw.hasSuffix(path) else { return nil }
        return url
    }
}
