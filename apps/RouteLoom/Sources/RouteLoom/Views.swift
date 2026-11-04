import SwiftUI
import AppKit
import ServiceManagement
import RouteLoomCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Image(systemName:"point.3.connected.trianglepath.dotted").font(.title).foregroundStyle(.teal).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:3) { Text("RouteLoom").font(.title2.bold()); Text(model.tr("Compare connection failures together")).font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                if model.sample { stateBadge("Sample",.teal) }
                SettingsLink { Image(systemName:"gearshape").font(.title3) }.accessibilityLabel(model.tr("Settings"))
            }
            if let error = model.error { Text(model.tr(error)).font(.callout).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) }
            if let shortcutError = model.shortcutError { Text(model.tr(shortcutError)).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            if model.sessions.isEmpty {
                Spacer()
                VStack(alignment:.leading,spacing:16) {
                    Text(model.tr("Two endpoints. One clearer story.")).font(.system(size:28,weight:.semibold))
                    Text(model.tr("Add a reference endpoint and a work endpoint in Settings. RouteLoom checks them together and keeps an incident report on this Mac.")).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text(model.tr("Nothing runs until you start. Both endpoints receive HTTPS HEAD requests during a live session.")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    HStack {
                        if model.valid { Button(model.tr("Start session")) { model.start() }.accessibilityLabel(model.tr("Start session")).buttonStyle(.borderedProminent).tint(.teal).keyboardShortcut(.defaultAction) }
                        else { SettingsLink { Text(model.tr("Configure pair")) }.accessibilityLabel(model.tr("Configure pair")) }
                        Button(model.tr("Try Sample")) { model.toggleSample(true) }.accessibilityLabel(model.tr("Try Sample")).keyboardShortcut("s",modifiers:[.command,.shift]).buttonStyle(.borderedProminent).tint(.teal) }
                }.padding(28).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.6),in:RoundedRectangle(cornerRadius:16))
                Spacer()
            } else {
                controls
                HStack(alignment:.top,spacing:18) {
                    VStack(alignment:.leading,spacing:14) {
                        Text(model.tr("Sessions")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollView {
                            VStack(spacing:8) {
                                ForEach(model.sessions) { session in
                                    Button { model.selectedID = session.id } label: {
                                        VStack(alignment:.leading,spacing:6) {
                                            Text(session.sample ? model.tr(session.name) : session.name).font(.callout.weight(.semibold)).lineLimit(2)
                                            Text(session.started.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                                            Text(model.tr(session.ended == nil ? "Active" : "Stopped")).font(.caption).foregroundStyle(session.ended == nil ? .teal : .secondary)
                                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                                            .background(model.selected?.id == session.id ? Color.teal.opacity(0.12) : Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
                                    }.buttonStyle(.plain).accessibilityLabel((session.sample ? "Sample " : "") + session.name + " " + model.tr("session"))
                                }
                            }
                        }
                    }.frame(width:190)
                    if let session = model.selected {
                        VStack(alignment:.leading,spacing:14) {
                            incidentCard(session)
                            HStack {
                                Text(model.tr("Paired observations")).font(.headline)
                                Spacer()
                                Text("\(session.checks.count) " + model.tr("checks")).font(.caption).foregroundStyle(.secondary)
                            }
                            if session.checks.isEmpty { Text(model.tr("Waiting for both responses")).foregroundStyle(.secondary) }
                            ScrollView {
                                VStack(spacing:8) {
                                    ForEach(session.checks.reversed()) { check in
                                        HStack(alignment:.top,spacing:12) {
                                            Circle().fill(color(check.state)).frame(width:7,height:7).padding(.top,6).accessibilityHidden(true)
                                            VStack(alignment:.leading,spacing:4) {
                                                HStack { Text(model.tr(check.state.label)).font(.callout.weight(.semibold)); Spacer(); Text(check.at.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                                                HStack(alignment:.top) {
                                                    observation(model.tr("Reference"),check.reference)
                                                    Spacer(minLength:8)
                                                    observation(model.tr("Work"),check.work)
                                                }
                                            }
                                        }.padding(10).background(Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:9))
                                    }
                                }
                            }.frame(maxHeight:.infinity)
                            if let gap = session.gaps.last {
                                Label(model.tr("Unknown gap") + " · " + String(format:"%.0f",gap.duration) + " " + model.tr("seconds") + " · " + model.tr("not measured downtime"),systemImage:"moon.zzz").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            }
                            HStack {
                                Button(model.tr("Preview report")) { model.copied = false; model.showReport = true }.accessibilityLabel(model.tr("Preview report")).buttonStyle(.borderedProminent).tint(.teal)
                                Button(model.tr("Compare sessions")) { model.showCompare = true }.accessibilityLabel(model.tr("Compare sessions")).disabled(!model.sessions.contains { $0.started < (model.selected?.started ?? .distantPast) })
                                Spacer()
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
            }
            Divider()
            HStack { PolicyLinks(model:model); Spacer(); Button(model.tr("Quit")) { model.stop(); NSApp.terminate(nil) }.accessibilityLabel(model.tr("Quit")) }
        }.padding(24).frame(width:820,height:680)
            .background(Color(nsColor:.windowBackgroundColor))
            .sheet(isPresented:$model.showReport) { ReportView(model:model) }
            .sheet(isPresented:$model.showCompare) { CompareView(model:model) }
            .background(WindowReader { window in NotificationCenter.default.post(name:.routeWindow,object:window) })
    }
    private var controls: some View {
        HStack(spacing:12) {
            if model.sample {
                Picker(model.tr("Sample case"),selection:$model.scenario) {
                    Text(model.tr("Timeout")).tag(Transport.timeout)
                    Text(model.tr("TLS failure")).tag(Transport.tls)
                    Text(model.tr("Offline")).tag(Transport.offline)
                    Text(model.tr("Reference failure")).tag(Transport.dns)
                    Text(model.tr("Missing evidence")).tag(Transport.unknown)
                }.frame(width:260).onChange(of:model.scenario) { model.resetSample() }
                Button(model.tr("Reset Sample")) { model.resetSample() }.accessibilityLabel(model.tr("Reset Sample"))
                Spacer()
                Button(model.tr("Exit Sample")) { model.toggleSample(false) }.accessibilityLabel(model.tr("Exit Sample"))
            } else {
                Text(model.tr(model.running ? (model.sleeping ? "Paused during sleep" : model.checking ? "Checking pair" : model.isStale ? "Evidence is stale" : "Session running") : "Stopped")).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if model.running { Button(model.tr("Stop session")) { model.stop() }.accessibilityLabel(model.tr("Stop session")) }
                else { Button(model.tr("Start session")) { model.start() }.accessibilityLabel(model.tr("Start session")).buttonStyle(.borderedProminent).tint(.teal).disabled(!model.valid) }
                Button(model.tr("Try Sample")) { model.toggleSample(true) }.accessibilityLabel(model.tr("Try Sample")).keyboardShortcut("s",modifiers:[.command,.shift])
            }
        }.padding(12).background(Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
    }
    private func incidentCard(_ s: Session) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text(model.tr(s.latestIncident == nil ? "Pair overview" : "Latest incident")).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); stateBadge(model.tr(s.sample ? "Sample" : s.ended == nil ? "Live" : "Stopped"),.teal) }
            Text(model.tr(s.latestIncident?.checks.first?.state.label ?? s.current.label)).font(.title3.weight(.semibold))
            HStack(spacing:18) {
                Text(s.referenceHost).lineLimit(1).truncationMode(.middle)
                Image(systemName:"arrow.left.arrow.right").accessibilityHidden(true)
                Text(s.workHost).lineLimit(1).truncationMode(.middle)
            }.font(.caption).foregroundStyle(.secondary)
            if let i = s.latestIncident {
                Text(incidentSummary(i)).font(.caption.weight(.medium))
            }
            if s.checks.last?.reference?.error == .denied || s.checks.last?.work?.error == .denied {
                Text(model.tr("Network access was denied. Check system privacy settings or choose another HTTPS endpoint.")).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
            }
            Text(model.tr("A possible lead, not proof of an ISP, DNS or VPN fault.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.teal.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
    }
    private func incidentSummary(_ i: Incident) -> String {
        let duration = String(format:"%.0f",i.observedDuration) + " " + model.tr("seconds")
        let recovery = model.tr(i.end == nil ? "Recovery not observed" : "Recovered")
        return [model.tr("Observed span"),duration,recovery].joined(separator:" · ")
    }
    private func observation(_ label: String,_ o: Observation?) -> some View {
        VStack(alignment:.leading,spacing:2) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(o?.status.map { "HTTP \($0)" } ?? model.tr(o?.error?.rawValue ?? "unknown")).font(.caption.monospaced())
            if let o { Text(String(format:"%.0f ms",o.elapsed*1000)).font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
func stateBadge(_ text: String,_ color: Color) -> some View { Text(text).font(.caption.weight(.semibold)).padding(.horizontal,10).padding(.vertical,4).foregroundStyle(color).background(color.opacity(0.12),in:Capsule()) }
func color(_ state: PairState) -> Color { state == .healthy ? .teal : state == .insufficient ? .gray : .orange }
struct PolicyLinks: View {
    @ObservedObject var model: AppModel
    @State private var document: AppDocument?
    var body: some View {
        HStack(spacing:12) {
            documentButton(.privacy)
            documentButton(.support)
        }.font(.caption)
            .sheet(item:$document) { doc in
                VStack(alignment:.leading,spacing:16) {
                    Text(model.tr(doc.title)).font(.title2.bold())
                    ScrollView { Text(doc.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                    HStack { Spacer(); Button(model.tr("Done")) { document = nil }.keyboardShortcut(.cancelAction) }
                }.padding(24).frame(width:620,height:580)
            }
    }
    private func documentButton(_ doc: AppDocument) -> some View {
        Button(model.tr(doc.title)) {
            if let url = doc.webURL() {
                if !NSWorkspace.shared.open(url) { document = doc }
            } else { document = doc }
        }.buttonStyle(.link).accessibilityLabel(model.tr(doc.title))
    }
}
struct ReportView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text(model.tr("Support report preview")).font(.title2.bold()); Spacer(); if model.sample { stateBadge("Sample",.teal) } }
            Text(model.tr("Only hostnames are included. Paths and query strings stay out of the report. Copying sends nothing to a server.")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            ScrollView { Text(model.reportText).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.padding(14).background(Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
            HStack { Button(model.tr(model.copied ? "Copied" : "Copy report")) { model.copyReport() }.accessibilityLabel(model.tr(model.copied ? "Copied" : "Copy report")).buttonStyle(.borderedProminent).tint(.teal); Spacer(); Button(model.tr("Done")) { model.showReport = false }.accessibilityLabel(model.tr("Done")).keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width:780,height:640).background(Color(nsColor:.windowBackgroundColor))
    }
}
struct CompareView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text(model.tr("Compare observed sessions")).font(.title2.bold());Spacer();if model.sample { stateBadge("Sample",.teal) } }
            if let recent = model.selected {
                Text(model.tr("Recent session") + " · " + recent.started.formatted(date:.abbreviated,time:.shortened)).foregroundStyle(.secondary)
                Picker(model.tr("Earlier session"),selection:Binding(get:{ model.earlier?.id ?? UUID() },set:{model.earlierID = $0})) {
                    ForEach(model.sessions.filter { $0.started < recent.started }) { s in Text(s.started.formatted(date:.abbreviated,time:.shortened)).tag(s.id) }
                }
                if let earlier = model.earlier,earlier.id != recent.id {
                    Text(model.tr(recent.referenceHost == earlier.referenceHost && recent.workHost == earlier.workHost ? "Same endpoint hostnames" : "Different endpoint hostnames · compare with care")).font(.callout).foregroundStyle(.secondary)
                    HStack { Text(model.tr("Observation"));Spacer();Text(model.tr("Recent"));Text(model.tr("Earlier")).frame(width:75) }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(PairState.allCases,id:\.self) { state in
                        HStack { Circle().fill(color(state)).frame(width:8,height:8).accessibilityHidden(true);Text(model.tr(state.label));Spacer();Text("\(recent.counts[state,default:0])");Text("\(earlier.counts[state,default:0])").frame(width:75) }.padding(12).background(Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:8))
                    }
                    Text(model.tr("Checks are counts, not continuous uptime measurements")).font(.caption).foregroundStyle(.secondary)
                } else { Text(model.tr("Select a different earlier session")) }
            }
            Spacer();HStack { PolicyLinks(model:model);Spacer();Button(model.tr("Done")) { model.showCompare = false }.accessibilityLabel(model.tr("Done")).keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width:780,height:610).background(Color(nsColor:.windowBackgroundColor))
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(model.tr("RouteLoom settings")).font(.title2.bold())
            Form {
                TextField(model.tr("Pair name"),text:$model.pairName).disabled(model.running)
                TextField(model.tr("Reference HTTPS URL"),text:$model.referenceURL).disabled(model.running).accessibilityIdentifier("referenceEndpoint")
                TextField(model.tr("Work HTTPS URL"),text:$model.workURL).disabled(model.running).accessibilityIdentifier("workEndpoint")
            }.textFieldStyle(.roundedBorder)
            Text(model.tr("Both endpoints receive requests when a live session runs. Use public health endpoints without credentials. Redirects are not followed. HTTP errors still prove a response was received.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if !model.referenceURL.isEmpty || !model.workURL.isEmpty {
                if model.valid { Label(model.tr("Pair ready to start"),systemImage:"checkmark.circle").font(.caption).foregroundStyle(.teal) }
                else { Text(model.tr("Add a pair name and two HTTPS URLs without embedded credentials or fragments.")).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            }
            HStack { Picker(model.tr("Interval"),selection:$model.interval) { ForEach([10.0,30,60,120],id:\.self) { Text("\(Int($0)) " + model.tr("seconds")).tag($0) } };Picker(model.tr("Timeout"),selection:$model.timeout) { ForEach([2.0,8,15,30],id:\.self) { Text("\(Int($0)) " + model.tr("seconds")).tag($0) } } }
            Picker(model.tr("Keep recent sessions"),selection:$model.retention) { ForEach([5,20,50],id:\.self) { Text("\($0)").tag($0) } }
            Picker(model.tr("Open current incident"),selection:$model.shortcut) {
                Text("Control Option R").tag(0); Text("Command Shift R").tag(1);Text(model.tr("Disabled")).tag(2)
            }
            if let error = model.shortcutError { Text(model.tr(error)).font(.caption).foregroundStyle(.orange) }
            Toggle(model.tr("Show brief menu text"),isOn:$model.showMenuText)
            Toggle(model.tr("Launch at login"),isOn:Binding(get:{login},set:{enable in
                do { if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = SMAppService.mainApp.status == .requiresApproval ? model.tr("Approve RouteLoom in System Settings under Login Items") : nil
                } catch { loginError = error.localizedDescription }
                login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            }))
            if let error = loginError { Text(error).font(.caption).foregroundStyle(.orange) }
            Toggle(model.tr("Sample mode"),isOn:Binding(get:{model.sample},set:{model.toggleSample($0)}))
            Picker(model.tr("Language"),selection:$model.spanish) { Text("English").tag(false);Text("Español").tag(true) }
            Text(model.tr("History stays on this Mac. Sleep and app shutdown are unknown gaps. Clearing data stops the session and removes endpoints and saved history.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Button(model.tr("Clear local data"),role:.destructive) { model.clearData() }.accessibilityLabel(model.tr("Clear local data"))
            Divider(); HStack { PolicyLinks(model:model);Spacer();Text("1.0.0").font(.caption).foregroundStyle(.secondary) }
        }.padding(24).frame(width:600).background(Color(nsColor:.windowBackgroundColor))
    }
}
struct WindowReader: NSViewRepresentable {
    var read: (NSWindow) -> Void
    func makeNSView(context:Context) -> NSView { let v = NSView();DispatchQueue.main.async { if let w = v.window { read(w) } };return v }
    func updateNSView(_ view:NSView,context:Context) { DispatchQueue.main.async { if let w = view.window { read(w) } } }
}
extension Notification.Name {
    static let routeWindow = Notification.Name("RouteLoomWindow")
    static let routeHotkey = Notification.Name("RouteLoomHotkey")
}
