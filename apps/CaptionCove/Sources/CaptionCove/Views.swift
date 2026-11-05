import SwiftUI
import AppKit
import CaptionCoveCore

struct ProductLinks:View {
    var spanish=false
    @State private var document:String?
    static func destination(_ raw:String?,expectedPath:String?=nil)->URL? {
        guard let raw, !raw.contains("{"), !raw.contains("}"), let url=URL(string:raw), url.scheme == "https", url.host != nil else { return nil }
        if let expectedPath, url.path != expectedPath { return nil }
        return url
    }
    func open(_ name:String) {
        let key=name == "privacy" ? "MASPrivacyPolicyURL" : "MASSupportURL"
        if let url=Self.destination(Bundle.main.object(forInfoDictionaryKey:key) as? String,expectedPath:name == "privacy" ? "/apps/captioncove/privacy/" : "/apps/captioncove/support/") { NSWorkspace.shared.open(url) }
        else { document=name }
    }
    var body:some View {
        HStack {
            Button(spanish ? "Privacidad" : "Privacy Policy") { open("privacy") }
            Button(spanish ? "Ayuda" : "Support") { open("support") }
        }.buttonStyle(.link).font(.caption)
        .sheet(isPresented:Binding(get:{document != nil},set:{ if !$0 { document=nil } })) {
            VStack(alignment:.leading,spacing:16) {
                Text(document == "privacy" ? (spanish ? "Privacidad" : "Privacy Policy") : (spanish ? "Ayuda" : "Support")).font(.title2.bold())
                ScrollView { Text(localText(document ?? "support")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                Button(spanish ? "Cerrar" : "Close") { document=nil }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width:560,height:520)
        }
    }
    static func localText(_ name:String)->String {
        guard let url=Bundle.module.url(forResource:name,withExtension:"md",subdirectory:"LocalDocuments"), let text=try? String(contentsOf:url,encoding:.utf8) else { return "CaptionCove processes files locally. Contact support@barframe.com for help." }
        return text
    }
    func localText(_ name:String)->String { Self.localText(name) }
}
struct StateBadge:View {
    @ObservedObject var model:AppModel
    var symbol:String { model.checking ? "arrow.triangle.2.circlepath" : model.state == .ready ? "checkmark.circle.fill" : model.state == .issues ? "exclamationmark.circle.fill" : "questionmark.circle" }
    var body:some View {
        Label(model.stateText,systemImage:symbol).foregroundStyle(model.state == .ready ? .green : model.state == .issues ? .orange : .secondary)
            .accessibilityLabel(model.tooltip)
    }
}
struct SummaryView:View {
    @ObservedObject var model:AppModel
    var openDetails:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("CaptionCove").font(.headline); Spacer(); if model.sampleMode { Text("Sample").font(.caption.bold()).foregroundStyle(.teal) } }
            StateBadge(model:model)
            Text(model.summaryText).font(.callout).lineLimit(3)
            if let result=model.result { Text(model.l("Local warnings ","Avisos locales ")+String(result.warningCount)).font(.caption).foregroundStyle(.secondary) }
            Text(model.lastCheck).font(.caption).foregroundStyle(.secondary)
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(model.error ? .orange : .secondary).lineLimit(3) }
            HStack {
                Button(model.l("Review matrix","Revisar matriz"),action:openDetails).keyboardShortcut("o")
                Button(model.l("Rescan","Comprobar")) { model.scan() }.disabled(model.checking)
            }
            Button(model.sampleMode ? model.l("Use Live files","Usar archivos reales") : model.l("See Sample","Ver Sample")) { model.toggleSample(!model.sampleMode) }
            Divider()
            HStack { SettingsLink { Text(model.l("Settings","Ajustes")) }; ProductLinks(spanish:model.language == "es"); Spacer(); Button(model.l("Quit","Salir")) { NSApp.terminate(nil) } }
        }.padding(18).frame(width:380).preferredColorScheme(model.scheme)
    }
}
struct ContentView:View {
    @ObservedObject var model:AppModel
    @State private var newLabel=""
    var body:some View {
        GeometryReader { geometry in
        ScrollView(.vertical) {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:5) {
                    HStack { Text("CaptionCove").font(.largeTitle.bold()); if model.sampleMode { Text("Sample").font(.callout.bold()).padding(.horizontal,10).padding(.vertical,4).background(.teal.opacity(0.15),in:Capsule()).foregroundStyle(.teal) } }
                    Text(model.l("Subtitle delivery parity","Comparación de entregas de subtítulos")).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment:.trailing,spacing:6) { StateBadge(model:model); Text(model.lastCheck).font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing:12) {
                Button(model.sampleMode ? model.l("Use Live files","Usar archivos reales") : model.l("See Sample","Ver Sample")) { model.toggleSample(!model.sampleMode) }
                Button(model.l("Rescan","Comprobar")) { model.scan() }.keyboardShortcut("r").disabled(model.checking)
                if model.checking { ProgressView().controlSize(.small); Button(model.l("Cancel","Cancelar")) { model.cancelScan() } }
                Spacer()
                SettingsLink { Text(model.l("Settings","Ajustes")) }.keyboardShortcut(",")
            }
            if !model.sampleMode {
                HStack {
                    Button(model.project.reference == nil ? model.l("Choose reference","Seleccionar referencia") : model.l("Replace reference","Cambiar referencia")) { model.choose(reference:true) }
                    Text(model.project.reference?.filename ?? model.l("No reference selected","Sin referencia")).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    TextField(model.l("Language label","Etiqueta del idioma"),text:$newLabel).frame(width:155)
                    Button(model.l("Add SRT","Añadir SRT")) { model.choose(reference:false,label:newLabel) }
                }
                if !model.project.languages.isEmpty {
                    ScrollView(.horizontal) {
                        HStack { ForEach(model.project.languages) { input in
                            HStack { Text(input.label).font(.caption); Button(model.l("Choose again","Elegir otra vez")) { model.replace(input) }; Button { model.remove(input) } label: { Image(systemName:"xmark") }.accessibilityLabel(model.l("Remove ","Quitar ")+input.label) }.padding(7).background(.quaternary,in:RoundedRectangle(cornerRadius:7))
                        } }
                    }.frame(maxHeight:40)
                }
            }
            if model.result == nil {
                VStack(alignment:.leading,spacing:15) {
                    Label(model.l("See Sample","Ver Sample"),systemImage:"1.circle").font(.headline)
                    Text(model.l("Explore missing cues and shifted timing with local example files","Explora subtítulos ausentes y tiempos desplazados con ejemplos locales")).foregroundStyle(.secondary)
                    Label(model.l("Choose inputs","Seleccionar archivos"),systemImage:"2.circle").font(.headline)
                    Text(model.l("Select a reference SRT and label each language. File access is granted only when you choose files","Selecciona un SRT de referencia y etiqueta cada idioma. Solo se concede acceso cuando eliges archivos")).foregroundStyle(.secondary)
                    Label(model.l("Review result","Revisar resultado"),systemImage:"3.circle").font(.headline)
                    Text(model.l("Use the matrix to find missing IDs, timing drift and local text warnings","Usa la matriz para localizar IDs ausentes, desfases y avisos de texto")).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
            } else if let result=model.result {
                if result.stale { Label(model.l("Previous results are stale. Rescan before making a parity claim","Resultados anteriores desactualizados. Comprueba antes de afirmar que coinciden"),systemImage:"clock.badge.exclamationmark").font(.callout).foregroundStyle(.orange) }
                matrix(result,maxHeight:Self.availableMatrixHeight(windowHeight:geometry.size.height,sample:model.sampleMode))
                HStack {
                    Text(model.l("Cue details","Detalles de subtítulos")).font(.headline)
                    Spacer()
                    Picker(model.l("Language","Idioma"),selection:$model.selected) { ForEach(result.rows) { Text(model.label($0.label)).tag($0.label) } }.frame(width:245)
                }
                details(result)
                HStack {
                    Button(model.l("Copy report without dialogue","Copiar informe sin diálogo")) { model.copy() }.disabled(!model.canCopy)
                    Menu(model.l("Include dialogue","Incluir diálogo")) { Button(model.l("Copy report with dialogue text","Copiar informe con diálogo")) { model.copy(includeText:true) } }.disabled(!model.canCopy || model.previews.isEmpty)
                    Spacer()
                    Text(model.l("Tolerance ","Tolerancia ")+"\(result.rules.toleranceMS) ms").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(model.error ? .orange : .secondary).textSelection(.enabled) }
            Spacer(minLength:0)
            Divider()
            HStack {
                Text(model.l("Local processing\nSource files stay unchanged","Proceso local\nLos archivos originales no se modifican")).font(.caption).foregroundStyle(.secondary)
                Spacer(); ProductLinks(spanish:model.language == "es")
                Button(model.l("Quit","Salir")) { NSApp.terminate(nil) }.font(.caption)
            }
        }.frame(minHeight:geometry.size.height-48,alignment:.top).padding(24)
        }
        }.frame(minWidth:900,minHeight:620).preferredColorScheme(model.scheme)
    }
    static func availableMatrixHeight(windowHeight:CGFloat,sample:Bool)->CGFloat { max(80,min(190,windowHeight-(sample ? 490 : 540))) }
    static func matrixHeight(rowCount:Int)->CGFloat { min(190,CGFloat(rowCount+1)*30+12) }
    @ViewBuilder private func matrix(_ result:ScanResult,maxHeight:CGFloat)->some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text(model.l("Delivery matrix","Matriz de entregas")).font(.headline); Spacer(); Text(model.l("Local warnings ","Avisos locales ")+String(result.warningCount)).font(.caption).foregroundStyle(.secondary) }
            ScrollView(.vertical) {
            Grid(alignment:.leading,horizontalSpacing:10,verticalSpacing:10) {
                GridRow {
                    Text(model.l("Language","Idioma")).frame(width:150,alignment:.leading)
                    ForEach(IssueKind.allCases,id:\.self) { kind in Text(model.kind(kind)).font(.caption.bold()).frame(maxWidth:.infinity) }
                    Text(model.l("Status","Estado")).font(.caption.bold()).frame(width:80)
                }
                Divider().gridCellColumns(9)
                ForEach(result.rows) { row in
                    GridRow {
                        Button(model.label(row.label)) { model.selected=row.label }.buttonStyle(.plain).font(.callout.weight(model.selected == row.label ? .bold : .regular)).frame(width:150,alignment:.leading)
                        ForEach(IssueKind.allCases,id:\.self) { kind in
                            Button { model.selected=row.label } label: { Text("\(row.count(kind))").font(.system(.body,design:.monospaced)).foregroundStyle(row.count(kind)>0 ? (kind.parityFailure ? Color.orange : Color.teal) : Color.secondary).frame(maxWidth:.infinity) }.buttonStyle(.plain).accessibilityLabel("\(model.label(row.label)) \(model.kind(kind)) \(row.count(kind))")
                        }
                        Text(row.complete ? (!row.findings.contains(where:{$0.kind.parityFailure}) ? model.l("Ready","Listo") : model.l("Issues","Problemas")) : model.l("Incomplete","Incompleto")).font(.caption).frame(width:80)
                    }
                }
            }
            }.frame(minHeight:80,maxHeight:min(maxHeight,Self.matrixHeight(rowCount:result.rows.count)))
        }.padding(14).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
    }
    @ViewBuilder private func details(_ result:ScanResult)->some View {
        let row=result.rows.first{$0.label == model.selected}
        ScrollView {
            LazyVStack(alignment:.leading,spacing:10) {
                if let row, row.findings.isEmpty { Label(model.l("No findings with the current rules","Sin avisos con las reglas actuales"),systemImage:"checkmark.circle").foregroundStyle(.green).padding(12) }
                ForEach(row?.findings ?? []) { finding in
                    VStack(alignment:.leading,spacing:5) {
                        HStack { Text(model.kind(finding.kind)).font(.caption.bold()).foregroundStyle(finding.kind.parityFailure ? .orange : .teal); Text(finding.cueID.map{model.l("Cue ","Subtítulo ")+String($0)} ?? model.l("File issue","Problema de archivo")).font(.callout.bold()); Spacer(); if let start=finding.start,let end=finding.end { Text("\(formatTime(start)) → \(formatTime(end))").font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary) } }
                        Text(model.reason(finding.reason)).font(.callout).textSelection(.enabled)
                        if let id=finding.cueID,let cue=model.previews[row?.label ?? ""]?.cues.first(where:{$0.id == id}),!cue.text.isEmpty {
                            Text(String(cue.visibleText.prefix(120))).font(.caption).foregroundStyle(.secondary).lineLimit(2).accessibilityLabel(model.l("Local text preview ","Vista previa local ")+String(cue.visibleText.prefix(120)))
                        }
                    }.padding(12).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:8))
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.frame(minHeight:110,maxHeight:.infinity)
    }
}
struct SettingsView:View {
    @ObservedObject var model:AppModel
    @State var advanced=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:17) {
                HStack { Text(model.l("CaptionCove settings","Ajustes de CaptionCove")).font(.title2.bold()); Spacer(); if model.sampleMode { Text("Sample").foregroundStyle(.teal) } }
                Toggle(model.l("Sample mode","Modo Sample"),isOn:Binding(get:{model.sampleMode},set:{model.toggleSample($0)}))
                if model.sampleMode { Button(model.l("Reset Sample fixtures","Restablecer ejemplos Sample")) { model.resetSample() } }
                Text(model.l("Live project uses your selected reference and labeled SRT files. Choose inputs in the review window","El proyecto real usa la referencia y los SRT etiquetados que seleccionaste. Elige archivos en la ventana de revisión")).font(.caption).foregroundStyle(.secondary)
                Picker(model.l("Language","Idioma"),selection:$model.language) { Text("English").tag("en"); Text("Español").tag("es") }
                Picker(model.l("Appearance","Apariencia"),selection:$model.appearance) { Text(model.l("System","Sistema")).tag("system"); Text(model.l("Light","Clara")).tag("light"); Text(model.l("Dark","Oscura")).tag("dark") }
                HStack {
                    Text(model.l("Open panel shortcut","Atajo para abrir panel"))
                    Picker(model.l("Modifiers","Modificadores"),selection:$model.hotkeyModifiers) { Text("⌘ ⌥").tag("commandOption"); Text("⌃ ⌥").tag("controlOption"); Text("⌘ ⇧").tag("commandShift"); Text(model.l("Off","Desactivado")).tag("off") }.frame(width:130)
                    Picker(model.l("Key","Tecla"),selection:$model.hotkeyKey) { ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init),id:\.self) { Text($0).tag($0) } }.frame(width:80)
                }
                if !model.hotkeyError.isEmpty { Text(model.hotkeyError).font(.caption).foregroundStyle(.orange) }
                DisclosureGroup(model.l("Advanced rules","Reglas avanzadas"),isExpanded:$advanced) {
                    VStack(alignment:.leading,spacing:12) {
                        Stepper(model.l("Timing tolerance ","Tolerancia de tiempos ")+"\(model.rules.toleranceMS) ms",value:Binding(get:{model.rules.toleranceMS},set:{model.updateRules(Rules(toleranceMS:$0,maxCPS:model.rules.maxCPS,warnOverlap:model.rules.warnOverlap))}),in:0...5000,step:25)
                        Stepper(model.l("Text warning above ","Aviso de texto por encima de ")+String(format:"%.0f",model.rules.maxCPS)+model.l(" characters per second"," caracteres por segundo"),value:Binding(get:{model.rules.maxCPS},set:{model.updateRules(Rules(toleranceMS:model.rules.toleranceMS,maxCPS:$0,warnOverlap:model.rules.warnOverlap))}),in:1...100,step:1)
                        Toggle(model.l("Warn about overlaps","Avisar sobre solapamientos"),isOn:Binding(get:{model.rules.warnOverlap},set:{model.updateRules(Rules(toleranceMS:model.rules.toleranceMS,maxCPS:model.rules.maxCPS,warnOverlap:$0))}))
                        Text(model.l("Counts use visible grapheme clusters including spaces but excluding line breaks. Simple b i u and font tags are removed. Thresholds are your delivery rules and are not universal accessibility standards. Overlap warnings do not change files","Se cuentan grafemas visibles y espacios sin saltos de línea. Se eliminan etiquetas simples b i u y font. Los umbrales son tus reglas de entrega y no estándares universales de accesibilidad. Los avisos de solapamiento no modifican archivos")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.top,10)
                }
                Divider()
                HStack { Button(model.l("Forget Live project","Olvidar proyecto real")) { model.forget() }; Button(model.l("Delete all local data","Eliminar datos locales")) { model.clearAll() } }
                Text(model.l("Removes saved references and summaries. Your source files stay unchanged","Elimina referencias y resúmenes guardados. Los archivos originales no se modifican")).font(.caption).foregroundStyle(.secondary)
                if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(model.error ? .orange : .secondary) }
                ProductLinks(spanish:model.language == "es")
                Text("Version 1.0.0").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(width:600,height:650).preferredColorScheme(model.scheme)
    }
}
