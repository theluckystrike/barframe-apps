import AppKit
import SwiftUI
import LedgerCore

struct LedgerDetailView: View {
    @ObservedObject var model: LedgerModel
    let ledger: AppLedger
    var staleDays: Int = LedgerModel.defaultStaleDays
    /// Entry numbers whose details start open. nil uses the default: the newest entry when it flags an anomaly.
    var expandedEntries: Set<Int>? = nil
    /// An entry to scroll to when the view appears. The screenshot renderer uses it.
    var scrollToEntry: Int? = nil

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusCards
                if let message = model.notices[ledger.id], !message.isEmpty {
                    Label(message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if ledger.isRemoved { removedCallout }
                if !ledger.openAnomalies.isEmpty { anomalyCallout }
                timeline
                Text(LedgerReport.limits).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            .padding(.horizontal, 26).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            // The newest entry scrolls with the Timeline heading above it.
            guard let seq = scrollToEntry else { return }
            proxy.scrollTo(seq == ledger.latest?.seq ? "timeline" : "entry-\(seq)", anchor: .top)
        }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ledger.displayName).font(.system(size: 26, weight: .semibold, design: .serif)).lineLimit(1)
                    if model.isSample { Chip(text: "Sample", tint: Palette.gold, filled: true) }
                }
                HStack(spacing: 10) {
                    Text(ledger.pinnedBundleID ?? "Not inspected yet")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    Label(sourceText, systemImage: ledger.source.folderID == nil ? "plus.app" : "folder")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { model.inspect(ledger.id) } label: {
                    Label(model.isBusy(ledger.id) ? "Inspecting…" : "Inspect now", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent).tint(Palette.green)
                .disabled(!model.canInspect(ledger))
                .help(ledger.isRemoved ? "The app is no longer in its watched folder." : "Read the app again. A new entry is added only when something changed.")
                Button { model.acknowledge(ledger.id) } label: { Label("Acknowledge", systemImage: "checkmark.seal") }
                    .disabled(!model.canAcknowledge(ledger))
                    .help("Read the app again and accept the latest entry as the reviewed baseline.")
                Button { model.verify(ledger.id) } label: { Label("Verify chain", systemImage: "link") }
                    .help("Recalculate every entry hash and check each link.")
                Menu {
                    Button("Copy Report") { model.copyReport(ledger.id) }
                    Divider()
                    Button("Remove", role: .destructive) { model.remove(ledger.id) }.disabled(!model.canWrite)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("More actions")
            }
            .controlSize(.regular)
        }
    }

    private var sourceText: String {
        if let folder = model.folder(of: ledger) { return "In \(folder.name)" }
        return ledger.source.folderID == nil ? "Added with Add App" : "Watched folder removed"
    }

    private var removedCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Removed", systemImage: "xmark.bin").font(.system(size: 13, weight: .semibold))
            Text("The app is no longer in \(model.folder(of: ledger)?.name ?? "its watched folder"). The final entry records the removal. The ledger stays, and it can still be verified and exported. If the app comes back, NativeLedger records it again.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.rule))
    }

    // MARK: status

    private var statusCards: some View {
        HStack(spacing: 12) {
            chainCard
            baselineCard
            readCard
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private func card<Content: View>(_ title: String, tint: Color, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: symbol).font(.system(size: 10.5, weight: .bold)).tracking(0.8).foregroundStyle(tint)
            content()
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35)))
    }
    @ViewBuilder private var chainCard: some View {
        let verdict = model.verdicts[ledger.id] ?? LedgerChain.verify(ledger)
        switch verdict {
        case .intact(let count):
            card("Chain", tint: Palette.green, symbol: "link") {
                Text(count == 0 ? "No entries yet" : "Intact · \(count) \(count == 1 ? "entry" : "entries")").font(.system(size: 15, weight: .semibold))
                Text(model.verifiedAt[ledger.id].map { "Verified \(Formatting.relative($0))" } ?? "Checked when loaded")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .broken(let seq, let reason):
            card("Chain", tint: Palette.red, symbol: "link.badge.plus") {
                Text("Broken at entry \(seq)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.red)
                Text(reason).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var baselineCard: some View {
        card("Baseline", tint: Palette.gold, symbol: "checkmark.seal") {
            if let base = ledger.baseline {
                Text("Entry \(base.seq) · Version \(Formatting.versionBuild(base.observation))").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text("Acknowledged \(Formatting.dateTime.string(from: base.observation.observedAt))").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("None yet").font(.system(size: 15, weight: .semibold))
                Text("Acknowledge an entry after you review it").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private var readCard: some View {
        let stale = model.isStale(ledger, days: staleDays)
        let failure = model.failures[ledger.id]
        let tint = failure != nil || stale ? Palette.amber : Color.secondary
        return card("Last read", tint: tint, symbol: failure != nil ? "lock.slash" : "clock") {
            if let last = model.lastRead(ledger) {
                Text(Formatting.relative(last)).font(.system(size: 15, weight: .semibold)).foregroundStyle(stale ? Palette.amber : .primary)
            } else {
                Text("Not inspected").font(.system(size: 15, weight: .semibold))
            }
            Text(failure.map { $0.safeMessage } ?? (stale ? "Older than \(staleDays) days. Inspect it again." : "Unchanged readings add no entry"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var anomalyCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Open anomalies since the baseline", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.red)
            ForEach(Anomaly.bySeverity(ledger.openAnomalies), id: \.self) { anomaly in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Chip(text: anomaly.label, tint: Palette.red, filled: true)
                    Text(anomaly.explanation).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Acknowledge after you have reviewed the change.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.redSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.red.opacity(0.3)))
    }

    // MARK: timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline").font(.system(size: 17, weight: .semibold, design: .serif))
                Text("newest first").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 6)
            .id("timeline")
            if ledger.entries.isEmpty {
                Text("No entries yet. Click Inspect now to record the app.").font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    let entries = Array(ledger.entries.reversed())
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        TimelineEntryView(entry: entry, isLast: index == entries.count - 1,
                                          broken: brokenSeq.map { entries.count - index >= $0 } ?? false,
                                          expanded: expandedEntries.map { $0.contains(entry.seq) } ?? (index == 0 && TimelineEntryView.opensByDefault(entry)))
                            .id("entry-\(entry.seq)")
                    }
                }
            }
        }
    }
    private var brokenSeq: Int? {
        if case .broken(let seq, _) = model.verdicts[ledger.id] { return seq }
        return nil
    }
}

struct TimelineEntryView: View {
    let entry: LedgerEntry
    var isLast = false
    var broken = false
    @State private var expanded: Bool

    init(entry: LedgerEntry, isLast: Bool = false, broken: Bool = false, expanded: Bool = false) {
        self.entry = entry; self.isLast = isLast; self.broken = broken
        _expanded = State(initialValue: expanded)
    }
    /// The newest entry opens its details when it flags an anomaly in the extended fields.
    static func opensByDefault(_ entry: LedgerEntry) -> Bool {
        let extended: Set<Anomaly> = [.signatureInvalid, .newBackgroundItem, .newPrivacyUsage, .updateFeedChanged]
        return entry.observation.extendedFields && !extended.isDisjoint(with: entry.anomalies)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            node.frame(width: 24, height: 24).padding(.top, 12)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Entry \(entry.seq)").font(.system(size: 13, weight: .bold))
                    KindChip(kind: entry.kind)
                    if entry.observation.extendedFields && entry.kind != .removed {
                        let v = entry.observation.signatureValidity
                        Chip(text: v.chipText, symbol: v.symbol, tint: v.tint, filled: v.isFailure)
                            .help("Signature validity \(v.label)")
                    }
                    Text(Formatting.dateTime.string(from: entry.observation.observedAt)).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    hashes
                }
                Text(summary).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                if !entry.anomalies.isEmpty {
                    FlowLayout {
                        ForEach(Anomaly.bySeverity(entry.anomalies), id: \.self) { Chip(text: $0.label, symbol: "exclamationmark.triangle.fill", tint: Palette.red, filled: true) }
                    }
                }
                if !entry.changes.isEmpty {
                    FlowLayout {
                        ForEach(entry.changes) { Chip(text: $0.chipText, tint: .secondary) }
                    }
                } else if entry.kind == .removed {
                    Text("Removed from its watched folder. The entry repeats the last reading with the removal date.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                } else if entry.seq == 1 {
                    Text("Opening entry. Later entries are compared with the one before them.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                } else if entry.kind == .acknowledged {
                    Text("Same content as the entry before. Accepted as the reviewed baseline.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                if entry.kind != .removed {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                        Label(expanded ? "Hide details" : "Show details", systemImage: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.borderless).foregroundStyle(Palette.green)
                    if expanded { EntryDetails(entry: entry) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: entry.anomalies.isEmpty && !broken ? 0.75 : 1.25))
            .padding(.bottom, 10)
        }
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle().fill(Palette.rule).frame(width: 2).padding(.leading, 11).padding(.top, 36)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var border: Color {
        if broken { return Palette.red }
        if !entry.anomalies.isEmpty { return Palette.red.opacity(0.55) }
        if entry.kind == .acknowledged { return Palette.gold.opacity(0.55) }
        return Palette.rule
    }
    @ViewBuilder private var node: some View {
        let color: Color = broken || !entry.anomalies.isEmpty ? Palette.red
            : entry.kind == .acknowledged ? Palette.gold : entry.kind == .removed ? .secondary : Palette.green
        ZStack {
            Circle().fill(color.opacity(0.16))
            Circle().stroke(color, lineWidth: 2).padding(3)
            if entry.kind == .acknowledged { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(color) }
            else if entry.kind == .removed { Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(color) }
            else { Circle().fill(color).padding(8) }
        }
    }
    private var hashes: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(entry.shortHash).font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(broken ? Palette.red : Palette.green).textSelection(.enabled)
                .help("Entry hash \(entry.entryHash)")
            Text("links to \(String(entry.previousHash.prefix(12)))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .accessibilityLabel("Entry hash \(entry.shortHash)")
    }
    private var summary: String {
        let o = entry.observation
        var parts = ["Version \(Formatting.versionBuild(o))", o.architecture.rawValue]
        switch o.signing {
        case .read(_, let team, let ent):
            parts.append("Team \(team ?? "none")")
            parts.append("\(ent.count) \(ent.count == 1 ? "entitlement" : "entitlements")")
        case .unsigned: parts.append("Not signed")
        case .unavailable: parts.append("Signing not read")
        }
        if let cd = o.binary.cdhash { parts.append("cdhash \(cd.prefix(10))") }
        return parts.joined(separator: " · ")
    }
}

/// The extended fields of one entry, with a mark on each field this entry changed.
struct EntryDetails: View {
    let entry: LedgerEntry

    private var o: LedgerObservation { entry.observation }
    private func change(_ field: ChangeField) -> Change? { entry.changes.first { $0.field == field } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !o.extendedFields {
                Text("This entry was recorded before NativeLedger read usage descriptions, background items, the update feed, the minimum macOS version, slices and signature validity.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                    row("Signature validity", mark: change(.signatureValidity)) {
                        Text(o.signatureValidity.label).foregroundStyle(o.signatureValidity.isFailure ? Palette.red : Color.primary)
                    }
                    row("Minimum macOS", mark: change(.minimumSystemVersion)) { Text(o.minimumSystemVersion ?? "Not declared") }
                    row("Slices", mark: change(.architectureSlices)) {
                        Text(o.architectureSlices.isEmpty ? "None read" : o.architectureSlices.joined(separator: ", "))
                    }
                    row("Update feed", mark: change(.updateFeedURL)) {
                        Text(o.updateFeedURL ?? "None").lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    row("Background items", mark: nil) {
                        if o.backgroundItems.isEmpty { Text("None") } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(o.backgroundItems, id: \.self) { item in
                                    HStack(spacing: 6) {
                                        Text(item).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                        if let c = change(.backgroundItem(item)) { mark(c) }
                                    }
                                }
                            }
                        }
                    }
                    row("Usage descriptions", mark: nil) {
                        if o.usageDescriptions.isEmpty { Text("None") } else {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(o.usageDescriptions.keys.sorted(), id: \.self) { key in
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Chip(text: Self.shortName(key), tint: Palette.green).help(o.usageDescriptions[key] ?? "")
                                            Text(key).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                                            if let c = change(.usageDescription(key)) { mark(c) }
                                        }
                                        Text(o.usageDescriptions[key] ?? "").font(.system(size: 11.5)).foregroundStyle(.secondary)
                                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                .font(.system(size: 12))
            }
            if let removed = removedItems, !removed.isEmpty {
                Text("Removed in this entry: \(removed.joined(separator: ", "))").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
    }

    /// Background items and usage keys that this entry no longer has.
    private var removedItems: [String]? {
        let gone = entry.changes.compactMap { c -> String? in
            guard c.after == nil else { return nil }
            switch c.field {
            case .backgroundItem(let item): return item
            case .usageDescription(let key): return key
            default: return nil
            }
        }
        return gone.isEmpty ? nil : gone
    }

    static func shortName(_ key: String) -> String {
        var name = key
        if name.hasPrefix("NS") { name.removeFirst(2) }
        if name.hasSuffix("UsageDescription") { name.removeLast("UsageDescription".count) }
        return name.isEmpty ? key : name
    }

    @ViewBuilder private func row<V: View>(_ title: String, mark change: Change?, @ViewBuilder value: () -> V) -> some View {
        GridRow {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                value()
                if let change { mark(change) }
            }
        }
    }
    private func mark(_ change: Change) -> some View {
        let added = change.before == nil
        let isNewRisk: Bool = { if case .backgroundItem = change.field { return added }; return false }()
        return Chip(text: added ? "New" : change.after == nil ? "Removed" : "Changed",
                    tint: isNewRisk || (change.field == .signatureValidity && entry.observation.signatureValidity.isFailure) ? Palette.red : Palette.amber,
                    filled: isNewRisk)
    }
}
