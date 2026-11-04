import SwiftUI
import LedgerCore

/// The sidebar's top item: entries from every ledger in the last 7 days, newest first. A click opens the ledger.
struct RecentChangesView: View {
    @ObservedObject var model: LedgerModel

    var body: some View {
        let items = model.recentChanges()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(items)
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No entries in the last 7 days.").font(.system(size: 15, weight: .semibold))
                        Text(model.folders.isEmpty
                             ? "Choose Watch a Folder. NativeLedger then records an entry each time an app in that folder changes."
                             : "When an app in a watched folder changes, its new entry appears here.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.rule))
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            Button { model.open(item) } label: {
                                FeedRow(item: item, folder: model.ledger(item.ledgerID).flatMap { model.folder(of: $0) }?.name)
                            }
                            .buttonStyle(.plain)
                            .help("Open the ledger of \(item.displayName)")
                        }
                    }
                }
            }
            .padding(.horizontal, 26).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ items: [LedgerModel.FeedItem]) -> some View {
        let flagged = items.filter { !$0.entry.anomalies.isEmpty }.count
        let apps = Set(items.map(\.ledgerID)).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Recent changes").font(.system(size: 26, weight: .semibold, design: .serif))
                if model.isSample { Chip(text: "Sample", tint: Palette.gold, filled: true) }
            }
            Text("Entries from all ledgers in the last 7 days, newest first. Click an entry to open its ledger.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
            if !items.isEmpty {
                HStack(spacing: 8) {
                    Chip(text: "\(items.count) \(items.count == 1 ? "entry" : "entries")", tint: Palette.green)
                    Chip(text: "\(apps) \(apps == 1 ? "app" : "apps")", tint: .secondary)
                    if flagged > 0 {
                        Chip(text: "\(flagged) with anomalies", symbol: "exclamationmark.triangle.fill", tint: Palette.red)
                    }
                }.padding(.top, 2)
            }
        }
    }
}

struct FeedRow: View {
    let item: LedgerModel.FeedItem
    var folder: String?

    var body: some View {
        let entry = item.entry
        let anomalies = Anomaly.bySeverity(entry.anomalies)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatting.day.string(from: item.date)).font(.system(size: 12, weight: .semibold))
                Text(Formatting.time.string(from: item.date)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: 92, alignment: .trailing)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("Entry \(entry.seq)").font(.system(size: 12)).foregroundStyle(.secondary)
                    KindChip(kind: entry.kind)
                    Spacer(minLength: 8)
                    if let folder { Label(folder, systemImage: "folder").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Text(summary).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                if !anomalies.isEmpty {
                    FlowLayout {
                        ForEach(anomalies, id: \.self) { Chip(text: $0.label, symbol: "exclamationmark.triangle.fill", tint: Palette.red, filled: true) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(anomalies.isEmpty ? Palette.rule : Palette.red.opacity(0.45),
                                                           lineWidth: anomalies.isEmpty ? 0.75 : 1.1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let entry = item.entry
        let version = "Version \(Formatting.versionBuild(entry.observation))"
        switch entry.kind {
        case .removed: return "\(version). The app is no longer in its watched folder."
        case .acknowledged: return "\(version). Accepted as the reviewed baseline."
        case .observed:
            if entry.seq == 1 { return "\(version). Opening entry." }
            // The version and build are already in the line, so their change chips are not repeated.
            let rest = entry.changes.filter { $0.field != .version && $0.field != .build }
            if rest.isEmpty { return entry.changes.isEmpty ? version : "\(version). Updated." }
            let shown = rest.prefix(3).map(\.chipText)
            let more = rest.count > 3 ? ", and \(rest.count - 3) more" : ""
            return "\(version). \(shown.joined(separator: ", "))\(more)"
        }
    }
}

/// Observed, Acknowledged or Removed.
struct KindChip: View {
    let kind: EntryKind
    var body: some View {
        switch kind {
        case .acknowledged: Chip(text: "Acknowledged", symbol: "checkmark.seal.fill", tint: Palette.gold, filled: true)
        case .removed: Chip(text: "Removed", symbol: "xmark.bin", tint: Color(red: 0.36, green: 0.40, blue: 0.47), filled: true)
        case .observed: Chip(text: "Observed", symbol: "eye", tint: .secondary)
        }
    }
}
