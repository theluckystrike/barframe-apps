import SwiftUI
import LedgerCore

/// The cross-Mac comparison: one row per bundle identifier, newest entry on each side.
struct CompareView: View {
    let comparison: LedgerModel.Comparison
    var close: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compare with Ledger File").font(.system(size: 22, weight: .semibold, design: .serif))
                    Text("\(comparison.source) · exported \(Formatting.dateTime.string(from: comparison.exportedAt))")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if comparison.sample { Chip(text: "Sample", tint: Palette.gold, filled: true) }
            }
            summary
            if comparison.brokenInFile > 0 {
                Label("\(comparison.brokenInFile) \(comparison.brokenInFile == 1 ? "ledger" : "ledgers") in that file did not verify. Their rows are marked Not verified.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Palette.red)
            }
            if comparison.brokenHere > 0 {
                Label("\(comparison.brokenHere) \(comparison.brokenHere == 1 ? "ledger" : "ledgers") on this Mac did not verify. Their rows are marked Not verified.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Palette.red)
            }
            table
            HStack {
                Text("Same build needs the same version, the same build and matching hashes. Each side uses its newest entry.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 820, idealWidth: 860, minHeight: 440)
        .background(Palette.paper)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            ForEach(CrossMacVerdict.allCases, id: \.self) { verdict in
                let count = comparison.rows.filter { $0.verdict == verdict }.count
                if count > 0 { Chip(text: "\(count) \(verdict.label)", tint: Palette.verdict(verdict), filled: false) }
            }
            Spacer()
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            row(header: true, app: "App", verdict: nil, here: ("This Mac", ""), there: ("Other Mac", ""))
            Divider()
            if comparison.rows.isEmpty {
                Text("Neither side has entries yet.").foregroundStyle(.secondary).padding(20)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(comparison.rows) { r in
                        row(header: false, app: r.bundleID, verdict: r.verdict, here: side(r.here), there: side(r.there),
                            unverified: comparison.unverified.contains(r.bundleID))
                        Divider().opacity(0.6)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.rule))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func side(_ o: LedgerObservation?) -> (String, String) {
        guard let o else { return ("Not recorded", "") }
        let hash = o.binary.executableSHA256.map { "sha256 " + $0.prefix(12) } ?? o.binary.cdhash.map { "cdhash " + $0.prefix(12) } ?? "no hash"
        return ("Version " + Formatting.versionBuild(o), hash)
    }

    private func cell(_ value: (String, String), header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.0).font(.system(size: 12.5, weight: header ? .semibold : .regular)).lineLimit(1)
            if !value.1.isEmpty {
                Text(value.1).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(header: Bool, app: String, verdict: CrossMacVerdict?, here: (String, String), there: (String, String),
                     unverified: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(app).font(.system(size: 12.5, weight: header ? .semibold : .regular, design: header ? .default : .monospaced))
                .lineLimit(1).truncationMode(.middle).frame(width: 190, alignment: .leading)
            Group {
                if unverified {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.red)
                        Text("Not verified").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.red).lineLimit(1)
                    }
                } else if let verdict {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.verdict(verdict)).frame(width: 8, height: 8)
                        Text(verdict.label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.verdict(verdict))
                            .lineLimit(1)
                    }
                } else {
                    Text("Result").font(.system(size: 12.5, weight: .semibold))
                }
            }.frame(width: 270, alignment: .leading)
            cell(here, header: header)
            cell(there, header: header)
        }
        .padding(.horizontal, 14).padding(.vertical, header ? 9 : 8)
        .background(header ? Color.primary.opacity(0.04)
                    : unverified ? Palette.red.opacity(0.06)
                    : (verdict.map { Palette.verdict($0).opacity($0 == .sameBuild ? 0 : 0.05) } ?? .clear))
        .accessibilityElement(children: .combine)
    }
}
