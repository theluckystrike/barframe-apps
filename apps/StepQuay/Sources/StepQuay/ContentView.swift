import SwiftUI
import StepQuayCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var title = ""
    @State private var minutes: Double = 10
    @State private var note = ""
    @State private var interrupting = false
    @State private var revising = false
    @State private var revisedMinutes: Double = 5
    @State private var editing: Action?
    @State private var history = false
    @State private var expanded: Bool
    init(model: AppModel, expanded: Bool = false) { self.model = model; _expanded = State(initialValue: expanded) }
    private var showsQueue: Bool { expanded || model.queue.current == nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.teal).accessibilityHidden(true)
                Text("StepQuay").font(.title2.bold())
                Spacer()
                if model.sampleMode { Text("Sample").font(.caption.bold()).padding(7).background(.teal.opacity(0.15), in: Capsule()) }
                SettingsLink { Image(systemName: "gearshape").accessibilityLabel(model.l("Settings")) }
                    .help(model.l("Settings"))
            }
            if model.queue.actions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.l("Add your next action")).font(.title3.bold())
                    Text(model.l("Give one small task a name and an estimate. Your queue stays on this Mac.")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(model.l("Try Sample")) { model.toggleSample(true) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            if let action = model.queue.current {
                currentCard(action)
                Button(model.l(expanded ? "Hide queue" : "Show queue")) { expanded.toggle() }.accessibilityLabel(model.l(expanded ? "Hide queue" : "Show queue")).accessibilityIdentifier("queueDisclosure").font(.caption)
            } else if !model.queue.actions.isEmpty {
                Button(model.l("Start next")) { model.start() }.accessibilityLabel(model.l("Start next")).accessibilityIdentifier("startNext").buttonStyle(.borderedProminent).tint(.teal).keyboardShortcut(.return, modifiers: .command)
            }
            if showsQueue {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.l("Action queue")).font(.headline)
                        Spacer()
                        Text(model.l("Available minutes")).font(.caption)
                        TextField(model.l("Available minutes"), value: Binding(get: { model.queue.budget / 60 }, set: { value in
                            if value.isFinite && value > 0 && value <= 1440 { model.change { $0.budget = value * 60 } }
                            else { model.message = model.l("Enter minutes greater than zero and no more than 1440.") }
                        }), format: .number).frame(width: 58).textFieldStyle(.roundedBorder)
                    }
                    Text(model.l("Fit preview preserves your queue order.")).font(.caption).foregroundStyle(.secondary)
                    if !model.queue.actions.isEmpty {
                        ScrollView {
                            VStack(spacing: 6) { ForEach(model.queue.actions) { action in actionRow(action) } }
                        }.frame(height: min(CGFloat(model.queue.actions.count) * 92, 200))
                    }
                }
                Divider()
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.l("Task title")).font(.caption)
                        TextField(model.l("Task title"), text: $title).textFieldStyle(.roundedBorder).onSubmit { addAction() }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.l("Minutes")).font(.caption)
                        TextField(model.l("Minutes"), value: $minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                    }
                    Button(model.l("Add")) { addAction() }.accessibilityLabel(model.l("Add action"))
                }
            }
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if !model.shortcutError.isEmpty { Text(model.shortcutError).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack(spacing: 12) {
                Button(model.l("Session history")) { history = true }.disabled(model.queue.history.isEmpty)
                if !model.queue.history.isEmpty { Button(model.l("Undo completion")) { model.change { try $0.undo() } }.accessibilityLabel(model.l("Undo completion")).accessibilityIdentifier("undoCompletion") }
                Spacer()
                Button(model.l(model.sampleMode ? "Use live queue" : "Try Sample")) { model.toggleSample(!model.sampleMode) }
            }.font(.caption)
            HStack {
                PolicySupportLinks(model: model)
                Spacer()
                Button(model.l("Quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
            }.font(.caption)
        }
        .padding(22).frame(width: 580)
        .onAppear { minutes = model.defaultMinutes }
        .sheet(isPresented: $interrupting) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.l("Interrupt action")).font(.title2.bold())
                Text(model.l("Where should you pick up next?"))
                TextField(model.l("Resume note"), text: $note, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder)
                Text(model.l("A short note is required before pausing.")).font(.caption).foregroundStyle(.secondary)
                if !model.message.isEmpty { Text(model.message).foregroundStyle(.orange) }
                HStack { Button(model.l("Cancel")) { interrupting = false }.keyboardShortcut(.cancelAction); Spacer()
                    Button(model.l("Pause with note")) {
                        model.change { try $0.interrupt(note: note, now: ProcessInfo.processInfo.systemUptime) }
                        if model.message.isEmpty { interrupting = false; note = "" }
                    }.keyboardShortcut(.defaultAction).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 500)
        }
        .sheet(item: $editing) { action in ActionEditor(model: model, action: action) }
        .sheet(isPresented: $revising) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.l("Revise remaining")).font(.title2.bold())
                TextField(model.l("Remaining minutes"), value: $revisedMinutes, format: .number).textFieldStyle(.roundedBorder)
                if !model.message.isEmpty { Text(model.message).foregroundStyle(.orange) }
                HStack {
                    Button(model.l("Cancel")) { revising = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(model.l("Save")) { model.change { try $0.reviseRemaining(minutes: revisedMinutes, now: ProcessInfo.processInfo.systemUptime) }; if model.message.isEmpty { revising = false } }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 460)
        }
        .sheet(isPresented: $history) { HistoryView(model: model) }
    }
    private func addAction() {
        model.change { try $0.add(title: title, minutes: minutes) }
        if model.message.isEmpty { title = ""; minutes = model.defaultMinutes }
    }
    @ViewBuilder private func currentCard(_ action: Action) -> some View {
        VStack(alignment: .leading, spacing: expanded ? 8 : 12) {
            HStack {
                Label(model.l(action.phase == .paused ? "Paused" : action.remaining <= 0 ? "Overdue" : "Current action"), systemImage: model.symbol).font(.caption.bold())
                Spacer()
            }.foregroundStyle(action.remaining <= 0 ? .orange : .teal)
            Text(action.title).font(.system(size: expanded ? 22 : 26, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text(TimeText.clock(action.remaining)).font(.system(size: expanded ? 32 : 40, weight: .medium, design: .rounded)).monospacedDigit()
                Text(model.l(action.remaining <= 0 ? "Over estimate" : "Remaining effort")).font(.caption).foregroundStyle(.secondary)
            }
            if let note = action.notes.last {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.l("Resume note")).font(.caption.bold()).foregroundStyle(.teal)
                    Text(model.l(note.note)).fixedSize(horizontal: false, vertical: true)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                if action.phase == .paused {
                    Button(model.l("Resume")) { model.resume() }.accessibilityLabel(model.l("Resume")).accessibilityIdentifier("resumeAction").keyboardShortcut("r", modifiers: .command).buttonStyle(.borderedProminent).tint(.teal)
                } else {
                    Button(model.l("Interrupt")) { note = ""; interrupting = true }.accessibilityLabel(model.l("Interrupt")).accessibilityIdentifier("interruptAction").keyboardShortcut("i", modifiers: .command)
                }
                Button(model.l("Finish")) { model.finish() }.accessibilityLabel(model.l("Finish")).accessibilityIdentifier("finishAction").keyboardShortcut("f", modifiers: .command)
                Spacer()
                Button(model.l("Defer")) { model.deferAction() }.accessibilityLabel(model.l("Defer")).accessibilityIdentifier("deferAction")
            }
            if action.remaining <= 0 {
                Text(model.l("Time is guidance. Only you can complete this action.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if action.phase == .running {
                        Button(model.l("Continue")) { model.message = model.l("Continue past the estimate") }.accessibilityLabel(model.l("Continue")).accessibilityIdentifier("continueAction")
                    }
                    Button(model.l("Revise remaining")) { revisedMinutes = model.defaultMinutes; revising = true }.accessibilityLabel(model.l("Revise remaining")).accessibilityIdentifier("reviseAction")
                }
            }
        }.padding(expanded ? 14 : 18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.teal.opacity(0.25)))
    }
    private func actionRow(_ action: Action) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title).font(.subheadline.weight(.medium)).lineLimit(2)
                HStack {
                    Text(TimeText.clock(action.remaining)).monospacedDigit()
                    Text(model.l(action.remaining <= 0 ? "Overdue" : model.queue.fittingIDs.contains(action.id) ? "Fits" : "Overflow"))
                    if action.id == model.queue.selectedID { Text(model.l(action.phase == .paused ? "Paused" : "Running")) }
                }.font(.caption).foregroundStyle(.secondary)
                if let note = action.notes.last {
                    Text(model.l("Resume note") + " " + model.l(note.note)).font(.caption).foregroundStyle(.teal).lineLimit(2)
                }
            }
            Spacer(minLength: 3)
            Button { model.change { $0.move(action.id, by: -1) } } label: { Image(systemName: "arrow.up").accessibilityLabel(model.l("Move up") + " " + action.title) }.help(model.l("Move up"))
            Button { model.change { $0.move(action.id, by: 1) } } label: { Image(systemName: "arrow.down").accessibilityLabel(model.l("Move down") + " " + action.title) }.help(model.l("Move down"))
            Button { editing = action } label: { Image(systemName: "pencil").accessibilityLabel(model.l("Edit") + " " + action.title) }.help(model.l("Edit"))
            Button { model.change { $0.delete(action.id) } } label: { Image(systemName: "trash").accessibilityLabel(model.l("Delete action") + " " + action.title) }.disabled(action.id == model.queue.selectedID).help(model.l("Delete action"))
        }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct ActionEditor: View {
    @ObservedObject var model: AppModel
    let action: Action
    @Environment(\.dismiss) var dismiss
    @State private var title: String
    @State private var minutes: Double
    init(model: AppModel, action: Action) { self.model = model; self.action = action; _title = State(initialValue: action.title); _minutes = State(initialValue: max(1, action.remaining / 60)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.l("Edit action")).font(.title2.bold())
            TextField(model.l("Task title"), text: $title).textFieldStyle(.roundedBorder)
            Text(model.l("Remaining minutes")).font(.caption)
            TextField(model.l("Remaining minutes"), value: $minutes, format: .number).textFieldStyle(.roundedBorder)
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.orange) }
            HStack { Button(model.l("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                Button(model.l("Save")) { model.tick(); model.change { try $0.edit(action.id, title: title, minutes: minutes) }; if model.message.isEmpty { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 460)
    }
}
struct HistoryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.l("Session history")).font(.title2.bold())
            if model.sampleMode { Text("Sample").foregroundStyle(.teal) }
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if model.queue.history.isEmpty { Text(model.l("No completed actions yet")) }
                    ForEach(model.queue.history.reversed()) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.action.title).font(.headline)
                            Text(record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            Text(model.l("Estimated") + " " + TimeText.clock(record.action.estimate) + " · " + model.l("Active") + " " + TimeText.clock(record.action.active)).font(.caption)
                            ForEach(Array(record.action.notes.enumerated()), id: \.offset) { _, note in Text(model.l(note.note)).font(.caption).fixedSize(horizontal: false, vertical: true) }
                        }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(model.l("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(24).frame(width: 520, height: 470)
    }
}
struct PolicySupportLinks: View {
    @ObservedObject var model: AppModel
    @State private var document: LocalDocument?
    var body: some View {
        HStack(spacing: 12) {
            ForEach(LocalDocument.allCases) { item in
                Button(model.l(item.title)) {
                    if let url = item.webURL() { NSWorkspace.shared.open(url) }
                    else { document = item }
                }
            }
        }.font(.caption)
        .sheet(item: $document) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text(model.l(item.title)).font(.title2.bold())
                ScrollView { Text(item.text(spanish: model.spanish)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button(model.l("Close")) { document = nil }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 520, height: 470)
        }
    }
}
