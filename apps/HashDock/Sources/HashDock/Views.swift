import SwiftUI
import AppKit
import HashDockCore

func L(_ english: String, _ spanish: String) -> String { Locale.preferredLanguages.first?.hasPrefix("es") == true ? spanish : english }
struct Links: View {
    @State private var localPage: String?
    func open(_ key: String) {
        let path=key == "MASPrivacyPolicyURL" ? "/apps/hashdock/privacy/" : "/apps/hashdock/support/"
        if let url=PolicyLink.webURL(Bundle.main.object(forInfoDictionaryKey:key) as? String,path:path) { NSWorkspace.shared.open(url) }
        else { localPage=key }
    }
    var body: some View {
        HStack {
            Button(L("Privacy Policy","Política de privacidad")) { open("MASPrivacyPolicyURL") }
            Button(L("Support","Ayuda")) { open("MASSupportURL") }
        }.font(.caption).sheet(isPresented:Binding(get:{localPage != nil},set:{if !$0 { localPage=nil }})) {
            VStack(alignment:.leading,spacing:18) {
                Text(localPage == "MASPrivacyPolicyURL" ? L("Privacy Policy","Política de privacidad") : L("Support","Ayuda")).font(.title2)
                Text(localPage == "MASPrivacyPolicyURL" ? L("HashDock processes folders on your Mac. Paths, bookmarks, hashes and results stay in the local app container. No accounts, analytics or automatic network requests. Input files are read only. Forget job deletes saved local state and permissions. Copy receipt places the chosen summary on your clipboard.","HashDock procesa carpetas en tu Mac. Rutas, permisos, hashes y resultados se guardan localmente. Sin cuentas, análisis ni solicitudes automáticas de red. Los archivos solo se leen. Olvidar entrega borra datos y permisos guardados. Copiar recibo coloca el resumen elegido en el portapapeles.") : L("Try Sample from the delivery matrix or Settings. For live checks choose a source, freeze a manifest, add recipients and verify. Choose again restores unavailable permissions. Reconnect offline drives before rechecking. Command comma opens Settings. Checks describe a past read and do not create an atomic snapshot.","Prueba el ejemplo en la matriz o en Ajustes. Para comprobar carpetas elige un origen, crea un manifiesto, añade destinatarios y verifica. Elegir otra vez restaura permisos. Conecta las unidades sin conexión antes de verificar. Comando coma abre Ajustes. Las comprobaciones describen una lectura anterior y no crean una instantánea atómica."))
                Text("© 2026 Michael Lip").font(.caption)
                Button(L("Done","Cerrar")) { localPage=nil }
            }.padding(24).frame(width:500)
        }
    }
}
struct ContentView: View {
    @State private var receiptShown = false
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Image(systemName:model.symbol).font(.largeTitle).foregroundStyle(.teal)
                VStack(alignment:.leading) { Text("HashDock").font(.title.bold()); Text(L("Verify every delivery copy","Verifica cada copia entregada")).foregroundStyle(.secondary) }
                Spacer(); if model.sample { Text(L("Sample","Ejemplo")).font(.headline).padding(8).background(.teal.opacity(0.2),in:Capsule()) }
            }
            HStack { Text("1  "+L("See Sample","Ver ejemplo")); Image(systemName:"chevron.right"); Text("2  "+L("Choose inputs","Elegir carpetas")); Image(systemName:"chevron.right"); Text("3  "+L("Review result","Revisar resultado")) }.font(.caption).foregroundStyle(.secondary)
            HStack { Text(model.job.name).font(.title2.bold()); Spacer(); Toggle(L("Sample mode", "Modo de ejemplo"),isOn:Binding(get:{model.sample},set:{model.switchSample($0)})).toggleStyle(.switch).disabled(model.busy) }
            HStack {
                Button(L("Choose source","Elegir origen")) { model.choose(source:true) }.disabled(model.sample || model.busy)
                Button(L("Add recipient","Añadir destinatario")) { model.choose(source:false) }.disabled(model.sample || model.busy)
                Button(L("Freeze source manifest","Crear manifiesto")) { model.refresh() }.disabled(model.busy || (!model.sample && model.job.source == nil))
            }
            if !model.sample, let name=model.job.sourceName { Text(L("Source · ", "Origen · ")+name).font(.caption).foregroundStyle(.secondary) }
            if let manifest=model.job.manifest {
                HStack { Label(L("\(manifest.entries.count) files frozen","\(manifest.entries.count) archivos registrados"),systemImage:"lock.fill"); Spacer(); Text(L("Revision ","Revisión ")+String(manifest.id.prefix(8))).monospaced() }.font(.caption)
                Text(L("Frozen ","Creado ")+manifest.created.formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier:Locale.preferredLanguages.first ?? "en")))).font(.caption).foregroundStyle(.secondary)
                if !manifest.warnings.isEmpty { Text(L("Excluded or unreadable paths · ","Rutas omitidas o ilegibles · ")+manifest.warnings.map { localizedWarning($0) }.joined(separator:", ")).foregroundStyle(.orange) }
            } else { Text(L("No frozen manifest yet. Select a source and freeze it to begin.","Sin manifiesto. Elige una carpeta y crea el manifiesto.")).foregroundStyle(.secondary) }
            Button(L("Verify all recipients","Verificar todos los destinatarios")) { model.verifyAll() }.disabled(model.busy || model.job.manifest == nil || model.job.recipients.isEmpty)
            Divider()
            if model.job.recipients.isEmpty { ContentUnavailableView(L("No delivery copies yet","Sin copias todavía"),systemImage:"externaldrive",description:Text(L("Try Sample or add the folders you delivered to each recipient.","Prueba el ejemplo o añade las carpetas de los destinatarios."))).frame(height:160) }
            ScrollView {
                VStack(spacing:12) { ForEach(model.job.recipients) { recipient in
                    VStack(alignment:.leading,spacing:7) {
                        HStack { Text(recipient.alias).font(.headline); Spacer(); Text(recipient.staleReason != nil ? L("Stale · Choose again", "Anterior · Elige otra vez") : recipient.result?.current(model.job.manifest) == true ? D(recipient.result!.status) : D("Needs verification")).font(.subheadline.bold()).foregroundStyle(recipient.staleReason == nil && ["Verified","Verified with extras"].contains(recipient.result?.status ?? "") ? .teal : .orange) }
                        if let r=recipient.result {
                            Text(L("\(r.verified) verified   \(r.missing.count) missing   \(r.changed.count) changed   \(r.extra.count) extra   \(r.unreadable.count) unreadable", "\(r.verified) verificados   \(r.missing.count) ausentes   \(r.changed.count) modificados   \(r.extra.count) extra   \(r.unreadable.count) ilegibles")).font(.caption)
                            Text((r.interrupted ? L("Interrupted","Interrumpido") : (r.completed.map { L("Completed ","Completado ")+$0.formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier:Locale.preferredLanguages.first ?? "en"))) } ?? L("Check unavailable","Comprobación no disponible")))+L(" · Revision "," · Revisión ")+String(r.revision.prefix(8))).font(.caption2).foregroundStyle(.secondary)
                            if !r.missing.isEmpty { Text(L("Missing · ","Ausentes · ")+r.missing.joined(separator:", ")).font(.caption).foregroundStyle(.orange) }
                            if !r.changed.isEmpty { Text(L("Changed · ","Modificados · ")+r.changed.joined(separator:", ")).font(.caption).foregroundStyle(.orange) }
                            if !r.unreadable.isEmpty { Text(L("Unreadable · ","Ilegibles · ")+r.unreadable.map { localizedWarning($0) }.joined(separator:", ")).font(.caption).foregroundStyle(.orange) }
                        }
                        if let warnings=recipient.result?.warnings, !warnings.isEmpty { Text(warnings.map { localizedWarning($0) }.joined(separator:", ")).font(.caption).foregroundStyle(.secondary) }
                        HStack { Button(L("Verify again","Verificar otra vez")) { model.verify(recipient.id) }.accessibilityLabel(L("Verify ","Verificar ")+recipient.alias).disabled(model.busy || model.job.manifest == nil); if !model.sample { Button(L("Choose again", "Elegir otra vez")) { model.choose(source:false,recipient:recipient.id) }.disabled(model.busy) }; Button(L("Remove recipient","Eliminar destinatario")) { model.removeRecipient(recipient.id) }.disabled(model.busy) }
                    }.padding(14).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:10))
                } }
            }.frame(minHeight:230,maxHeight:430)
            if model.busy { HStack { ProgressView().controlSize(.small); Text(model.progress).lineLimit(1); Spacer(); Button(L("Cancel", "Cancelar")) { model.token.cancel() } } }
            Text(D(model.message)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text(L("Checks detect observed changes during reads. This is not an atomic filesystem snapshot.","Las comprobaciones detectan cambios observados. No es una instantánea atómica.")).font(.caption2).foregroundStyle(.secondary)
            HStack { Button(L("Review receipt","Revisar recibo")) { receiptShown=true }; Spacer(); SettingsLink { Text(L("Settings","Ajustes")) }; Links(); Button(L("Quit", "Salir")) { NSApp.terminate(nil) } }
        }.padding(24).frame(minWidth:690,idealWidth:720,maxWidth:900,minHeight:650)
        .sheet(isPresented:$receiptShown) { ReceiptView(model:model) }
    }
}
struct SettingsView: View {
    @ObservedObject var model: Model
    @State private var advanced = false
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(L("HashDock settings", "Ajustes de HashDock")).font(.title2.bold())
            if !model.sample {
                Picker(L("Select pinned job","Elegir entrega fijada"),selection:Binding(get:{model.library.pinned},set:{model.pin($0)})) {
                    ForEach(model.library.jobs.keys.sorted(),id:\.self) { key in Text(model.library.jobs[key]?.name ?? "HashDock").tag(key) }
                }
                Button(L("New delivery job","Nueva entrega")) { model.newJob() }
            }
            TextField(L("Pinned job", "Entrega fijada"),text:$model.job.name).onChange(of:model.job.name) { _ in model.save() }
            Text(L("This delivery job is pinned to the menu bar.", "Esta entrega está fijada en la barra de menús.")).font(.caption).foregroundStyle(.secondary)
            ForEach($model.job.recipients) { $recipient in TextField(L("Recipient alias", "Alias del destinatario"),text:$recipient.alias).onChange(of:recipient.alias) { _ in model.save() } }
            Toggle(L("Sample mode", "Modo de ejemplo"),isOn:Binding(get:{model.sample},set:{model.switchSample($0)}))
            Button(L("Reset sample", "Restablecer ejemplo")) { model.resetSample() }
            Picker(L("Appearance", "Apariencia"),selection:$model.appearance) { ForEach(["System","Light","Dark"],id:\.self) { Text(D($0)).tag($0) } }
            Picker(L("Open panel shortcut", "Atajo para abrir el panel"),selection:Binding(get:{HotKey.shared.key},set:{HotKey.shared.register($0); model.objectWillChange.send()})) { Text(L("Control Option H","Control Opción H")).tag(UInt32(4)); Text(L("Control Option D","Control Opción D")).tag(UInt32(2)); Text(L("Disabled", "Desactivado")).tag(UInt32(999)) }
            Text(D(HotKey.shared.message)).font(.caption)
            DisclosureGroup(L("Advanced", "Opciones avanzadas"),isExpanded:$advanced) {
                VStack(alignment:.leading) { Toggle(L("Extra files fail verification", "Los archivos extra impiden verificar"),isOn:$model.extraFails); Toggle(L("Include relative filenames in receipts", "Incluir nombres relativos en los recibos"),isOn:$model.filenames); Button(L("Clear verification history", "Borrar historial de verificación")) { model.invalidate() }; Button(L("Forget job and delete local data", "Olvidar entrega y borrar datos locales")) { model.forget() } }.padding(.top,8)
            }
            Links()
        }.padding(24).frame(width:510).disabled(model.busy)
    }
}

func D(_ value: String) -> String {
    let words: [String:String] = [
        "See Sample, choose inputs, then review each delivery.": "Prueba el ejemplo, elige carpetas y revisa cada entrega.",
        "Live mode uses only folders you select.": "El modo real usa solo las carpetas que elijas.",
        "Sample fixtures are local. Studio matches, Client is missing a file, Archive is offline.": "Los ejemplos son locales. La copia de estudio coincide, a la del cliente le falta un archivo y la de archivo está sin conexión.",
        "Source selected. Freeze a manifest before verifying.": "Origen seleccionado. Crea un manifiesto antes de verificar.",
        "Recipient selected. Edit its alias in Settings.": "Destinatario seleccionado. Edita su alias en Ajustes.",
        "Frozen manifest ready. Every recipient needs verification.": "Manifiesto listo. Verifica cada destinatario.",
        "Receipt copied. It includes verification times and coverage.": "Recibo copiado con fechas y cobertura de verificación.",
        "Local job and saved permissions cleared. Input files are unchanged.": "Entrega y permisos guardados borrados. Los archivos originales no se modificaron.",
        "Saved state could not be read. Choose folders again. Original files were not changed.": "No se pudieron leer los datos guardados. Elige las carpetas otra vez. Los archivos originales no se modificaron.",
        "Shortcut registered": "Atajo registrado",
        "Shortcut disabled": "Atajo desactivado",
        "Shortcut unavailable or in conflict. Choose another.": "Atajo no disponible o en conflicto. Elige otro.",
        "Privacy Policy": "Política de privacidad",
        "Support": "Ayuda",
        "Sample mode": "Modo de ejemplo",
        "Freeze source manifest": "Crear manifiesto",
        "Needs verification": "Necesita verificación",
        "Offline": "Sin conexión",
        "Incomplete": "Incompleto",
        "Findings": "Diferencias",
        "Verified": "Verificado",
        "Verified with extras": "Verificado con extras",
        "Choose again": "Elegir otra vez",
        "Cancel": "Cancelar",
        "Quit": "Salir",
        "HashDock settings": "Ajustes de HashDock",
        "Pinned job": "Entrega fijada",
        "Recipient alias": "Alias del destinatario",
        "Reset sample": "Restablecer ejemplo",
        "Launch at login": "Abrir al iniciar sesión",
        "Appearance": "Apariencia",
        "Open panel shortcut": "Atajo para abrir el panel",
        "Disabled": "Desactivado",
        "Advanced": "Opciones avanzadas",
        "Extra files fail verification": "Los archivos extra impiden verificar",
        "Include relative filenames in receipts": "Incluir nombres relativos en los recibos",
        "Clear verification history": "Borrar historial de verificación",
        "Forget job and delete local data": "Olvidar entrega y borrar datos locales",
        "This delivery job is pinned to the menu bar.": "Esta entrega está fijada en la barra de menús.",
        "Open delivery matrix": "Abrir matriz de entregas",
        "See Sample": "Ver ejemplo",
        "System": "Sistema", "Light": "Claro", "Dark": "Oscuro",
        "Control Option H opens the delivery matrix": "Control Opción H abre la matriz de entregas",
        "No inputs": "Sin carpetas",
        "Checking…": "Verificando…",
        "All checked": "Todo verificado"
    ]
    if Locale.preferredLanguages.first?.hasPrefix("es") == true {
        if value.hasPrefix("Source unavailable.") { return "Origen no disponible. Elige otra vez." }
        if value.hasPrefix("Manifest incomplete.") { return "Manifiesto incompleto. Cancelado o modificado durante la lectura. Inténtalo otra vez." }
        if value.hasPrefix("Could not save") { return "No se pudieron guardar los datos locales." }
        if value.hasPrefix("Permission unavailable") { return "Permiso no disponible. Elige otra vez." }
    }
    if Locale.preferredLanguages.first?.hasPrefix("es") == true, value.hasPrefix("Could not clear") { return "No se pudieron borrar los datos locales." }
    return L(value, words[value] ?? value)
}

struct ReceiptView: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text(L("Delivery receipt", "Recibo de entrega")).font(.title2.bold()); Spacer(); if model.sample { Text(L("Sample","Ejemplo")).foregroundStyle(.teal) } }
            Text(L("Verification times describe a past read. They do not guarantee files are unchanged now.", "Las fechas describen una lectura anterior. No garantizan que los archivos sigan iguales.")).foregroundStyle(.secondary)
            ScrollView { Text(model.job.receipt(sample:model.sample,filenames:model.filenames,spanish:Locale.preferredLanguages.first?.hasPrefix("es") == true)).font(.system(.body,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            HStack { Button(L("Copy delivery receipt", "Copiar recibo")) { model.copyReceipt() }; Spacer(); Button(L("Done", "Cerrar")) { dismiss() } }
        }.padding(24).frame(width:640,height:570)
    }
}

func localizedWarning(_ value: String) -> String {
    Diagnostics.localized(value,spanish:Locale.preferredLanguages.first?.hasPrefix("es") == true)
}
