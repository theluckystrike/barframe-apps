import SwiftUI
import PDFKit
import Carbon
import MASKit
import PageParcelCore
struct Links: View {
 @ObservedObject var model:Model
 @State var localTitle = ""
 @State var localText = ""
 @State var showing = false
 func open(_ key:String,_ title:String,_ resource:String) {
 let requiredPath = key == "MASPrivacyPolicyURL" ? "/apps/pageparcel/privacy/" : "/apps/pageparcel/support/"
 if let url = ProductLink.resolved(Bundle.main.object(forInfoDictionaryKey:key) as? String,path:requiredPath) { NSWorkspace.shared.open(url) }
 else {
 localTitle = title
 localText = Bundle.module.url(forResource:resource,withExtension:"txt").flatMap { try? String(contentsOf:$0) } ?? model.t("PageParcel keeps PDF processing and saved packets on your Mac. Choose PDFs, review source pages and planned blanks, and copy the assembly sheet. Clear local data removes both packets and saved bookmarks without deleting source PDFs.","PageParcel procesa PDF y guarda paquetes en tu Mac. Elige PDF, revisa las páginas y los blancos, y copia la hoja de montaje. Borrar datos locales elimina ambos paquetes y sus accesos sin borrar los PDF.")
 showing = true
 }
 }
 var body:some View {
 HStack {
 Button(model.t("Support","Ayuda")) { open("MASSupportURL",model.t("Support","Ayuda"),"LocalSupport") }
 Button(model.t("Privacy Policy","Política de privacidad")) { open("MASPrivacyPolicyURL",model.t("Privacy Policy","Política de privacidad"),"LocalPrivacy") }
 }.sheet(isPresented:$showing) { VStack(alignment:.leading,spacing:15) { Text(localTitle).font(.title2); ScrollView { Text(localText).textSelection(.enabled) }; Button(model.t("Done","Listo")) { showing = false } }.padding(24).frame(width:520,height:400) }
 }
}
struct ContentView: View {
 @Environment(\.openWindow) private var openWindow
 @ObservedObject var model: Model
 @State private var acknowledge: UUID?
 @State private var expectedInput = ""
 @State private var confirmExpected = false
 var body: some View {
 VStack(alignment: .leading,spacing: 14) {
 HStack { Image(systemName:"doc.on.doc").font(.largeTitle).foregroundStyle(.teal); VStack(alignment: .leading) { Text("PageParcel").font(.title.bold()); Text(model.t("Plan duplex document packets","Planifica paquetes de documentos dúplex")).foregroundStyle(.secondary) }; Spacer(); Text(model.sample ? "Sample · \(model.displayState)" : model.displayState).font(.headline).padding(9).background(.teal.opacity(0.12),in: Capsule()) }
 Text(model.t("1 See Sample    2 Choose PDFs    3 Review the assembly sheet","1 Ver ejemplo    2 Elegir PDF    3 Revisar el montaje")).font(.caption).foregroundStyle(.secondary)
 HStack { Button(model.t("Choose PDFs","Elegir PDF")) { model.choose() }; Button(model.t("Rescan","Volver a analizar")) { model.rescan() }.disabled(model.documents.isEmpty || model.busy); if model.busy { ProgressView(value:Double(model.progress),total:Double(max(model.documents.count,1))).frame(width:80); Button(model.t("Cancel check","Cancelar análisis")) { model.cancelScan() } }; Button(model.t("Copy assembly sheet","Copiar hoja de montaje")) { model.copy() }.disabled(model.documents.isEmpty); Spacer(); Toggle("Sample",isOn: Binding(get:{model.sample},set:{model.toggleSample($0)})).toggleStyle(.switch); SettingsLink { Image(systemName:"gearshape") }.accessibilityLabel(model.t("Settings","Ajustes")) }
 Text(model.t("Duplex assumption · Odd packet pages are fronts and even pages are backs","Supuesto dúplex · Las páginas impares son anversos y las pares reversos")).font(.callout)
 if model.documents.isEmpty {
 ContentUnavailableView(model.t("Build your first packet","Crea tu primer paquete"),systemImage:"doc.badge.plus",description:Text(model.t("Choose PDFs or turn on Sample. File access is requested only when you choose files.","Elige PDF o activa Sample. El acceso se solicita al elegir archivos."))).frame(height:380)
 } else {
 HSplitView {
 VStack(alignment:.leading,spacing:10) {
 Text(model.t("Document order","Orden de documentos")).font(.headline)
 ScrollView {
 ForEach($model.documents) { $doc in
 VStack(alignment:.leading,spacing:5) {
 HStack { TextField(model.t("Label","Etiqueta"),text:$doc.label).font(.headline).onChange(of:doc.label) { model.save() }; Button { model.move(doc.id,-1) } label: { Image(systemName:"arrow.up") }.accessibilityLabel(model.t("Move document up","Subir documento")); Button { model.move(doc.id,1) } label: { Image(systemName:"arrow.down") }.accessibilityLabel(model.t("Move document down","Bajar documento")) }
 Text(doc.filename).font(.caption).foregroundStyle(.secondary).lineLimit(1)
 HStack { Text("\(doc.count.map(String.init) ?? "?") \(model.t("pages","páginas"))"); Spacer(); Toggle(model.t("Start on front","Inicio en anverso"),isOn:$doc.front).onChange(of:doc.front) { model.review.observe(model.plan); model.save() } }.font(.caption)
 HStack { Text(model.t("Expected","Esperadas")); Text(doc.expected.map(String.init) ?? model.t("Unset","Sin definir")).monospacedDigit(); Button(model.t("Set expected count","Definir recuento")) { expectedInput = (doc.count ?? doc.expected).map(String.init) ?? ""; acknowledge = doc.id } }.font(.caption)
 if let range = model.plan.ranges[doc.id] { Text("\(model.t("Packet","Paquete")) \(range.lowerBound) \(model.t("to","a")) \(range.upperBound)").font(.caption).foregroundStyle(.teal) }
 if let issue = doc.issue { Text(model.translatedIssue(issue)).font(.caption).foregroundStyle(.orange); Button(model.t("Choose again","Elegir de nuevo")) { model.choose(replacing:doc.id) } }
 if doc.changed { Text(model.t("Count differs from expectation","El recuento difiere del esperado")).font(.caption).foregroundStyle(.orange) }
 Button(model.t("Remove","Quitar")) { model.remove(doc.id) }.font(.caption)
 }.padding(10).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:9))
 }
 }.disabled(model.busy).frame(maxHeight:.infinity)
 }.frame(minWidth:270,idealWidth:285)
 VStack(alignment:.leading) {
 Text(model.t("Virtual assembly","Montaje virtual")).font(.headline)
 Text(model.t("\(model.plan.pages.count) pages · \(model.plan.blanks) planned blanks","\(model.plan.pages.count) páginas · \(model.plan.blanks) blancos previstos")).font(.caption).foregroundStyle(.secondary)
 List(model.plan.pages,selection:$model.selected) { page in
 HStack { Text("\(page.position)").monospacedDigit().frame(width:25); VStack(alignment:.leading) { Text(page.document.flatMap { id in model.documents.first { $0.id == id }?.label } ?? model.t("Planned blank","Página en blanco prevista")); Text("\(model.t("Sheet","Hoja")) \(page.sheet) · \(model.t(page.side,page.side == "Front" ? "Anverso" : "Reverso"))" + (page.local.map { " · \(model.t("Source","Original")) \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary) } }.tag(page.position)
 }.listStyle(.inset)
 }.frame(minWidth:230,idealWidth:245)
 VStack {
 if let page = model.plan.pages.first(where:{$0.position == model.selected}) {
 if let id = page.document, let pdf = model.pdfs[id], let local = page.local { Group { PDFPreview(document:pdf,page:local-1) } }
 else if page.isBlank { VStack(spacing:16) { Image(systemName:"doc").font(.system(size:52)); Text(model.t("Planned blank back","Reverso en blanco previsto")).font(.headline); Text(model.t("A virtual page in your plan","Una página virtual en tu plan")) }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.quaternary.opacity(0.3)) }
 else { VStack(spacing:12) { if model.busy { ProgressView() }; Text(model.t("Source preview unavailable","Vista previa original no disponible")); Text(model.t("Rescan or choose the source again","Analiza o elige el original de nuevo")).font(.caption) }.frame(maxWidth:.infinity,maxHeight:.infinity) }
 } else { Text(model.t("Select a packet page","Selecciona una página")).frame(maxWidth:.infinity,maxHeight:.infinity) }
 }.frame(minWidth:220,idealWidth:260)
 }.frame(height:390)
 }
 if !model.changes.isEmpty { DisclosureGroup(model.t("Downstream positions changed","Posiciones posteriores modificadas")) { ForEach(model.changes,id:\.self) { Text($0).font(.caption) }; Button(model.t("Acknowledge position changes","Confirmar cambios de posición")) { model.acknowledgeChanges() }.disabled(!model.plan.complete) } }
 if !model.message.isEmpty { Text(model.translatedIssue(model.message)).font(.caption).foregroundStyle(.orange) }
 Text(model.t("Virtual blanks are a plan only. PDFs are unchanged and nothing is sent to a printer.","Los blancos son solo un plan. Los PDF no cambian y no se envía nada a la impresora.")).font(.caption).foregroundStyle(.secondary)
 HStack { Links(model:model); Spacer(); if let date = model.lastCheck { Text(date,style:.time).font(.caption) }; Button(model.t("Quit","Salir")) { NSApp.terminate(nil) } }
 }.padding(22).frame(minWidth:890,minHeight:630)
 .sheet(isPresented:Binding(get:{acknowledge != nil},set:{if !$0 { acknowledge = nil }})) {
 VStack(alignment:.leading,spacing:16) {
 Text(model.t("Set expected page count","Definir páginas esperadas")).font(.headline)
 TextField(model.t("Positive page count","Número de páginas positivo"),text:$expectedInput)
 Text(model.t("Changing the expectation requires confirmation. Review downstream positions too.","Cambiar el recuento requiere confirmación. Revisa también las posiciones posteriores.")).font(.caption)
 HStack { Button(model.t("Cancel","Cancelar")) { acknowledge = nil }; Button(model.t("Review replacement","Revisar cambio")) { confirmExpected = true }.disabled(Int(expectedInput).map { !ExpectedCount.valid($0) } ?? true) }
 }.padding(24).frame(width:420)
 .alert(model.t("Replace expected page count?","¿Cambiar las páginas esperadas?"),isPresented:$confirmExpected) {
 Button(model.t("Cancel","Cancelar"),role:.cancel) {}
 Button(model.t("Confirm replacement","Confirmar cambio")) { if let id = acknowledge, let value = Int(expectedInput) { model.acceptExpected(id,value) }; acknowledge = nil }
 } message: { Text(model.t("This acknowledges the selected expectation. Pending position findings stay until acknowledged separately.","Esto confirma el recuento elegido. Los cambios de posición se conservan hasta confirmarlos por separado.")) }
 }
 .onAppear { Delegate.reopen = { openWindow(id:"packet") } }
 .preferredColorScheme(model.appearance == "Dark" ? .dark : model.appearance == "Light" ? .light : nil)
 }
}
struct PDFPreview:NSViewRepresentable {
 let document:PDFDocument; let page:Int
 func makeNSView(context:Context)->SourcePageView { SourcePageView() }
 func updateNSView(_ view:SourcePageView,context:Context) { view.page = document.page(at:page); view.needsDisplay = true }
}
final class SourcePageView:NSView {
 var page:PDFPage?
 override func draw(_ dirtyRect:NSRect) {
 NSColor.windowBackgroundColor.setFill(); bounds.fill()
 guard let page, let context = NSGraphicsContext.current?.cgContext else { return }
 let source = page.bounds(for:.mediaBox), available = bounds.insetBy(dx:8,dy:8)
 let scale = min(available.width/source.width,available.height/source.height)
 context.saveGState()
 context.translateBy(x:bounds.midX-source.width*scale/2,y:bounds.midY-source.height*scale/2)
 context.scaleBy(x:scale,y:scale); context.translateBy(x:-source.minX,y:-source.minY)
 context.setFillColor(NSColor.white.cgColor); context.fill(source)
 page.draw(with:.mediaBox,to:context)
 context.restoreGState()
 }
}
struct SettingsView: View {
 @ObservedObject var model: Model
 var body: some View {
 Form {
 Text(model.t("PageParcel settings","Ajustes de PageParcel")).font(.title2.bold())
 Toggle(model.t("Sample mode","Modo de ejemplo"),isOn:Binding(get:{model.sample},set:{model.toggleSample($0)}))
 Button(model.t("Reset Sample","Restablecer ejemplo")) { if !model.sample { model.toggleSample(true) }; model.resetSample() }
 Toggle(model.t("Default front side starts","Iniciar en anverso por defecto"),isOn:$model.defaultFront)
 Picker(model.t("Appearance","Apariencia"),selection:$model.appearance) { ForEach(["System","Light","Dark"],id:\.self) { Text(model.t($0,["System":"Sistema","Light":"Claro","Dark":"Oscuro"][$0] ?? $0)) } }
 Toggle("Español",isOn:$model.spanish)
 DisclosureGroup(model.t("Advanced","Avanzado")) {
 Text(model.t("Open panel shortcut","Atajo para abrir el panel"))
 ShortcutRecorder(model:model).frame(height:26)
 Text(model.t("Click the shortcut then press any key with modifiers. Reserved system shortcuts are rejected. Other app shortcuts cannot all be detected.","Pulsa el atajo e introduce una tecla con modificadores. Los atajos reservados se rechazan. No se pueden detectar todos los atajos de otras apps.")).font(.caption)
 Text(model.translatedIssue(model.shortcutMessage)).foregroundStyle(.orange)
 Text(model.t("Set labels and expected counts beside each document. Replacing any expectation requires confirmation.","Define etiquetas y recuentos esperados junto a cada documento. Cambiar un recuento requiere confirmación.")).font(.caption)
 Button(model.t("Clear all local data","Borrar todos los datos locales")) { model.clear() }
 }
 Links(model:model)
 }.padding(24).frame(width:490)
 }
}

struct ShortcutRecorder:NSViewRepresentable {
 @ObservedObject var model:Model
 func makeNSView(context:Context)->RecorderField { let field = RecorderField(); field.isEditable = false; field.isSelectable = false; field.isBezeled = true; field.model = model; return field }
 func updateNSView(_ view:RecorderField,context:Context) { view.stringValue = model.shortcutName; view.setAccessibilityLabel(model.t("Record open panel shortcut","Grabar atajo para abrir el panel")) }
}
final class RecorderField:NSTextField {
 weak var model:Model?
 override var acceptsFirstResponder:Bool { true }
 override func mouseDown(with event:NSEvent) { window?.makeFirstResponder(self); stringValue = model?.t("Press shortcut","Pulsa el atajo") ?? "" }
 override func keyDown(with event:NSEvent) { record(event) }
 override func performKeyEquivalent(with event:NSEvent)->Bool { guard window?.firstResponder === self else { return false }; record(event); return true }
 func record(_ event:NSEvent) {
 var mods:UInt32 = 0; var name = ""
 for (flag,carbon,symbol) in [(NSEvent.ModifierFlags.control,UInt32(controlKey),"⌃"),(.option,UInt32(optionKey),"⌥"),(.shift,UInt32(shiftKey),"⇧"),(.command,UInt32(cmdKey),"⌘")] { if event.modifierFlags.contains(flag) { mods |= carbon; name += symbol } }
 name += event.charactersIgnoringModifiers?.uppercased() ?? "\(event.keyCode)"
 model?.setShortcut(key:UInt32(event.keyCode),modifiers:mods,name:name); stringValue = model?.shortcutName ?? ""
 }
}
