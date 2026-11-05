import SwiftUI
import Carbon
import MASKit
import PageParcelCore
@main struct PageParcelApp: App {
 @NSApplicationDelegateAdaptor(Delegate.self) var delegate
 @StateObject var model: Model
 init() {
 if CommandLine.arguments.contains("--smoke") { exit(Smoke.run()) }
 if CommandLine.arguments.contains("--screenshots") { do { try ScreenshotRenderer.render(to:URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("screenshots")); exit(0) } catch { exit(1) } }
 _model = StateObject(wrappedValue:Model())
 }
 var body: some Scene {
 WindowGroup("PageParcel", id: "packet") { ContentView(model:model).onAppear { delegate.model = model } }
 Settings { SettingsView(model:model) }
 MenuBarExtra { SummaryView(model:model) } label: { StatusIcon(model:model) }.menuBarExtraStyle(.window)
 }
}
@MainActor final class Delegate:NSObject,NSApplicationDelegate {
 var model:Model?
 static var reopen: (() -> Void)?
 func applicationDidFinishLaunching(_ notification:Notification) {
 NSApp.setActivationPolicy(.accessory)
 InstallEventHandler(GetApplicationEventTarget(), { _,_,_ in DispatchQueue.main.async { Delegate.show() }; return noErr },1,[EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))],nil,nil)
 }
 func applicationWillTerminate(_ notification:Notification) { model?.flushSave(); model?.release() }
 func applicationDidBecomeActive(_ notification:Notification) { model?.checkStale() }
 static func show() { NSApp.activate(ignoringOtherApps:true); reopen?() }
}
enum Smoke {
 @MainActor static func run() -> Int32 {
 let model = Model(); model.sample = true; model.resetSample()
 var checks = [SmokeCheck(name:"Sample parity",pass:model.plan.blanks == 1 && model.plan.pages.count == 6,detail:"Introduction three pages then blank then appendix"),SmokeCheck(name:"PDFKit fixture",pass:model.pdfs.values.map(\.pageCount).sorted() == [2,3],detail:"Real PDFKit page objects")]
 do { let url = model.root.appendingPathComponent("smoke-packet.json"); try PacketStore.encode(model.documents).write(to:url); let restored = try PacketStore.decode(Data(contentsOf:url)); checks.append(SmokeCheck(name:"Container persistence reopen",pass:restored == model.documents,detail:"Saved packet decoded from container")); try FileManager.default.removeItem(at:url)
 let pdfURL = model.root.appendingPathComponent("smoke-input.pdf"); let pdf = model.pdfs.values.first!; let written = pdf.write(to:pdfURL); checks.append(SmokeCheck(name:"PDF live parser",pass:written && PDFKitRead.count(pdfURL) == pdf.pageCount,detail:"PDF file opened from sandbox container")); try? FileManager.default.removeItem(at:pdfURL)
 } catch { checks.append(SmokeCheck(name:"Persistence",pass:false,detail:error.localizedDescription)) }
 let report = SmokeReport(app:"PageParcel",bundleID:"com.michaellip.pageparcel",version:"1.0.0",checks:checks)
 do { _ = try report.write() } catch { return 1 }; return report.pass ? 0 : 1
 }
}
import PDFKit
enum PDFKitRead { static func count(_ url:URL)->Int? { PDFDocument(url:url)?.pageCount } }

struct SummaryView:View {
 @ObservedObject var model:Model
 var body:some View {
 VStack(alignment:.leading,spacing:10) {
 Text(model.sample ? "Sample · \(model.displayState)" : model.displayState).font(.headline)
 Text(model.t("\(model.plan.pages.count) virtual pages · \(model.plan.blanks) blanks","\(model.plan.pages.count) páginas virtuales · \(model.plan.blanks) blancos"))
 if model.busy { ProgressView(value:Double(model.progress),total:Double(max(model.documents.count,1))) }
 Text(model.mostImportant).font(.caption).foregroundStyle(.secondary)
 if let date = model.lastCheck { Text(date,style:.time) }
 Button(model.t("Open assembly sheet","Abrir hoja de montaje")) { Delegate.show() }
 Button(model.t("Choose PDFs","Elegir PDF")) { model.choose() }
 SettingsLink { Text(model.t("Settings","Ajustes")) }
 Links(model:model)
 Button(model.t("Quit","Salir")) { NSApp.terminate(nil) }
 }.padding().frame(width:300).background(PanelOpenObserver(model:model)).onAppear { model.checkStale() }
 }
}
struct StatusIcon:View {
 @ObservedObject var model:Model
 var body:some View {
 ZStack(alignment:.bottomTrailing) {
 Image(systemName:"doc.on.doc").font(.system(size:15)).frame(width:24,height:20,alignment:.leading)
 if model.busy { ProgressView().controlSize(.mini).frame(width:9,height:9) }
 else if !model.documents.isEmpty {
 Text(model.state == "Ready" ? "✓" : model.state == "Changed" ? "!" : "?").font(.system(size:8,weight:.bold)).frame(width:9,height:9).background(.background,in:Circle())
 }
 if model.sample { Text("S").font(.system(size:7,weight:.bold)).frame(width:9,height:9).background(.background,in:Circle()).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing) }
 }.frame(width:24,height:20)
 .accessibilityLabel("PageParcel " + (model.sample ? "Sample · " : "") + model.displayState + " · " + model.mostImportant)
 .help("PageParcel " + model.displayState + " · " + (model.lastCheck?.formatted() ?? model.t("No completed check","Sin análisis completado")))
 }
}

struct PanelOpenObserver:NSViewRepresentable {
 let model:Model
 func makeNSView(context:Context)->PanelVisibilityView { let view = PanelVisibilityView(); view.model = model; return view }
 func updateNSView(_ view:PanelVisibilityView,context:Context) { view.model = model }
}
final class PanelVisibilityView:NSView {
 weak var model:Model?
 var tokens:[NSObjectProtocol] = []
 override func viewDidMoveToWindow() {
 for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens = []
 guard let window else { return }
 for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
 tokens.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main) { [weak model,weak window] _ in
 Task { @MainActor in if window?.isVisible == true { model?.checkStale() } }
 })
 }
 }
 deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
