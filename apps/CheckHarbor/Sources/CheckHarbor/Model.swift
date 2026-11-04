import Foundation
import SwiftUI
import Security
import CheckHarborCore

func L(_ english: String,_ spanish: String) -> String { Locale.preferredLanguages.first?.hasPrefix("es") == true ? spanish : english }

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum Credentials {
    static let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.michaellip.checkharbor",kSecAttrAccount as String:"github"]
    static func read() throws -> String? {
        var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        var result: CFTypeRef?; let status=SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,let data=result as? Data else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(status)) }
        return String(data:data,encoding:.utf8)
    }
    static func save(_ token: String) throws {
        if token.isEmpty { try remove(); return }
        let data=Data(token.utf8)
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var q=query; q[kSecValueData as String]=data; q[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added=SecItemAdd(q as CFDictionary,nil)
            guard added == errSecSuccess else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(added)) }; return
        }
        guard status == errSecSuccess else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(status)) }
    }
    static func remove() throws { let s=SecItemDelete(query as CFDictionary); guard s == errSecSuccess || s == errSecItemNotFound else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(s)) } }
}
struct RepositoryState: Codable {
    var inbox = Inbox()
    var runs: [String:[Run]] = [:]
    var fetched: [String:Date] = [:]
    var etags: [String:String] = [:]
    var backoff: Date?
}
struct Payload: Decodable { let workflow_runs: [Run] }
@MainActor final class Model: ObservableObject {
    @Published var state=RepositoryState()
    @Published var repositories: [String] = []
    @Published var sample=false
    @Published var message=""
    @Published var errors: [String:String] = [:]
    @Published var busy=false
    @Published var staleSample=false
    @Published var recovered=false
    @Published var interval: Int = 300 { didSet { defaults.set(interval,forKey:"interval") } }
    @Published var retention: Int = 30 { didSet { defaults.set(retention,forKey:"retention") } }
    @Published var snoozeMinutes: Int = 60 { didSet { defaults.set(snoozeMinutes,forKey:"snooze") } }
    @Published var shortcut: Int = 0 { didSet { defaults.set(shortcut,forKey:"shortcut"); Shortcut.shared.register(choice:shortcut) { self.open() }; shortcutError=Shortcut.shared.error } }
    @Published var shortcutError=""
    private let defaults=UserDefaults.standard
    private let ephemeral: Bool
    private var generation=UUID()
    private var timer: Timer?
    private var lastAttempt=Date.distantPast
    private let file=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/CheckHarbor/live.json")
    private let session: URLSession
    private let tokenProvider: () throws -> String?
    private var loadFailed=false
    private var fallbackWindow: NSWindow?
    init(ephemeral: Bool=false, session: URLSession? = nil, tokenProvider: @escaping () throws -> String? = Credentials.read) {
        self.session=session ?? URLSession(configuration:.ephemeral,delegate:NoRedirect(),delegateQueue:nil)
        self.tokenProvider=tokenProvider
        self.ephemeral=ephemeral
        if !ephemeral {
            repositories=defaults.stringArray(forKey:"repositories") ?? []
            interval=max(60,defaults.integer(forKey:"interval") == 0 ? 300 : defaults.integer(forKey:"interval"))
            retention=max(1,defaults.integer(forKey:"retention") == 0 ? 30 : defaults.integer(forKey:"retention"))
            snoozeMinutes=max(1,defaults.integer(forKey:"snooze") == 0 ? 60 : defaults.integer(forKey:"snooze"))
            shortcut=defaults.integer(forKey:"shortcut")
            load()
            timer=Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [weak self] _ in Task { @MainActor in
                guard let self else { return }; self.objectWillChange.send()
                if Date().timeIntervalSince(self.lastAttempt) >= Double(self.interval) { await self.refresh() }
            } }
        }
    }
    func startShortcut() { Shortcut.shared.register(choice:shortcut) { self.open() }; shortcutError=Shortcut.shared.error }
    func open() {
        recovered=false
        NSApp.activate(ignoringOtherApps:true)
        if let window=NSApp.windows.first(where:{$0.title == "CheckHarbor"}) { window.makeKeyAndOrderFront(nil); return }
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:720,height:720),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="CheckHarbor"; window.isReleasedWhenClosed=false; window.contentView=NSHostingView(rootView:ContentView(model:self)); window.center(); window.makeKeyAndOrderFront(nil); fallbackWindow=window
    }
    var shown: [Episode] { (recovered ? state.inbox.recovered : state.inbox.active).sorted { a,b in
        if a.snoozed(at:Date()) != b.snoozed(at:Date()) { return !a.snoozed(at:Date()) }; return a.latest.updated_at > b.latest.updated_at
    } }
    var stale: Bool { (state.backoff ?? .distantPast) > Date() || staleSample || !errors.isEmpty || (!sample && repositories.contains { state.fetched[$0].map { Date().timeIntervalSince($0) > Double(interval*2) } ?? true }) }
    var symbol: String { !sample && repositories.isEmpty ? "shippingbox" : stale ? "clock.badge.exclamationmark" : state.inbox.active.isEmpty ? "checkmark.circle" : "exclamationmark.circle" }
    var status: String { if !sample && repositories.isEmpty { return L("Setup required","Configuración necesaria") }; if stale { return L("Stale or unavailable","Datos antiguos o no disponibles") }; return state.inbox.active.isEmpty ? L("No unresolved failures","Sin fallos pendientes") : L("Unresolved failures","Fallos pendientes") }
    func load() {
        loadFailed=false
        guard FileManager.default.fileExists(atPath:file.path) else { state=RepositoryState(); return }
        do { state=try JSONDecoder().decode(RepositoryState.self,from:Data(contentsOf:file)) }
        catch { loadFailed=true; message=L("Local history could not be read. Existing file is preserved.","No se pudo leer el historial local. Se conserva el archivo existente."); state=RepositoryState() }
    }
    func persist() {
        guard !sample && !ephemeral && !loadFailed else { return }
        do { try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true); try JSONEncoder().encode(state).write(to:file,options:.atomic) }
        catch { message=L("Could not save history. Check available storage.","No se pudo guardar el historial. Comprueba el almacenamiento.") }
    }
    func toggleSample(_ value: Bool) {
        generation=UUID(); sample=value; errors=[:]; message=""; recovered=false; staleSample=false
        if value { resetSample() } else { load() }
    }
    func resetSample() { state=RepositoryState(); state.inbox.ingest(repository:"harbor/demo",runs:Fixtures.initial); state.runs["harbor/demo"]=Fixtures.initial; state.fetched["harbor/demo"]=Date(); staleSample=false; recovered=false }
    func sampleRecovery() { state.inbox.ingest(repository:"harbor/demo",runs:Fixtures.recovery); state.runs["harbor/demo"]=Fixtures.recovery; recovered=true }
    func acknowledge(_ e: Episode) { state.inbox.acknowledge(e.id); persist() }
    func snooze(_ e: Episode) { state.inbox.snooze(e.id,until:e.snoozed(at:Date()) ? nil : Date().addingTimeInterval(Double(snoozeMinutes*60))); persist() }
    func add(_ text: String) {
        guard let repo=Validation.repository(text) else { message=L("Use owner/repository with no URL or spaces.","Usa propietario/repositorio sin URL ni espacios."); return }
        if !repositories.contains(repo) { repositories.append(repo); defaults.set(repositories,forKey:"repositories") }; message=""
    }
    func remove(_ repo: String) { generation=UUID(); repositories.removeAll{$0 == repo}; defaults.set(repositories,forKey:"repositories"); errors.removeValue(forKey:repo); message=L("Monitoring removed. History is kept until you delete local data.","Supervisión eliminada. El historial se conserva hasta borrar los datos locales.") }
    func deleteData() {
        generation=UUID(); state=RepositoryState(); errors=[:]; message=""
        if sample { return }
        loadFailed=false; repositories=[]; defaults.removeObject(forKey:"repositories")
        do { if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) } } catch { message=error.localizedDescription }
    }
    func token(_ text: String) { do { try Credentials.save(text); state.etags=[:]; message=L("Credentials updated","Credenciales actualizadas"); persist() } catch { message=L("Keychain access failed. Try again.","Falló el acceso al llavero. Inténtalo de nuevo.") } }
    func refresh() async {
        guard !busy else { return }
        guard !sample else { message=L("Sample mode makes no network requests","El modo Sample no realiza solicitudes de red"); return }
        guard Validation.mayFetch(sample:sample,until:state.backoff,now:Date()) else { message=L("Rate limit backoff is active","Espera por límite de solicitudes activa"); return }
        guard !repositories.isEmpty else { return }
        busy=true; defer { busy=false }; lastAttempt=Date(); let current=generation
        let token: String?
        do { token=try tokenProvider() } catch { message=L("Keychain access denied. Open Settings and retry credentials.","Acceso al llavero denegado. Abre Ajustes y vuelve a guardar las credenciales."); return }
        for repo in repositories {
            guard current == generation, !sample else { return }
            var request=URLRequest(url:URL(string:"https://api.github.com/repos/\(repo)/actions/runs?per_page=100")!)
            request.timeoutInterval=30; request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
            request.setValue("2022-11-28",forHTTPHeaderField:"X-GitHub-Api-Version")
            request.setValue("CheckHarbor",forHTTPHeaderField:"User-Agent")
            if let token,!token.isEmpty { request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
            if let etag=state.etags[repo] { request.setValue(etag,forHTTPHeaderField:"If-None-Match") }
            do {
                let (data,response)=try await session.data(for:request)
                guard current == generation,!sample else { return }
                guard let http=response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                let headers=http.allHeaderFields.reduce(into:[String:String]()) { $0[String(describing:$1.key)]=String(describing:$1.value) }
                state.backoff=Validation.backoff(status:http.statusCode,headers:headers,now:Date())
                if http.statusCode == 304 { state.fetched[repo]=Date(); errors.removeValue(forKey:repo) }
                else if http.statusCode == 200 {
                    let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                    let runs=try decoder.decode(Payload.self,from:data).workflow_runs
                    state.inbox.ingest(repository:repo,runs:runs); state.runs[repo]=runs; state.fetched[repo]=Date(); state.etags[repo]=http.value(forHTTPHeaderField:"ETag"); errors.removeValue(forKey:repo)
                } else {
                    errors[repo] = http.statusCode == 401 ? L("Authentication failed. Replace or remove the token.","Autenticación fallida. Sustituye o elimina el token.") : http.statusCode == 404 ? L("Repository unavailable or access denied. Check the name and Actions read permission.","Repositorio no disponible o acceso denegado. Comprueba el nombre y el permiso de lectura de Actions.") : [403,429].contains(http.statusCode) ? L("Access denied or rate limited. Check token permissions and retry after backoff.","Acceso denegado o límite alcanzado. Comprueba los permisos y espera.") : L("Service unavailable. Retry later.","Servicio no disponible. Inténtalo más tarde.")
                }
            } catch { guard current == generation else { return }; errors[repo]=L("Fetch failed. History preserved. Check your connection and retry.","Consulta fallida. Historial conservado. Comprueba la conexión y reintenta.") }
            state.inbox.prune(before:Date().addingTimeInterval(-Double(retention)*86400)); persist()
            if state.backoff != nil { break }
        }
    }
}
