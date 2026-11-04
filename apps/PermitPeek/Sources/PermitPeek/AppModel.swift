import AppKit
import Security
import PermitPeekCore
import Carbon

func L(_ en: String, _ es: String) -> String { Locale.preferredLanguages.first?.hasPrefix("es") == true ? es : en }

enum Inspector {
    static func inspect(_ url: URL) throws -> Snapshot {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard created == errSecSuccess, let code else { throw failure(created) }
        var info: CFDictionary?
        let copied = SecCodeCopySigningInformation(code, SecCSFlags(rawValue:kSecCSSigningInformation), &info)
        guard copied == errSecSuccess, let dict = info as? [String:Any], let identity = dict[kSecCodeInfoIdentifier as String] as? String else { throw failure(copied) }
        guard let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) else { throw failure(errSecIO) }
        let ent = dict[kSecCodeInfoEntitlementsDict as String] as? [String:Any] ?? [:]
        return Snapshot(identity:identity,version:plist["CFBundleShortVersionString"] as? String ?? "unknown",team:dict[kSecCodeInfoTeamIdentifier as String] as? String ?? "unknown",declarations:ent.mapValues(Compare.normalize))
    }
    static func failure(_ status: OSStatus) -> NSError { NSError(domain:"PermitPeek",code:Int(status),userInfo:[NSLocalizedDescriptionKey:L("Signature or bundle unreadable. Choose the app again to renew access. Baseline retained.","Firma o aplicación ilegible. Selecciona la aplicación de nuevo. Se conserva la referencia.") + " (\(status))"]) }
}
@MainActor final class AppModel: ObservableObject {
    static var inboxWindow: NSWindow?
    @Published var watches: [Watch] = []
    @Published var sampleMode=false
    @Published var notice=""
    @Published private(set) var savedDataUnreadable = false
    @Published var selected: String?
    @Published var shortcutChoice = UserDefaults.standard.integer(forKey:"shortcut")
    @Published var shortcutError=""
    private var live: [Watch]=[]
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    let storage: URL
    init(storage: URL? = nil, installShortcut: Bool = true) {
        self.storage = storage ?? URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/PermitPeek/watches.json")
        retrySavedData()
        if installShortcut { registerShortcut() }
    }
    private var recoveryNotice: String {
        L("Saved data could not be read. Writes are paused. Retry saved data or explicitly delete all live watches in Settings.",
          "No se pudieron leer los datos guardados. No se guardarán cambios. Reintenta o elimina las referencias reales en Ajustes.")
    }
    func retrySavedData() {
        do {
            let restored: [Watch]
            if FileManager.default.fileExists(atPath: storage.path) {
                restored = try JSONDecoder().decode([Watch].self, from: Data(contentsOf: storage))
            } else { restored = [] }
            live = restored
            if !sampleMode { watches = live }
            savedDataUnreadable = false
            notice = ""
        } catch {
            savedDataUnreadable = true
            notice = recoveryNotice
        }
    }
    var menuPresentation: MenuPresentation { MenuPresentation(watches: watches, sampleMode: sampleMode) }
    var menuStateLabel: String {
        switch symbol {
        case "questionmark.circle": return L("PermitPeek inspection unknown", "PermitPeek inspección desconocida")
        case "shield": return L("PermitPeek no watched apps", "PermitPeek sin aplicaciones")
        case "exclamationmark.shield": return L("PermitPeek changes to review", "PermitPeek cambios por revisar")
        default: return L("PermitPeek no unreviewed changes", "PermitPeek sin cambios pendientes")
        }
    }
    var menuBarTitle: String { menuPresentation.title }
    var symbol: String { menuPresentation.symbol }
    func becameActive() {}
    func persist() {
        guard !sampleMode else { return }
        guard !savedDataUnreadable else { notice = recoveryNotice; return }
        do {
            try FileManager.default.createDirectory(at:storage.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(watches).write(to:storage,options:.atomic)
            live = watches
        } catch { notice=error.localizedDescription }
    }
    func toggleSample(_ enabled: Bool) {
        if !sampleMode && !savedDataUnreadable { live=watches }
        sampleMode=enabled
        watches=enabled ? Samples.watches : live
        selected=watches.first?.id
        notice = !enabled && savedDataUnreadable ? recoveryNotice : ""
    }
    func clearSampleData() {
        guard sampleMode else { return }
        watches=[]
        selected=nil
        notice=L("Sample watches deleted. Live watches were kept.","Se borraron los ejemplos Sample. Se conservaron las referencias reales.")
    }
    func deleteAllLiveData() {
        do {
            if FileManager.default.fileExists(atPath: storage.path) { try FileManager.default.removeItem(at: storage) }
            live=[]
            if !sampleMode { watches=[]; selected=nil }
            savedDataUnreadable=false
            notice=L("All live watches and history deleted from this Mac.","Se borraron todas las referencias reales y el historial de este Mac.")
        } catch { notice=error.localizedDescription }
    }
    func choose() {
        guard !savedDataUnreadable else { notice = recoveryNotice; return }
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.applicationBundle]; panel.directoryURL=URL(fileURLWithPath:"/Applications"); panel.canChooseDirectories=false
        guard panel.runModal() == .OK, let url=panel.url else { notice=L("Selection cancelled. Nothing changed.","Selección cancelada. No hay cambios."); return }
        if sampleMode { toggleSample(false) }
        do {
            let bookmark=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
            let i=watches.firstIndex(where:{$0.id == url.path})
            var watch=i.map { watches[$0] } ?? Watch(id:url.path,name:url.deletingPathExtension().lastPathComponent)
            watch.bookmark=bookmark
            do { watch.receive(try Inspector.inspect(url)) } catch { watch.fail(error.localizedDescription) }
            if let i { watches[i]=watch } else { watches.append(watch) }; selected=watch.id; persist()
        } catch { notice=error.localizedDescription }
    }
    func rescan() {
        if sampleMode { watches=Samples.watches; return }
        guard !savedDataUnreadable else { notice = recoveryNotice; return }
        for i in watches.indices {
            do {
                guard let data=watches[i].bookmark else { throw Inspector.failure(errSecIO) }
                var stale=false
                let url=try URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale)
                let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                if stale { watches[i].bookmark=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil) }
                watches[i].receive(try Inspector.inspect(url))
            } catch { watches[i].fail(error.localizedDescription) }
        }
        persist()
    }
    func acknowledge(_ id: String) { guard sampleMode || !savedDataUnreadable else { notice = recoveryNotice; return }; if let i=watches.firstIndex(where:{$0.id==id}) { watches[i].acknowledge(); persist() } }
    func remove(_ id: String) { guard sampleMode || !savedDataUnreadable else { notice = recoveryNotice; return }; watches.removeAll{$0.id==id}; persist() }
    func copy(_ w: Watch) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(w.report,forType:.string); notice=L("Report copied","Informe copiado") }
    func registerShortcut() {
        if let hotkey { UnregisterEventHotKey(hotkey) }; hotkey=nil
        if handler == nil {
            var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(),{ _,_,_ in
                DispatchQueue.main.async { NSApp.activate(ignoringOtherApps:true); (AppModel.inboxWindow ?? NSApp.windows.first(where:{$0.canBecomeKey}))?.makeKeyAndOrderFront(nil) }; return noErr
            },1,&spec,nil,&handler)
        }
        UserDefaults.standard.set(shortcutChoice,forKey:"shortcut")
        guard shortcutChoice != 2 else { shortcutError=""; return }
        let status=RegisterEventHotKey(UInt32(shortcutChoice == 0 ? kVK_ANSI_P : kVK_ANSI_I),UInt32(cmdKey | shiftKey),EventHotKeyID(signature:0x50504B31,id:1),GetApplicationEventTarget(),0,&hotkey)
        shortcutError=status == noErr ? "" : L("Shortcut unavailable. Use the menu bar icon.","Atajo no disponible. Usa el icono de la barra de menús.")
    }
}
