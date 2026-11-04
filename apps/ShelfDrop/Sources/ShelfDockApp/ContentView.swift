import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ShelfDockCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showingNewGroupField = false
    @State private var newGroupName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ShelfDock").font(.headline)
                Spacer()
                if model.isSample {
                    Text("Sample").font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .accessibilityLabel("Sample data is shown")
                    Button("Live") { model.setSample(false) }
                        .accessibilityLabel("Leave sample mode")
                }
                Button { model.setSample(true) } label: {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.borderless)
                .help("Try with sample items")
                .accessibilityLabel("Show sample shelf")
                Menu {
                    Button("Settings…") { model.openSettings() }
                    Button("Quit") { NSApp.terminate(nil) }
                    Divider()
                    Button("Privacy Policy") { model.openPage(.privacy) }
                    Button("Support") { model.openPage(.support) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .accessibilityLabel("ShelfDock menu")
            }

            if model.store.groups.count > 1 {
                Picker("Group", selection: Binding(
                    get: { model.selectedGroupID ?? model.store.groups[0].id },
                    set: { model.selectedGroupID = $0 })) {
                    ForEach(model.store.groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Shelf group")
            }

            HStack {
                TextField("Filter", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Filter shelf items")
                if !model.query.isEmpty { Button("Reset") { model.query = "" } }
            }

            if model.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(model.emptyStateMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                    if model.query.isEmpty {
                        Button("Paste from Clipboard") { model.addPasteboardText() }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.items) { item in ShelfRow(item: item, model: model) }
                    }.padding(8)
                }
                .frame(height: 250)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }

            if let error = model.store.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("Shelf error: \(error)")
            }

            HStack(spacing: 10) {
                Button("Clear Shelf") {
                    model.store.clearAll(in: model.store.isDefaultGroup ? nil : model.currentGroup)
                }
                .disabled(model.items.isEmpty)
                .accessibilityLabel("Clear the shelf")
                Spacer()
                Button("Add Clipboard Text") { model.addPasteboardText() }

            }

            Toggle("Clear items after drag out", isOn: Binding(
                get: { model.store.clearAfterDragOut },
                set: { model.store.clearAfterDragOut = $0 }))
                .font(.caption)
                .accessibilityLabel("Clear items after drag out")

            if !model.store.recentlyClearedIDs.isEmpty {
                Button("Undo cleared drag") { model.store.restoreRecentlyCleared() }
            }
            if showingNewGroupField {
                HStack {
                    TextField("Group name", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if model.store.createGroup(named: newGroupName) == nil { newGroupName = ""; showingNewGroupField = false }
                        }
                    Button("Create") {
                        if model.store.createGroup(named: newGroupName) == nil { newGroupName = ""; showingNewGroupField = false }
                    }
                }
            } else {
                Button("New Group…") { showingNewGroupField = true }
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 400, height: 560, alignment: .top)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                .opacity(0)
        )
        .onDrop(of: [UTType.fileURL, UTType.plainText, UTType.image], isTargeted: nil) { providers in
            model.addDrop(providers: providers)
            return !providers.isEmpty
        }
    }
}

struct ShelfRow: View {
    let item: ShelfItem
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(item.isDirectory ? Color.blue : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).font(.body)
                Text(model.fileIssue(item) ?? (item.isDirectory ? "Folder" : item.isText ? "Text" : item.imageData != nil ? "Image" : "File"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Copy to Clipboard") { _ = model.copy(item) }
                Button("Share…") { model.share(item) }
                Button("Quick Look") { model.quickLook(item) }
                Menu("Move to Group") {
                    ForEach(model.store.groups) { group in
                        Button(group.name) { model.store.moveToGroup(id: item.id, group: group) }
                    }
                }
                Divider()
                Button("Remove", role: .destructive) { model.store.remove(id: item.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .accessibilityLabel("Actions for \(item.name)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            DragSource(item: item, model: model).padding(.trailing, 36)
        }
    }

    private var icon: String {
        if item.isDirectory { return "folder.fill" }
        if item.isText { return "doc.plaintext" }
        if item.imageData != nil { return "photo" }
        return "doc.fill"
    }
}

