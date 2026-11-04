import SwiftUI
import PermitPeekCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Image(systemName:model.symbol).font(.largeTitle).foregroundStyle(.cyan).accessibilityLabel(model.menuStateLabel)
                VStack(alignment:.leading) { Text("PermitPeek").font(.title.bold()); Text(L("Your permission change inbox","Tu bandeja de cambios de permisos")).foregroundStyle(.secondary) }
                Spacer()
                if model.sampleMode { Text("Sample").font(.headline).padding(8).background(.orange.opacity(0.18),in:Capsule()) }
                SettingsLink { Image(systemName:"gearshape") }.accessibilityLabel(L("Settings","Ajustes"))
            }
            HStack {
                Button(L("Choose app","Elegir aplicación")) { model.choose() }.keyboardShortcut("o").disabled(model.savedDataUnreadable)
                Button(L("Rescan","Volver a inspeccionar")) { model.rescan() }.disabled(model.watches.isEmpty || (!model.sampleMode && model.savedDataUnreadable))
                Spacer()
                Button(model.sampleMode ? L("Leave Sample","Salir de Sample") : L("Try Sample","Probar Sample")) { model.toggleSample(!model.sampleMode) }
            }
            Text(L("Choose an application to allow read only inspection. Scans run only when you ask.","Elige una aplicación para permitir su inspección de solo lectura. Inspecciona cuando lo solicites.")).font(.caption).foregroundStyle(.secondary)
            if !model.notice.isEmpty { Text(model.notice).foregroundStyle(.orange).font(.caption) }
            if model.watches.isEmpty {
                ContentUnavailableView(L("No watched apps","No hay aplicaciones"),systemImage:"shield",description:Text(L("Choose app to inspect a signature and save your first baseline, or try Sample.","Elige una aplicación para guardar la primera referencia o prueba Sample."))).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    VStack(spacing:14) {
                        ForEach(model.watches) { watch in
                            VStack(alignment:.leading,spacing:10) {
                                HStack { Text(watch.name).font(.title3.bold()); Spacer(); Text(watch.error != nil ? L("Unknown","Desconocido") : watch.baseline == nil ? L("Baseline needed","Sin referencia") : watch.changes.isEmpty ? L("No changes","Sin cambios") : L("Review changes","Revisar cambios")).font(.caption).foregroundStyle(.orange) }
                                if let error=watch.error { Text(model.sampleMode ? L(error,"No se pudo leer la firma de Sample. Se conserva la referencia anterior.") : error).foregroundStyle(.orange).font(.callout) }
                                if let current=watch.current {
                                    Text("\(current.identity)  •  \(current.version)").font(.caption).textSelection(.enabled)
                                    Text(L(current.networkExplanation, !current.sandboxed ? "Sandbox no declarado. Se desconoce el acceso efectivo a la red." : current.declarations["com.apple.security.network.client"] == "true" ? "Red saliente declarada. Se desconoce el tráfico real." : "Red saliente no declarada. Se desconoce el acceso efectivo completo.")).font(.callout)
                                    if let date=watch.scanned { Text(L("Last explicit scan ","Última inspección ")+date.formatted()).font(.caption).foregroundStyle(.secondary) }
                                    if watch.baseline == nil { Text(L("Inspect the declarations below, then acknowledge to create a baseline.","Revisa las declaraciones y acepta para crear una referencia.")).font(.callout) }
                                    ForEach(watch.changes) { c in
                                        VStack(alignment:.leading,spacing:4) {
                                            Text("\(L(c.kind, c.kind == "Added" ? "Añadido" : c.kind == "Removed" ? "Eliminado" : "Modificado"))  \(friendly(c.key))").font(.headline)
                                            Text("\(c.before ?? L("Not declared", "No declarado"))  →  \(c.after ?? L("Not declared", "No declarado"))").font(.system(.body,design:.monospaced)).textSelection(.enabled)
                                            Text(c.key).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                        }.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(.cyan.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
                                    }
                                    DisclosureGroup(L("All current declarations","Todas las declaraciones actuales")) {
                                        ForEach(current.declarations.keys.sorted(),id:\.self) { key in
                                            VStack(alignment:.leading) { Text(friendly(key)).bold(); Text(key).font(.caption); Text(current.declarations[key] ?? "unknown").font(.system(.caption,design:.monospaced)) }.frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled).padding(.vertical,4)
                                        }
                                    }
                                }
                                Text(L("Main executable only. Helpers, traffic, TCC grants and complete effective access are unknown.","Solo el ejecutable principal. Se desconocen los auxiliares, tráfico, permisos TCC y acceso efectivo completo.")).font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button(L("Acknowledge changes","Aceptar cambios")) { model.acknowledge(watch.id) }.disabled(watch.current == nil || watch.error != nil || (watch.baseline != nil && watch.changes.isEmpty))
                                    Button(L("Copy report","Copiar informe")) { model.copy(watch) }
                                    Spacer()
                                    Button(L("Remove","Eliminar"),role:.destructive) { model.remove(watch.id) }
                                }
                            }.padding(16).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                        }
                    }
                }
            }
            Divider()
            HStack { PolicySupportLinks(); Spacer(); Text(L("Local inspection • No verdicts","Inspección local • Sin veredictos")).font(.caption).foregroundStyle(.secondary) }
        }.padding(22).frame(width:760,height:720)
    }
    func friendly(_ key: String) -> String {
        switch key {
        case "Signing team": return L("Signing team", "Equipo firmante")
        case "Version": return L("Version", "Versión")
        case "Bundle identity": return L("Bundle identity", "Identidad de aplicación")
        case "com.apple.security.app-sandbox": return L("App Sandbox declaration","Declaración de App Sandbox")
        case "com.apple.security.network.client": return L("Outgoing network declaration","Declaración de red saliente")
        case "com.apple.security.network.server": return L("Incoming network declaration","Declaración de red entrante")
        case "com.apple.security.files.user-selected.read-only": return L("Selected files read access","Lectura de archivos seleccionados")
        case "com.apple.security.files.user-selected.read-write": return L("Selected files write access","Escritura de archivos seleccionados")
        default:return key
        }
    }
}
