import AppKit
import SwiftUI
import HeadroomModel

@MainActor final class State: ObservableObject {
 @Published var reading = Reading(memoryOK:false,processesOK:false)
 @Published var sample = false
 @Published var scenario = 0
 @Published var budget = 2.0
 @Published var busy = false
 func refresh() {
  if sample { reading = .sample(scenario); return }
  guard !busy else { return }; busy=true
  Task { let value = await Task.detached { Reading.live() }.value; if !sample { reading=value }; busy=false }
 }
}
struct Dashboard: View {
 @ObservedObject var state: State
 var r: Reading { state.reading }
 var accent: Color { r.pressure == 1 && r.swap == 0 ? Color(red:0.22,green:0.88,blue:0.72) : .orange }
 func metric(_ title:String,_ value:String,_ note:String) -> some View {
  VStack(alignment:.leading,spacing:12) { Text(title).font(.headline).foregroundStyle(.secondary); Text(value).font(.system(size:32,weight:.semibold,design:.rounded)); Text(note).font(.callout).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(22).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:18))
 }
 var body: some View {
  VStack(alignment:.leading,spacing:24) {
   HStack { VStack(alignment:.leading,spacing:4) { Text("Headroom").font(.system(size:30,weight:.bold,design:.rounded)); Text("AGENT MEMORY").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.secondary) }; Spacer(); Text(state.sample ? "SAMPLE DATA" : "LIVE · THIS DEVICE").font(.caption.weight(.bold)).padding(10).background(accent.opacity(0.12),in:Capsule()).foregroundStyle(accent) }
   HStack(alignment:.top,spacing:28) {
    VStack(alignment:.leading,spacing:16) {
     Text("Plan your next agent").font(.system(size:38,weight:.bold,design:.rounded))
     Text("An explicit memory budget for parallel coding.").foregroundStyle(.secondary).font(.title3)
     HStack(alignment:.firstTextBaseline,spacing:18) { Text(r.capacity(budget:state.budget).map(String.init) ?? "—").font(.system(size:104,weight:.bold,design:.rounded)).foregroundStyle(accent); VStack(alignment:.leading,spacing:8) { Text("more agents").font(.title2.bold()); Text("ESTIMATE · NOT A GUARANTEE").font(.caption.weight(.semibold)).foregroundStyle(.secondary) } }
     Text(r.memoryOK ? (r.swap > 0 ? "Swap is already in use. Start no more agents on this budget." : r.pressure != 1 ? "Memory pressure is elevated. Leave room for current work." : "Available memory minus a 4 GiB reserve, divided by your agent budget.") : "Memory data is unavailable. No capacity estimate is shown.").font(.body).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    }.frame(maxWidth:.infinity,alignment:.leading)
    VStack(alignment:.leading,spacing:18) {
     Text("YOUR ASSUMPTION").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
     Text(String(format:"%.1f GiB",state.budget)).font(.system(size:38,weight:.semibold,design:.rounded))
     Text("Memory budget per new agent").foregroundStyle(.secondary)
     Slider(value:$state.budget,in:0.5...16,step:0.5).tint(accent).accessibilityLabel("Memory budget per agent in GiB")
     Divider(); Text("4 GiB kept in reserve").font(.headline)
     Text("Use a larger budget for heavy builds or long sessions. Workloads can grow after launch.").font(.callout).foregroundStyle(.secondary)
    }.padding(24).frame(width:300).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:20))
   }
   HStack(spacing:16) {
    metric("Available",r.memoryOK ? String(format:"%.1f GiB",r.available) : "—","System memory estimate")
    metric("Pressure",r.pressureText,r.memoryOK ? String(format:"%.1f GiB swap in use",r.swap) : "Probe unavailable")
    metric("Detected agents",r.processesOK ? String(r.agents) : "—","Same-user supported roots")
   }
   HStack(alignment:.top,spacing:30) {
    VStack(alignment:.leading,spacing:8) { Text("Agent resident memory").font(.headline); Text(r.processesOK ? String(format:"%.1f GiB%@",r.resident,r.unreadable>0 ? " · partial" : "") : "Unavailable").font(.title2.bold()); Text("Includes detected process trees. Excludes compressed pages; not physical footprint.").font(.callout).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading)
    VStack(alignment:.leading,spacing:8) { Text("Know the limits").font(.headline); Text("Agent detection covers recognized native executables for your user. Unknown or script-hosted agents can be missed. The capacity estimate uses your budget, not resident memory.").font(.callout).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading)
   }.padding(22).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:18))
   Spacer(minLength:0)
   HStack { Toggle("Sample mode",isOn:$state.sample).toggleStyle(.switch).onChange(of:state.sample) { _,_ in state.refresh() }; if state.sample { Picker("Scenario",selection:$state.scenario) { Text("Balanced").tag(0); Text("Under pressure").tag(1); Text("Room to grow").tag(2) }.frame(width:240).onChange(of:state.scenario) { _,_ in state.refresh() } }; Spacer(); Button("Refresh") {state.refresh()}; Button("Privacy") { showPrivacy() }; Button("Quit") { NSApp.terminate(nil) } }
  }.padding(36).frame(minWidth:1060,minHeight:790).background(Color(red:0.045,green:0.075,blue:0.105)).foregroundStyle(.white).preferredColorScheme(.dark)
 }
 func showPrivacy() {
  let alert=NSAlert(); alert.messageText="Your data stays on this device"; alert.informativeText="Headroom reads system memory and same-user process metadata locally. It does not transmit, store, or log process names, paths, or arguments. No accounts, analytics, or tracking. Privacy policy: https://barframe.com/apps/headroom/privacy/"; alert.addButton(withTitle:"Done"); alert.addButton(withTitle:"Open policy")
  if alert.runModal() == .alertSecondButtonReturn, let raw=Bundle.main.object(forInfoDictionaryKey:"MASPrivacyPolicyURL") as? String, !raw.contains("{DOMAIN}"), let url=URL(string:raw) { NSWorkspace.shared.open(url) }
 }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
 var window:NSWindow!; var item:NSStatusItem!; let state=State(); var timer:Timer?
 func applicationDidFinishLaunching(_ notification:Notification) {
  let args=CommandLine.arguments
  if args.contains("--screenshots") { screenshots(); return }
  if args.contains("--smoke") { smoke(); return }
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:850),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
  window.title="Headroom Agent Memory"; window.contentView=NSHostingView(rootView:Dashboard(state:state)); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
  item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength); item.button?.title="HR"; item.button?.target=self; item.button?.action=#selector(show)
  if args.contains("--sample") {state.sample=true}; state.refresh()
  timer=Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in Task { @MainActor in self?.state.refresh() } }
 }
 @objc func show() {window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)}
 func screenshots() {
  do {
   let dir=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("screenshots"); try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
   for i in 0..<3 { state.sample=true;state.scenario=i;state.reading = .sample(i);state.budget=i==2 ? 4 : 2
    let host=NSHostingView(rootView:Dashboard(state:state).frame(width:1440,height:900))
    let shotWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:1440,height:900),styleMask:.borderless,backing:.buffered,defer:false)
    shotWindow.contentView=host; shotWindow.orderFront(nil)
    host.layoutSubtreeIfNeeded(); shotWindow.displayIfNeeded()
    RunLoop.main.run(until:Date().addingTimeInterval(0.25))
    guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2880,pixelsHigh:1800,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0) else {throw NSError(domain:"Screenshot",code:1)}
    rep.size=NSSize(width:1440,height:900); host.cacheDisplay(in:host.bounds,to:rep); shotWindow.orderOut(nil)
    guard let png=rep.representation(using:.png,properties:[:]) else {throw NSError(domain:"PNG",code:1)}
    try png.write(to:dir.appendingPathComponent("headroom-\(i+1).png"))
   }; finish()
  } catch { fputs("Screenshot error: \(error)\n",stderr); exit(1) }
 }
 func smoke() {
  let r=Reading.live(); let home=FileManager.default.homeDirectoryForCurrentUser.path
  let sandbox=home.contains("/Library/Containers/com.michaellip.headroom/")
  let checks:[[String:Any]]=[
   ["name":"memory","pass":r.memoryOK && r.total>0,"detail":"Live system memory probe"],
   ["name":"processes","pass":r.processesOK,"detail":"KERN_PROC_ALL scan completed"],
   ["name":"estimate","pass":Reading.sample(0).capacity(budget:2)==5 && Reading.sample(1).capacity(budget:2)==0,"detail":"Normal and swapping scenarios"],
   ["name":"sandbox","pass":sandbox,"detail":home]]
  do {let report:[String:Any] = ["pass":checks.allSatisfy{$0["pass"] as? Bool == true},"sandboxed":sandbox,"home":home,"checks":checks]; try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:URL(fileURLWithPath:home).appendingPathComponent("smoke.json"));finish()} catch {exit(1)}
 }
 func finish() { DispatchQueue.main.asyncAfter(deadline:.now()+0.7) { NSApp.terminate(nil) } }
}
let app=NSApplication.shared
let delegate=Delegate()
app.delegate=delegate
app.setActivationPolicy(.accessory)
app.run()
