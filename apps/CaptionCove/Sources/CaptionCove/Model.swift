import AppKit
import SwiftUI
import CaptionCoveCore
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
    @Published var project=Project()
    @Published var sampleMode=false
    @Published var sampleResult:ScanResult?
    @Published var sampleRules=Rules()
    @Published var checking=false
    @Published var message=""
    @Published var error=false
    @Published var selected="Spanish"
    @Published var previews=[String:ParsedSRT]()
    @Published var language=UserDefaults.standard.string(forKey:"language") ?? "en" { didSet { UserDefaults.standard.set(language,forKey:"language") } }
    @Published var appearance=UserDefaults.standard.string(forKey:"appearance") ?? "system" { didSet { UserDefaults.standard.set(appearance,forKey:"appearance") } }
    @Published var hotkeyKey=UserDefaults.standard.string(forKey:"hotkeyKey") ?? "C" { didSet { UserDefaults.standard.set(hotkeyKey,forKey:"hotkeyKey"); configureHotkey?() } }
    @Published var hotkeyModifiers=UserDefaults.standard.string(forKey:"hotkeyModifiers") ?? "off" { didSet { UserDefaults.standard.set(hotkeyModifiers,forKey:"hotkeyModifiers"); configureHotkey?() } }
    @Published var hotkeyError=""
    var configureHotkey:(()->Void)?
    private var task:Task<Void,Never>?
    private var generation=UUID()
    let folder:URL
    var stateURL:URL { folder.appendingPathComponent("project.json") }
    var result:ScanResult? { sampleMode ? sampleResult : project.result }
    var rules:Rules { sampleMode ? sampleRules : project.rules }
    var canCopy:Bool { result != nil && result?.stale != true && !checking }
    var summaryText:String {
        guard let result else { return l("Choose a reference and language files to compare subtitle deliveries","Selecciona una referencia y los archivos traducidos para comparar subtítulos") }
        if result.stale { return l("Previous results are stale. Rescan to review current delivery parity","Los resultados anteriores están desactualizados. Comprueba para revisar la comparación actual") }
        if let first=result.rows.flatMap({$0.findings}).first { return reason(first.reason) }
        return l("All language deliveries match the reference within your rules","Todas las entregas coinciden con la referencia según tus reglas")
    }
    var state:ReviewState { checking ? .incomplete : result?.state ?? .incomplete }
    var stateText:String { checking ? l("Checking","Comprobando") : l(state.rawValue, state == .ready ? "Listo" : state == .issues ? "Problemas" : "Incompleto") }
    var scheme:ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    var lastCheck:String { result.map { $0.date.formatted(date:.abbreviated,time:.shortened) } ?? l("Never checked","Sin comprobaciones") }
    var tooltip:String { "CaptionCove \(sampleMode ? "Sample " : "")\(stateText) \(lastCheck)" }
    init(folder customFolder:URL?=nil) {
        self.folder=customFolder ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CaptionCove")
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            if FileManager.default.fileExists(atPath:stateURL.path) { project=try Persistence.load(from:stateURL); project.result?.stale=true }
        } catch { message=l("Saved project could not be read. Choose your inputs again or forget project","No se pudo leer el proyecto guardado. Selecciona los archivos otra vez u olvida el proyecto"); self.error=true }
    }
    func l(_ english:String,_ spanish:String)->String { language == "es" ? spanish : english }
    func kind(_ kind:IssueKind)->String {
        let map:[IssueKind:String]=[.missing:"Ausentes",.extra:"Adicionales",.drift:"Tiempos",.text:"Texto",.overlap:"Solapan",.invalid:"Inválidos",.identity:"IDs no aptos"]
        return language == "es" ? map[kind]! : kind.rawValue
    }
    func label(_ text:String)->String {
        let map=["Reference":"Referencia","Spanish":"Español","French":"Francés","Empty translation":"Traducción vacía","Overlap example":"Ejemplo de solapamiento","Languages":"Idiomas"]
        return language == "es" && (sampleMode || text == "Reference" || text == "Languages") ? map[text] ?? text : text
    }
    func reason(_ text:String)->String {
        guard language == "es" else { return text }
        let replacements=[("Saved file permission is stale","El permiso guardado del archivo está desactualizado"),("Only SRT files are supported","Solo se admiten archivos SRT"),("SRT file exceeds the 10 MB local input limit","El archivo SRT supera el límite local de 10 MB"),("Input unavailable. Choose again. ","Archivo no disponible. Selecciona otra vez. "),("Reference unavailable","Referencia no disponible"),("Too many findings. The result is truncated and incomplete","Demasiados avisos. El resultado está truncado e incompleto"),("Cue IDs differ and may be renumbered. ID matching is unsuitable. Supply the original cue map","Los IDs difieren y pueden estar renumerados. No se pueden comparar por ID. Proporciona el mapa original"),("No subtitle cues found","No se encontraron subtítulos"),("Choose at least one language SRT","Selecciona al menos un SRT traducido"),("Empty visible text","Texto visible vacío"),("Reference cue is absent","Falta un subtítulo de referencia"),("Cue is absent from reference","El subtítulo no existe en la referencia"),("Signed start drift","Desfase firmado de inicio"),("and end drift","y de final"),("characters per second exceeds user rule","caracteres por segundo supera la regla"),("Overlaps cue","Solapa el subtítulo"),("by ","durante "),("Duplicate cue ID","ID de subtítulo duplicado"),("has a malformed timecode","tiene un tiempo incorrecto"),("has zero or reversed duration","tiene duración nula o invertida"),("Cue ","Subtítulo "),("Block ","Bloque "),("has an invalid cue ID or missing timing","tiene un ID incorrecto o carece de tiempos"),("File is not valid UTF8","El archivo no es UTF8 válido")]
        return replacements.reduce(text){$0.replacingOccurrences(of:$1.0,with:$1.1)}
    }
    func persist() {
        do { try Persistence.save(project,to:stateURL) }
        catch { message=l("Could not save the project. Current results remain available in this session","No se pudo guardar el proyecto. Los resultados siguen disponibles en esta sesión"); self.error=true }
    }
    func stop() { task?.cancel(); generation=UUID(); checking=false }
    func toggleSample(_ enabled:Bool) {
        stop(); sampleMode=enabled; previews=[:]; message=""; error=false
        if enabled { resetSample() } else { selected=project.languages.first?.label ?? "Reference"; becameActive() }
    }
    func resetSample() {
        stop(); sampleRules=Rules()
        do {
            let dir=folder.appendingPathComponent("Sample")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            try Data(Samples.reference.utf8).write(to:dir.appendingPathComponent("Reference.srt"),options:.atomic)
            for (label,text) in Samples.languages { try Data(text.utf8).write(to:dir.appendingPathComponent(label+".srt"),options:.atomic) }
            sampleMode=true; selected="Spanish"; scan()
        } catch { message=l("Sample fixtures could not be written","No se pudieron guardar los archivos Sample"); self.error=true }
    }
    func choose(reference:Bool,label:String="") {
        stop()
        let cleaned=label.trimmingCharacters(in:.whitespacesAndNewlines)
        if !reference && (cleaned.isEmpty || cleaned.caseInsensitiveCompare("Reference") == .orderedSame || project.languages.contains(where:{$0.label.caseInsensitiveCompare(cleaned) == .orderedSame})) {
            message=l("Give this language a unique label before choosing its file","Escribe una etiqueta única para este idioma antes de seleccionar el archivo"); self.error=true; return
        }
        let panel=NSOpenPanel(); panel.canChooseDirectories=false; panel.allowsMultipleSelection=false; panel.allowedContentTypes=[UTType(filenameExtension:"srt") ?? .plainText]
        panel.message=l("Choose an SRT file. CaptionCove reads it without changing it","Selecciona un SRT. CaptionCove lo lee sin modificarlo")
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let url=panel.url else { self.project.result?.stale=true; self.message=self.l("Selection cancelled. Previous results are stale","Selección cancelada. Los resultados anteriores están desactualizados"); self.persist(); return }
                do {
                    guard url.pathExtension.lowercased() == "srt" else { throw InputError.unsupported }
                    let accessed=url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let bookmark=try url.bookmarkData(options:[.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys:nil,relativeTo:nil)
                    let input=InputReference(label:reference ? "Reference" : cleaned,bookmark:bookmark,filename:url.lastPathComponent)
                    self.sampleMode=false; self.sampleResult=nil; self.previews=[:]
                    if reference { self.project.reference=input } else { self.project.languages.append(input); self.selected=cleaned }
                    self.project.result?.stale=true; self.message=""; self.error=false; self.persist(); self.scan()
                } catch { self.message=self.l("Cannot access this SRT. Choose again to grant file access. ","No se puede acceder al SRT. Selecciónalo otra vez para conceder acceso. ")+self.reason(error.localizedDescription); self.error=true; self.project.result?.stale=true; self.persist() }
            }
        }
    }
    func replace(_ input:InputReference) {
        // Remove only the stored reference. The original file is never modified.
        if input.label == "Reference" { choose(reference:true) }
        else {
            stop()
            let panel=NSOpenPanel(); panel.allowedContentTypes=[UTType(filenameExtension:"srt") ?? .plainText]
            panel.begin { [weak self] response in Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let url=panel.url else { self.project.result?.stale=true; self.message=self.l("Selection cancelled. Previous results are stale","Selección cancelada. Los resultados anteriores están desactualizados"); self.persist(); return }
                do {
                    guard url.pathExtension.lowercased() == "srt" else { throw InputError.unsupported }
                    let accessed=url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let bookmark=try url.bookmarkData(options:[.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys:nil,relativeTo:nil)
                    guard let index=self.project.languages.firstIndex(where:{$0.id == input.id}) else { return }
                    self.project.languages[index]=InputReference(id:input.id,label:input.label,bookmark:bookmark,filename:url.lastPathComponent)
                    self.persist(); self.scan()
                } catch { self.message=self.l("File access denied. Choose again","Acceso denegado. Selecciona otra vez"); self.error=true; self.project.result?.stale=true; self.persist() }
            } }
        }
    }
    func remove(_ input:InputReference) { stop(); project.languages.removeAll{$0.id == input.id}; project.result?.stale=true; previews=[:]; persist() }
    func updateRules(_ rules:Rules) {
        stop()
        if sampleMode { sampleRules=rules; sampleResult?.stale=true; scan() }
        else { project.rules=rules; project.result?.stale=true; persist() }
    }
    func scan() {
        stop(); message=""; error=false
        if !sampleMode && project.reference == nil { message=l("Choose a reference SRT and at least one language to begin","Selecciona un SRT de referencia y al menos un idioma para empezar"); project.result?.stale=true; persist(); return }
        let token=UUID(); generation=token; checking=true
        let mode=sampleMode, captured=project, capturedRules=rules, dir=folder.appendingPathComponent("Sample")
        task=Task {
            let result=await Task.detached(priority:.userInitiated) { () -> ScanWork in
                do {
                    var parsed=[String:ParsedSRT](), inputs=captured
                    if mode {
                        parsed["Reference"]=SRTParser.parse(data:try Data(contentsOf:dir.appendingPathComponent("Reference.srt")))
                        for (label,_) in Samples.languages { parsed[label]=SRTParser.parse(data:try Data(contentsOf:dir.appendingPathComponent(label+".srt"))) }
                    } else {
                        let work=Self.loadLiveProject(inputs)
                        parsed=work.parsed; inputs=work.project
                    }
                    let labels=mode ? Samples.languages.map(\.0) : captured.languages.map(\.label)
                    let scan=Comparator.scan(reference:parsed["Reference"] ?? ParsedSRT(cues:[],errors:["Reference unavailable"]),languages:labels.compactMap{label in parsed[label].map{(label,$0)}},rules:capturedRules,sample:mode)
                    return ScanWork(result:scan,parsed:parsed,project:inputs,failure:nil)
                } catch { return ScanWork(result:nil,parsed:[:],project:captured,failure:error.localizedDescription) }
            }.value
            guard !Task.isCancelled, generation == token else { return }
            checking=false
            if let failure=result.failure {
                error=true; message=l("Input unavailable or permission denied. Choose again. ","Archivo no disponible o permiso denegado. Selecciona otra vez. ")+failure
                if mode { sampleResult?.stale=true } else { project.result?.stale=true; persist() }
            } else if let scan=result.result {
                previews=result.parsed
                if mode { sampleResult=scan } else { project=result.project; project.result=scan; persist() }
                if !scan.rows.contains(where:{$0.label == selected}) { selected=scan.rows.first?.label ?? "Reference" }
            }
        }
    }
    nonisolated static func loadLiveProject(_ captured:Project, reader:(InputReference)throws->(ParsedSRT,Date?,Data)=AppModel.read) -> ScanWork {
        var inputs=captured, parsed=[String:ParsedSRT]()
        func readOne(_ input:inout InputReference) {
            do { let read=try reader(input); parsed[input.label]=read.0; input.modification=read.1; input.bookmark=read.2 }
            catch { parsed[input.label]=ParsedSRT(cues:[],errors:["Input unavailable. Choose again. "+error.localizedDescription]) }
        }
        if var reference=inputs.reference { readOne(&reference); inputs.reference=reference }
        for index in inputs.languages.indices { readOne(&inputs.languages[index]) }
        let result=Comparator.scan(reference:parsed["Reference"] ?? ParsedSRT(cues:[],errors:["Reference unavailable"]),languages:inputs.languages.map { ($0.label,parsed[$0.label] ?? ParsedSRT(cues:[],errors:["Input unavailable. Choose again. "])) },rules:inputs.rules)
        return ScanWork(result:result,parsed:parsed,project:inputs,failure:nil)
    }
    nonisolated static func read(_ input:InputReference) throws -> (ParsedSRT,Date?,Data) {
        var stale=false
        let url=try URL(resolvingBookmarkData:input.bookmark,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale)
        return try readResolved(input,url:url,stale:stale)
    }
    nonisolated static func readResolved(_ input:InputReference,url:URL,stale:Bool) throws -> (ParsedSRT,Date?,Data) {
        guard url.pathExtension.lowercased() == "srt" else { throw InputError.unsupported }
        let accessed=url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values=try url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
        guard (values.fileSize ?? 0)<=10*1024*1024 else { throw InputError.tooLarge }
        let data=try Data(contentsOf:url)
        guard data.count<=10*1024*1024 else { throw InputError.tooLarge }
        let bookmark=stale ? try url.bookmarkData(options:[.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys:nil,relativeTo:nil) : input.bookmark
        return (SRTParser.parse(data:data),values.contentModificationDate,bookmark)
    }
    func becameActive() {
        guard !sampleMode,!checking else { return }
        for input in ([project.reference].compactMap{$0}+project.languages) {
            do {
                var stale=false
                let url=try URL(resolvingBookmarkData:input.bookmark,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale)
                let accessed=url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let modification=try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
                if stale || modification != input.modification {
                    project.result?.stale=true; previews=[:]; persist(); return
                }
            } catch { project.result?.stale=true; previews=[:]; message=l("File access is unavailable. Choose again","El acceso al archivo no está disponible. Selecciona otra vez"); self.error=true; persist(); return }
        }
    }
    func cancelScan() { stop(); if sampleMode { sampleResult?.stale=true } else { project.result?.stale=true; persist() }; message=l("Check cancelled. Results are incomplete until you rescan","Comprobación cancelada. Los resultados son incompletos hasta comprobar otra vez") }
    func forget() { stop(); project=Project(); sampleResult=nil; sampleMode=false; previews=[:]; selected="Reference"; message=""; error=false; persist() }
    func clearAll() {
        forget()
        language="en"; appearance="system"; hotkeyKey="C"; hotkeyModifiers="off"
        for key in ["language","appearance","hotkeyKey","hotkeyModifiers"] { UserDefaults.standard.removeObject(forKey:key) }
        do { if FileManager.default.fileExists(atPath:folder.path) { try FileManager.default.removeItem(at:folder) }; try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true) }
        catch { message=l("Some local data could not be deleted","No se pudieron eliminar algunos datos locales"); self.error=true }
    }
    func copy(includeText:Bool=false) {
        guard canCopy, let result else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result.report(dialogue:includeText ? previews : nil),forType:.string)
        message=l(includeText ? "Copied report with dialogue text" : "Copied report without dialogue text",includeText ? "Informe copiado con diálogo" : "Informe copiado sin diálogo")
    }
}
struct ScanWork { var result:ScanResult?; var parsed:[String:ParsedSRT]; var project:Project; var failure:String? }
enum InputError:LocalizedError {
    case stale,unsupported,tooLarge
    var errorDescription:String? {
        switch self {
        case .stale:return "Saved file permission is stale"
        case .unsupported:return "Only SRT files are supported"
        case .tooLarge:return "SRT file exceeds the 10 MB local input limit"
        }
    }
}
