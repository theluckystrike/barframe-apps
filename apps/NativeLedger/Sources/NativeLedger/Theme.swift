import AppKit
import SwiftUI
import LedgerCore

/// Ledger green, seal gold and paper tones, matched to the app icon.
enum Palette {
    static let green = Color(red: 0.13, green: 0.38, blue: 0.27)
    static let greenSoft = Color(red: 0.13, green: 0.38, blue: 0.27).opacity(0.12)
    static let gold = Color(red: 0.72, green: 0.55, blue: 0.20)
    static let goldSoft = Color(red: 0.80, green: 0.62, blue: 0.24).opacity(0.18)
    static let red = Color(red: 0.76, green: 0.17, blue: 0.15)
    static let redSoft = Color(red: 0.76, green: 0.17, blue: 0.15).opacity(0.12)
    static let amber = Color(red: 0.80, green: 0.47, blue: 0.10)
    static let paper = dynamic(light: NSColor(srgbRed: 0.985, green: 0.975, blue: 0.95, alpha: 1),
                               dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.10, alpha: 1))
    static let sidebar = dynamic(light: NSColor(srgbRed: 0.94, green: 0.935, blue: 0.91, alpha: 1),
                                 dark: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.14, alpha: 1))
    static let card = dynamic(light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85),
                              dark: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.16, alpha: 1))
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let rule = Color.primary.opacity(0.10)

    static func badge(_ badge: LedgerModel.Badge) -> Color {
        switch badge {
        case .intact: return green
        case .anomaly, .broken: return red
        case .unavailable: return amber
        case .notInspected, .removed: return .secondary
        }
    }
    static func verdict(_ verdict: CrossMacVerdict) -> Color {
        switch verdict {
        case .sameBuild: return green
        case .differentBinarySameVersion: return red
        case .differentVersion: return amber
        case .onlyHere, .onlyThere: return Color(red: 0.36, green: 0.40, blue: 0.47)
        }
    }
}

enum Formatting {
    static let dateTime: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    static func relative(_ date: Date, to now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }
    static func versionBuild(_ o: LedgerObservation) -> String {
        o.version == o.build ? o.version : "\(o.version) (\(o.build))"
    }
}

/// A capsule label used for changes, anomalies and badges.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary
    var filled = false
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: filled ? .semibold : .medium)).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(filled ? Color.white : tint)
        .background(Capsule().fill(filled ? tint : tint.opacity(0.12)))
        .overlay(Capsule().stroke(tint.opacity(filled ? 0 : 0.25), lineWidth: 0.5))
    }
}

/// Wraps its children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width { y += line + lineSpacing; x = 0; line = 0 }
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: subviews.isEmpty ? 0 : y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX { y += line + lineSpacing; x = bounds.minX; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}

extension SignatureValidity {
    /// Text for the entry summary chip. The detail grid uses `label` (Valid, Invalid (code N), Not signed, Not checked).
    var chipText: String {
        switch self {
        case .valid: return "Signature valid"
        case .invalid(let code): return code == Self.unsignedCode ? "Not signed" : "Signature invalid (code \(code))"
        case .notChecked: return "Signature not checked"
        }
    }
    var tint: Color {
        switch self {
        case .valid: return Palette.green
        case .invalid: return isFailure ? Palette.red : .secondary
        case .notChecked: return .secondary
        }
    }
    var symbol: String { self == .valid ? "checkmark.seal" : isFailure ? "xmark.seal" : "seal" }
}

extension Change {
    /// Short chip text. Hashes are named, not printed.
    var chipText: String {
        switch field {
        case .cdhash, .executableSHA256: return "\(field.label) changed"
        case .entitlement(let key): return "Entitlement \(kind.lowercased()) \(key.replacingOccurrences(of: "com.apple.security.", with: ""))"
        case .usageDescription(let key):
            return "Usage description \(kind.lowercased()) \(key.replacingOccurrences(of: "UsageDescription", with: "").replacingOccurrences(of: "NS", with: ""))"
        case .backgroundItem(let item): return "Background item \(kind.lowercased()) \(item)"
        default:
            switch (before, after) {
            case let (b?, a?): return "\(field.label) \(b) → \(a)"
            case (nil, let a?): return "\(field.label) added \(a)"
            case (let b?, nil): return "\(field.label) removed \(b)"
            default: return field.label
            }
        }
    }
}
