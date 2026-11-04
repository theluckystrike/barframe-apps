import Foundation

/// Path detection and safe rendering for untrusted text.
public enum PathScreen {
    public static let omittedPath = "[path omitted]"

    public static func looksLikePath(_ s: String) -> Bool {
        var probe = s
        // Repeated decoding covers nested percent encoding and the escaped slash form of JSON.
        while true {
            let slashDecoded = probe.replacingOccurrences(of: #"\/"#, with: "/")
                .replacingOccurrences(of: #"/"#, with: "/", options: .caseInsensitive)
            let decoded = slashDecoded.removingPercentEncoding ?? slashDecoded
            if decoded == probe { break }
            probe = decoded
        }
        let lower = probe.lowercased()
        return lower.contains("/users/") || lower.contains("/volumes/") || lower.contains("/private/")
            || lower.contains("file://") || probe.contains("~/")
            || probe.range(of: #"(^|[\s"'\[{=,(])/"#, options: .regularExpression) != nil
    }
    /// One physical line, control and format characters escaped, at most 200 characters.
    static func singleLine(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            let token: String
            switch scalar.value {
            case 10: token = #"\n"#
            case 13: token = #"\r"#
            case 9: token = #"\t"#
            default:
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator: token = String(format: "\\u%04X", scalar.value)
                default: token = String(scalar)
                }
            }
            if out.count + token.count > 200 { return out + "…" }
            out += token
        }
        return out
    }
    public static func safeToken(_ s: String, max: Int = 80) -> String {
        guard !s.isEmpty, s.count <= max, !looksLikePath(s),
              s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_ +")).contains($0) }) else { return "[omitted]" }
        return s
    }
    static func safeValue(_ s: String?) -> String {
        guard let s else { return "none" }
        if looksLikePath(s) { return omittedPath }
        return singleLine(s)
    }
}

/// Plain text report of one ledger. It omits file paths, bookmarks and raw error text.
public enum LedgerReport {
    public static let limits = "Recorded per entry: bundle identifier, version, build, main executable architecture and slices, declared signing identifier, signing team, declared entitlements, code directory hash, SHA-256 of the main executable, privacy usage descriptions, nested login items, launchd jobs, XPC services and helpers by name, update feed address, minimum macOS version and the result of a signature validity check. Not inspected: the code inside nested items, effective permissions and network traffic. A valid signature means the bundle matches its signature. It does not mean the app is safe. The chain detects edits, removals and reordering of earlier entries. Someone who recalculates hashes can change or remove the newest entries, or rewrite the whole chain. Only an exported copy to compare reveals that. This report is not a safety or malware verdict."

    static func day(_ d: Date) -> String { LedgerCoding.string(from: d) }
    static func hash(_ s: String?) -> String {
        guard let s else { return "not recorded" }
        return s.allSatisfy(\.isHexDigit) && !s.isEmpty ? s : "[omitted]"
    }
    static func describe(_ o: LedgerObservation) -> [String] {
        var lines = ["Bundle identifier \(PathScreen.safeToken(o.bundleID))",
                     "Version \(PathScreen.safeToken(o.version, max: 40)) build \(PathScreen.safeToken(o.build, max: 40))",
                     "Architecture \(o.architecture.rawValue)",
                     "Code directory hash \(hash(o.binary.cdhash))",
                     "Executable SHA-256 \(hash(o.binary.executableSHA256))"]
        switch o.signing {
        case .read(let id, let team, let ent):
            lines.append("Signing identifier \(PathScreen.safeToken(id))")
            lines.append("Signing team \(team.map { PathScreen.safeToken($0, max: 16) } ?? "not declared")")
            lines.append("Declared entitlements \(ent.isEmpty ? "none" : String(ent.count))")
            for k in ent.keys.sorted() { lines.append("  \(PathScreen.safeToken(k, max: 120)) = \(PathScreen.safeValue(ent[k]))") }
        case .unsigned: lines.append("Signing not signed")
        case .unavailable: lines.append("Signing not read")
        }
        guard o.extendedFields else { return lines }
        lines.append("Signature validity \(o.signatureValidity.label)")
        lines.append("Architecture slices \(o.architectureSlices.isEmpty ? "none" : o.architectureSlices.joined(separator: ", "))")
        lines.append("Minimum macOS version \(o.minimumSystemVersion.map { PathScreen.safeToken($0, max: 40) } ?? "not declared")")
        lines.append("Update feed \(o.updateFeedURL.map { PathScreen.safeValue($0) } ?? "not declared")")
        lines.append("Usage descriptions \(o.usageDescriptions.isEmpty ? "none" : String(o.usageDescriptions.count))")
        for k in o.usageDescriptions.keys.sorted() {
            lines.append("  \(PathScreen.safeToken(k, max: 120)) = \(PathScreen.safeValue(o.usageDescriptions[k]))")
        }
        lines.append("Background items \(o.backgroundItems.isEmpty ? "none" : String(o.backgroundItems.count))")
        for item in o.backgroundItems { lines.append("  \(PathScreen.safeToken(item, max: 120))") }
        return lines
    }
    static func changeLabel(_ f: ChangeField) -> String {
        switch f {
        case .entitlement(let key): return "Entitlement " + PathScreen.safeToken(key, max: 120)
        case .usageDescription(let key): return "Usage description " + PathScreen.safeToken(key, max: 120)
        case .backgroundItem(let item): return "Background item " + PathScreen.safeToken(item, max: 120)
        default: return f.label
        }
    }

    public static func make(_ ledger: AppLedger, verdict: ChainVerdict, now: Date, sample: Bool = false) -> String {
        var out = ["NativeLedger report\(sample ? " (Sample)" : "")",
                   "App \(PathScreen.safeToken(ledger.displayName, max: 60))",
                   "Ledger \(ledger.id.uuidString)",
                   "Report date \(day(now))",
                   "Entries \(ledger.entries.count)"]
        switch verdict {
        case .intact(let count): out.append("Chain intact (\(count) entries verified)")
        case .broken(let seq, let reason): out.append("Chain broken at entry \(seq). \(PathScreen.singleLine(reason))")
        }
        let open = ledger.openAnomalies
        out.append("Open anomalies \(open.isEmpty ? "none" : open.map(\.label).joined(separator: ", "))")
        if let base = ledger.baseline { out.append("Baseline entry \(base.seq), acknowledged \(day(base.observation.observedAt))") }
        else { out.append("Baseline none") }
        for entry in ledger.entries.reversed() {
            out.append("")
            out.append("Entry \(entry.seq) \(entry.kind.rawValue) \(day(entry.observation.observedAt)) hash \(hash(entry.shortHash))")
            out += describe(entry.observation).map { "  " + $0 }
            for a in entry.anomalies { out.append("  Anomaly \(a.label). \(a.explanation)") }
            for c in entry.changes {
                out.append("  \(c.kind) \(changeLabel(c.field)) from \(PathScreen.safeValue(c.before)) to \(PathScreen.safeValue(c.after))")
            }
        }
        out.append("")
        out.append(limits)
        return out.joined(separator: "\n")
    }
}
