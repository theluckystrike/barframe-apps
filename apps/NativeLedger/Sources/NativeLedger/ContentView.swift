import AppKit
import SwiftUI
import LedgerCore

/// The window: the saved ledgers, or the Sample while it is open.
struct ContentView: View {
    @ObservedObject var state: AppState
    var body: some View {
        LedgerWindow(model: state.current, sampleOnly: state.sampleOnly,
                     openSample: { state.openSample() }, leaveSample: { state.leaveSample() })
            .id(ObjectIdentifier(state.current))
    }
}

struct SampleActions {
    var sampleOnly = false
    var open: () -> Void = {}
    var leave: () -> Void = {}
}

struct LedgerWindow: View {
    @ObservedObject var model: LedgerModel
    var sampleOnly = false
    var openSample: () -> Void = {}
    var leaveSample: () -> Void = {}
    var body: some View {
        LedgerSplitView(model: model, actions: SampleActions(sampleOnly: sampleOnly, open: openSample, leave: leaveSample))
            .navigationTitle(model.isSample ? "NativeLedger · Sample" : "NativeLedger")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { model.chooseFolders() } label: { Label("Watch a Folder", systemImage: "folder.badge.plus").labelStyle(.titleAndIcon) }
                        .disabled(!model.canWatchFolders)
                        .help(model.isSample ? "Leave Sample to watch your own folders." : "Choose a folder of apps, such as Applications. Access is read only.")
                    Button { model.chooseApps() } label: { Label("Add App", systemImage: "plus.app").labelStyle(.titleAndIcon) }
                        .disabled(!model.canAddApps)
                        .help(model.isSample ? "Leave Sample to add your own apps." : "Choose one or more apps. Access is read-only.")
                    Button { model.chooseExport() } label: { Label("Export Ledger", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon) }
                        .disabled(!model.canExport)
                        .help(model.isSample ? "Sample ledgers are not exported." : "Save a .nativeledger file in a place you choose.")
                    Button { model.chooseCompare() } label: { Label("Compare with Ledger File", systemImage: "arrow.left.arrow.right.square").labelStyle(.titleAndIcon) }
                        .help(model.isSample ? "Compare with a synthetic ledger from another Mac." : "Open a ledger file exported on another Mac.")
                }
            }
            .sheet(item: $model.comparison) { comparison in
                CompareView(comparison: comparison) { model.comparison = nil }
            }
    }
}

/// Sidebar and detail. The screenshot renderer draws this same view.
struct LedgerSplitView: View {
    @ObservedObject var model: LedgerModel
    var actions = SampleActions()
    /// The screenshot renderer sets this. An offscreen view cannot draw the floating sidebar, so the same
    /// sidebar and detail views are placed side by side instead.
    var flat = false
    /// Timeline entries shown with their details open, for the screenshot renderer.
    var expandedEntries: Set<Int>? = nil
    var scrollToEntry: Int? = nil
    @AppStorage(LedgerModel.staleKey) private var staleDays = LedgerModel.defaultStaleDays
    var body: some View {
        if flat {
            HStack(spacing: 0) {
                Sidebar(model: model, actions: actions, staleDays: staleDays, flat: true)
                    .frame(width: 280)
                    .background(Palette.sidebar)
                Rectangle().fill(Palette.rule).frame(width: 1)
                detail
            }
        } else {
            NavigationSplitView {
                Sidebar(model: model, actions: actions, staleDays: staleDays)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 360)
            } detail: {
                detail
            }
        }
    }
    private var detail: some View {
        VStack(spacing: 0) {
            if model.isSample { SampleBanner(sampleOnly: actions.sampleOnly, leave: actions.leave) }
            if model.storageCorrupt { StorageBanner(model: model) }
            else if !model.notice.isEmpty { NoticeBar(text: model.notice) }
            if let progress = model.scanProgress { ScanProgressBar(text: progress.text, fraction: progress.fraction) }
            Group {
                if model.showingRecent {
                    RecentChangesView(model: model)
                } else if let ledger = model.selectedLedger {
                    LedgerDetailView(model: model, ledger: ledger, staleDays: staleDays, expandedEntries: expandedEntries,
                                      scrollToEntry: scrollToEntry)
                } else if model.ledgers.isEmpty && model.folders.isEmpty && !model.storageCorrupt {
                    EmptyStateView(model: model, openSample: actions.open)
                } else {
                    Text("Select an app in the sidebar.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Palette.paper)
    }
}

/// What the sidebar list selects: the Recent changes item or one ledger. Folder rows are not selectable.
enum SidebarItem: Hashable {
    case recent
    case ledger(UUID)
}

struct Sidebar: View {
    @ObservedObject var model: LedgerModel
    var actions: SampleActions
    var staleDays: Int
    var flat = false
    @State private var folderToRemove: WatchedFolder?

    private var selection: Binding<SidebarItem?> {
        Binding(get: {
            if model.showingRecent { return .recent }
            return model.selection.map(SidebarItem.ledger)
        }, set: { item in
            switch item {
            case .recent?: model.showRecentChanges()
            case .ledger(let id)?: model.selection = id; model.showingRecent = false
            case nil: break
            }
        })
    }
    private var sortedLedgers: [AppLedger] {
        model.ledgers.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var content: SidebarContent { SidebarContent(model: model) }

    var body: some View {
        List(selection: selection) {
            RecentChangesRow(count: content.recentCount)
                .tag(SidebarItem.recent)
            Section(content.folders.title) {
                if let placeholder = content.folders.placeholder {
                    SidebarPlaceholderRow(text: placeholder)
                    Button { model.chooseFolders() } label: { Label("Watch a Folder", systemImage: "folder.badge.plus") }
                        .buttonStyle(.borderless)
                        .disabled(!model.canWatchFolders)
                }
                ForEach(model.folders) { folder in
                    FolderRow(folder: folder, appCount: model.appCount(folder.id), removedCount: model.removedCount(folder.id),
                              status: model.folderStatus[folder.id] ?? .idle, canRemove: model.canWrite && !model.isSample,
                              remove: { folderToRemove = folder })
                        .contextMenu {
                            Button("Check Now") { model.scanFolder(folder.id) }.disabled(model.isSample || !model.canWrite)
                            Divider()
                            Button("Remove Folder", role: .destructive) { folderToRemove = folder }
                                .disabled(model.isSample || !model.canWrite)
                        }
                }
            }
            Section {
                if let placeholder = content.apps.placeholder { SidebarPlaceholderRow(text: placeholder) }
                ForEach(sortedLedgers) { ledger in
                    SidebarRow(ledger: ledger, badge: model.badge(ledger), busy: model.isBusy(ledger.id),
                               stale: model.isStale(ledger, days: staleDays) && !ledger.isRemoved)
                        .tag(SidebarItem.ledger(ledger.id))
                        .contextMenu {
                            Button("Inspect now") { model.inspect(ledger.id) }.disabled(!model.canInspect(ledger))
                            Button("Verify chain") { model.verify(ledger.id) }
                            Button("Copy Report") { model.copyReport(ledger.id) }
                            Divider()
                            Button("Remove", role: .destructive) { model.remove(ledger.id) }.disabled(!model.canWrite)
                        }
                }
            } header: {
                HStack(spacing: 6) {
                    Text(content.apps.title)
                    if model.isSample { Chip(text: "Sample", tint: Palette.gold, filled: true).scaleEffect(0.85) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(flat ? .hidden : .automatic)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                if model.isSample {
                    Label(content.footer, systemImage: "flask")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button { actions.open() } label: { Label(content.footer, systemImage: "flask") }
                        .buttonStyle(.borderless)
                        .help("Explore a synthetic ledger. It is kept in memory and never saved.")
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(flat ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Material.bar))
        }
        .confirmationDialog(folderToRemove.map { "Remove the folder \($0.name)?" } ?? "Remove Folder",
                            isPresented: Binding(get: { folderToRemove != nil }, set: { if !$0 { folderToRemove = nil } }),
                            presenting: folderToRemove) { folder in
            Button("Remove Folder", role: .destructive) { model.removeFolder(folder.id); folderToRemove = nil }
            Button("Cancel", role: .cancel) { folderToRemove = nil }
        } message: { folder in
            let count = model.folderLedgers(folder.id).count
            Text("NativeLedger stops watching \(folder.name) and deletes the ledgers of its \(count) \(count == 1 ? "app" : "apps") and the saved access. Export first to keep a copy.")
        }
    }
}

/// What the sidebar always lists, also with no ledgers and no folders: the Recent changes item, the two section
/// headers with a muted placeholder row when a section is empty, and the Sample footer.
struct SidebarContent: Equatable {
    struct Group: Equatable {
        let title: String
        let rowCount: Int
        let placeholder: String?
    }
    static let recentTitle = "Recent changes"
    static let noFolders = "No watched folders yet"
    static let noApps = "No apps yet"
    let recentCount: Int
    let folders: Group
    let apps: Group
    /// The footer action, or the Sample note while the Sample is open.
    let footer: String

    @MainActor init(model: LedgerModel) {
        recentCount = model.recentChanges().count
        folders = Group(title: "Watched folders", rowCount: model.folders.count,
                        placeholder: model.folders.isEmpty ? Self.noFolders : nil)
        apps = Group(title: "Tracked apps", rowCount: model.ledgers.count,
                     placeholder: model.ledgers.isEmpty ? Self.noApps : nil)
        footer = model.isSample ? "Sample ledgers are synthetic and kept in memory." : "Open Sample"
    }
}

struct SidebarPlaceholderRow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.vertical, 2)
            .selectionDisabled()
    }
}

struct RecentChangesRow: View {
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Palette.green.opacity(0.14))
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.green)
            }.frame(width: 28, height: 28).accessibilityHidden(true)
            Text("Recent changes").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(nsColor: .labelColor))
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recent changes, \(count) entries in the last 7 days")
    }
}

struct FolderRow: View {
    let folder: WatchedFolder
    let appCount: Int
    var removedCount = 0
    let status: LedgerModel.FolderStatus
    var canRemove = true
    var remove: () -> Void = {}
    var body: some View {
        HStack(spacing: 10) {
            // The folder's name, count and status are one element. The remove button stays a separate element,
            // so pressing the row never opens the Remove confirmation.
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(Palette.gold.opacity(0.16))
                    Image(systemName: "folder").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.gold)
                }.frame(width: 28, height: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(nsColor: .labelColor)).lineLimit(1)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if status.progressText != nil { ProgressView().controlSize(.small) }
                else if status == .unavailable { Chip(text: "Unavailable", tint: Palette.amber) }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            if canRemove {
                Button(action: remove) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Remove Folder")
                    .accessibilityLabel("Remove Folder \(folder.name)")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
    private var subtitle: String {
        if let progress = status.progressText { return progress }
        let apps = "\(appCount) \(appCount == 1 ? "app" : "apps")"
        return removedCount > 0 ? "\(apps) · \(removedCount) removed" : apps
    }
}

struct ScanProgressBar: View {
    let text: String
    var fraction: Double?
    var body: some View {
        HStack(spacing: 10) {
            if let fraction { ProgressView(value: fraction).frame(width: 160) } else { ProgressView().controlSize(.small) }
            Text(text).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 7)
        .background(Palette.greenSoft)
    }
}

struct SidebarRow: View {
    let ledger: AppLedger
    let badge: LedgerModel.Badge
    var busy = false
    var stale = false
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Palette.badge(badge).opacity(0.14))
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.badge(badge))
            }.frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ledger.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(nsColor: .labelColor)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(ledger.latest.map { "Version " + Formatting.versionBuild($0.observation) } ?? "No entries yet")
                    if stale { Text("· not read lately").foregroundStyle(Palette.amber) }
                }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if busy { ProgressView().controlSize(.small) }
            else { Chip(text: badge.label, tint: Palette.badge(badge), filled: badge == .anomaly || badge == .broken) }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ledger.displayName), \(badge.label)")
    }
    private var symbol: String {
        switch badge {
        case .intact: return "checkmark.seal"
        case .anomaly: return "exclamationmark.triangle"
        case .broken: return "link.badge.plus"
        case .unavailable: return "lock.slash"
        case .notInspected: return "circle.dashed"
        case .removed: return "xmark.bin"
        }
    }
}

struct SampleBanner: View {
    var sampleOnly: Bool
    var leave: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flask.fill").foregroundStyle(Palette.gold)
            Text("Sample").font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(Palette.gold)
            Text("Synthetic ledgers kept in memory. Nothing here is saved or read from your apps.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if !sampleOnly { Button("Leave Sample", action: leave).controlSize(.small) }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Palette.goldSoft)
        .accessibilityElement(children: .contain)
    }
}

struct StorageBanner: View {
    @ObservedObject var model: LedgerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.notice).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Retry saved data") { model.retrySavedData() }
                Button("Start fresh (keeps a copy)") { model.recoverStartingFresh() }
            }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Palette.amber.opacity(0.15))
    }
}

struct NoticeBar: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 7)
            .background(Color.primary.opacity(0.04))
    }
}

struct EmptyStateView: View {
    @ObservedObject var model: LedgerModel
    var openSample: () -> Void
    var body: some View {
        // A scroll view inside a geometry reader: the empty state takes the height it is offered and scrolls when
        // that is too small, so it never grows the split view or the window.
        GeometryReader { proxy in
            ScrollView {
                content.frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
        }
        .frame(minWidth: 0, idealWidth: 480, maxWidth: .infinity, minHeight: 0, idealHeight: 480, maxHeight: .infinity)
    }
    private var content: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            ZStack {
                Circle().fill(Palette.greenSoft).frame(width: 110, height: 110)
                Image(systemName: "link").font(.system(size: 46, weight: .semibold)).foregroundStyle(Palette.green)
            }
            VStack(spacing: 8) {
                Text("Start an automatic ledger").font(.system(size: 30, weight: .semibold, design: .serif))
                Text("Watch a folder such as Applications. While NativeLedger is open, it records a dated entry each time an app in it changes, and links each entry to the one before it.")
                    .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 600).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button { model.chooseFolders() } label: { Label("Watch a Folder", systemImage: "folder.badge.plus").padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).tint(Palette.green).controlSize(.large)
                    .disabled(!model.canWatchFolders)
                    .keyboardShortcut(.defaultAction)
                Button { model.chooseApps() } label: { Label("Add App", systemImage: "plus.app").padding(.horizontal, 6) }
                    .controlSize(.large)
                    .disabled(!model.canAddApps)
                Button { openSample() } label: { Label("Open Sample", systemImage: "flask").padding(.horizontal, 6) }
                    .controlSize(.large)
            }
            HStack(alignment: .top, spacing: 14) {
                step(1, "Watch a Folder", "Choose a folder of apps. Access is read only. Each app gets its own ledger.", "folder.badge.plus")
                step(2, "Automatic entries", "A changed app gets a new entry a few seconds later. Unchanged apps add none.", "clock.arrow.circlepath")
                step(3, "Verify and compare", "Check the hash chain, export it and compare with another Mac.", "checkmark.seal")
            }.frame(maxWidth: 800)
            Text("To track a single app, choose Add App. Open Sample shows synthetic ledgers that are never saved.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 20)
        }
        .padding(30)
    }
    private func step(_ n: Int, _ title: String, _ text: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Circle().fill(Palette.green))
                Image(systemName: symbol).foregroundStyle(Palette.green)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.rule))
    }
}
