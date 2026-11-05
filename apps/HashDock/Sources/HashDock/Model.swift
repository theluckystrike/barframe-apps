import AppKit
import SwiftUI
import HashDockCore

@MainActor final class Model: ObservableObject {
    @Published var job = Job()
    @Published var library = JobLibrary()
    private var verifyQueue: [UUID] = []
    @Published var sample = false
    @Published var busy = false
    @Published var message = "See Sample, choose inputs, then review each delivery."
    @Published var progress = ""
    @Published var extraFails = false { didSet { if !sample { UserDefaults.standard.set(extraFails,forKey:"extraFails") }; if !restoring && oldValue != extraFails { invalidate(); if !sample { library.invalidatePolicy(extraFails); save() } } } }
    @Published var filenames = false { didSet { UserDefaults.standard.set(filenames,forKey:"filenames") } }
    @Published var appearance = "System" { didSet { UserDefaults.standard.set(appearance,forKey:"appearance"); NSApplication.shared.appearance = appearance == "System" ? nil : NSAppearance(named: appearance == "Dark" ? .darkAqua : .aqua) } }
    private var restoring = false
    private let storage: URL?
    var token = Cancellation()
    var stateURL: URL { storage ?? URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/HashDock/live.json") }
    init(storage: URL? = nil) { self.storage=storage; load() }
    func load() {
        restoring=true
        defer { restoring=false }
        if FileManager.default.fileExists(atPath:stateURL.path) {
            do {
                let data=try Data(contentsOf:stateURL)
                if let stored=try? JSONDecoder().decode(JobLibrary.self,from:data) { library=stored }
                else { library=JobLibrary(); library.jobs[library.pinned]=try JSONDecoder().decode(Job.self,from:data) }
                library.invalidatePolicy(UserDefaults.standard.bool(forKey:"extraFails"))
                job=library.jobs[library.pinned] ?? Job()
            }
            catch { message="Saved state could not be read. Choose folders again. Original files were not changed." }
        }
        if job.name == "Delivery job" { job.name=L("Delivery job","Entrega") }
        extraFails=UserDefaults.standard.bool(forKey:"extraFails"); filenames=UserDefaults.standard.bool(forKey:"filenames"); appearance=UserDefaults.standard.string(forKey:"appearance") ?? "System"
    }
    func save() {
        guard !sample, !restoring else { return }
        do { try FileManager.default.createDirectory(at:stateURL.deletingLastPathComponent(),withIntermediateDirectories:true); library.jobs[library.pinned]=job; try JSONEncoder().encode(library).write(to:stateURL,options:.atomic) }
        catch { message="Could not save local state. \(error.localizedDescription)" }
    }
    func newJob() { guard !busy, !sample else { return }; save(); library.create(); job=Job(); job.name=L("Delivery job","Entrega"); save() }
    func pin(_ id: String) { guard !busy, !sample, library.jobs[id] != nil else { return }; save(); library.pinned=id; job=library.jobs[id]!; save() }
    func removeRecipient(_ id: UUID) { guard !busy else { return }; job.removeRecipient(id); save() }
    func invalidate() { for i in job.recipients.indices { job.recipients[i].result=nil }; save() }
    func switchSample(_ value: Bool) {
        guard !busy else { return }
        if value { save(); sample=true; resetSample() } else { sample=false; job=Job(); load(); message="Live mode uses only folders you select." }
    }
    func resetSample() {
        guard !busy else { return }
        sample=true
        do {
            let base=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/HashDock/Sample")
            try? FileManager.default.removeItem(at:base)
            for folder in ["Source","Studio","Client"] {
                let dir=base.appendingPathComponent(folder); try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
                try Data("Sample project brief".utf8).write(to:dir.appendingPathComponent("Brief.txt"))
                if folder != "Client" { try Data("Sample delivery notes".utf8).write(to:dir.appendingPathComponent("Notes.txt")) }
            }
            job=Job(); job.name=L("Sample autumn delivery","Entrega de ejemplo de otoño"); job.sampleSource=base.appendingPathComponent("Source").path
            job.manifest=try Engine.freeze(base.appendingPathComponent("Source"))
            for (alias,folder) in [("Studio copy","Studio"),("Client copy","Client"),("Archive copy","Archive")] {
                var r=Recipient(alias:Locale.preferredLanguages.first?.hasPrefix("es") == true ? alias.replacingOccurrences(of:"Studio copy",with:"Copia de estudio").replacingOccurrences(of:"Client copy",with:"Copia del cliente").replacingOccurrences(of:"Archive copy",with:"Copia de archivo") : alias,samplePath:base.appendingPathComponent(folder).path)
                r.result=Engine.verify(base.appendingPathComponent(folder),manifest:job.manifest!,extraFails:extraFails)
                job.recipients.append(r)
            }
            message="Sample fixtures are local. Studio matches, Client is missing a file, Archive is offline."
        } catch { message=L("Sample could not be created. Reset sample to retry.","No se pudo crear el ejemplo. Restablécelo para reintentar.") }
    }
    func choose(source: Bool, recipient: UUID? = nil) {
        guard !busy, !sample else { return }
        // Leave the accessibility action before initializing AppKit's remote folder picker.
        Timer.scheduledTimer(withTimeInterval:0.05,repeats:false) { [weak self] _ in
            MainActor.assumeIsolated { self?.presentSelection(source:source,recipient:recipient) }
        }
    }
    private func presentSelection(source: Bool, recipient: UUID?) {
        guard !busy, !sample else { return }
        let panel=NSOpenPanel(); panel.canChooseDirectories=true; panel.canChooseFiles=false; panel.allowsMultipleSelection=false
        panel.message=source ? L("Select the source folder to freeze its file manifest","Elige la carpeta de origen para crear su manifiesto") : L("Select a recipient folder to verify against the frozen source","Elige una carpeta de destinatario para verificarla contra el origen")
        guard panel.runModal() == .OK, let url=panel.url else { return }
        do {
            let data=try url.bookmarkData(options:[.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys:[.pathKey,.volumeURLKey],relativeTo:nil)
            if source { job.source=data; job.sourceName=url.lastPathComponent; job.manifest=nil; invalidate() }
            else if let recipient, let i=job.recipients.firstIndex(where:{$0.id == recipient}) { job.recipients[i].savedPath=url.path; job.recipients[i].bookmark=data; job.recipients[i].result=nil; job.recipients[i].staleReason=nil }
            else { var r=Recipient(alias:L("Recipient ","Destinatario ")+String(job.recipients.count+1),bookmark:data); r.savedPath=url.path; job.recipients.append(r) }
            save(); message=source ? "Source selected. Freeze a manifest before verifying." : "Recipient selected. Edit its alias in Settings."
        } catch { message="Permission unavailable. Choose again. \(error.localizedDescription)" }
    }
    func resolve(_ bookmark: Data?, path: String?) throws -> URL {
        if sample, let path { return URL(fileURLWithPath:path) }
        guard let bookmark else { throw ScanError.unavailable }
        var stale=false
        let url=try URL(resolvingBookmarkData:bookmark,options:[.withSecurityScope,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale)
        if stale { throw NSError(domain:"HashDock",code:1,userInfo:[NSLocalizedDescriptionKey:"Saved permission is stale. Choose again. Previous results are historical."]) }
        return url
    }
    func refresh() {
        guard !busy else { return }
        // Invalidate even when the attempted refresh fails. Old results must not look current.
        job.manifest=nil; invalidate()
        do {
            let root=try resolve(job.source,path:job.sampleSource); let access=root.startAccessingSecurityScopedResource()
            busy=true; token=Cancellation(); let cancel=token
            Task { let outcome = await Task.detached { () -> Result<Manifest,Error> in
                defer { if access { root.stopAccessingSecurityScopedResource() } }
                return Result { try Engine.freeze(root,token:cancel,progress:{ path in Task { @MainActor in self.progress=Locale.preferredLanguages.first?.hasPrefix("es") == true ? path.replacingOccurrences(of:" of ",with:" de ").replacingOccurrences(of:" files",with:" archivos") : path } }) }
            }.value
                busy=false; progress=""
                switch outcome { case .success(let manifest): job.refresh(manifest); message="Frozen manifest ready. Every recipient needs verification."
                case .failure(let error):
                    if let empty=error as? EmptySourceFailure { message=L("No readable source files. Excluded or unreadable paths · ","Sin archivos de origen legibles. Rutas omitidas o ilegibles · ")+empty.warnings.map { localizedWarning($0) }.joined(separator:", ") }
                    else { message=L("Manifest incomplete. No readable files or scan cancelled. Review the source and try again.","Manifiesto incompleto. Sin archivos legibles o lectura cancelada. Revisa el origen e inténtalo otra vez.") } }
                save()
            }
        } catch { message="Source unavailable. Choose again. \(error.localizedDescription)" }
    }
    func verifyAll() { guard !busy, job.manifest != nil else { return }; token=Cancellation(); verifyQueue=job.recipients.map(\.id); nextVerification() }
    private func nextVerification() { guard !verifyQueue.isEmpty, !token.cancelled else { verifyQueue=[]; return }; verify(verifyQueue.removeFirst()) }
    func verify(_ id: UUID) {
        guard !busy, let manifest=job.manifest, let index=job.recipients.firstIndex(where:{$0.id == id}) else { return }
        let recipient=job.recipients[index]
        do {
            let root=try resolve(recipient.bookmark,path:recipient.samplePath); let access=root.startAccessingSecurityScopedResource()
            busy=true; token=Cancellation(); let cancel=token; let policy=extraFails
            var pending=Verification(revision:manifest.id); pending.interrupted=true; job.recipients[index].result=pending; save()
            Task { let result=await Task.detached {
                defer { if access { root.stopAccessingSecurityScopedResource() } }
                return Engine.verify(root,manifest:manifest,extraFails:policy,token:cancel,progress:{path in Task { @MainActor in self.progress=Locale.preferredLanguages.first?.hasPrefix("es") == true ? path.replacingOccurrences(of:" of ",with:" de ").replacingOccurrences(of:" files",with:" archivos") : path }})
            }.value
                if let i=job.recipients.firstIndex(where:{$0.id == id}) { job.recipients[i].result=result; job.recipients[i].staleReason=nil }
                busy=false; progress=""; message="\(recipient.alias) · \(D(result.status))"; save(); nextVerification()
            }
        } catch {
            let values=recipient.bookmark.flatMap { NSURL.resourceValues(forKeys:[.pathKey,.volumeURLKey],fromBookmarkData:$0) }
            let saved=recipient.savedPath ?? values?[.pathKey] as? String
            let volume=(values?[.volumeURLKey] as? URL)?.path
            let mounted=FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:nil,options:[])?.map(\.path)
            if let path=saved, VolumePresence.offline(path:path,volume:volume,mounted:mounted,stalePermission:(error as NSError).domain == "HashDock" && (error as NSError).code == 1) {
                var result=Verification(revision:manifest.id); result.offline=true; result.extraFails=extraFails
                job.recipients[index].result=result; job.recipients[index].staleReason=nil
                message=L("Recipient offline. Reconnect its drive and verify again.","Destinatario sin conexión. Conecta su unidad y verifica otra vez.")
            } else { job.recipients[index].staleReason=L("Saved permission unavailable. Choose again. Previous result is stale.","Permiso no disponible. Elige otra vez. El resultado anterior está desactualizado."); message=job.recipients[index].staleReason! }
            save(); nextVerification()
        }
    }
    func copyReceipt() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(job.receipt(sample:sample,filenames:filenames,spanish:Locale.preferredLanguages.first?.hasPrefix("es") == true),forType:.string); message="Receipt copied. It includes verification times and coverage." }
    func forget() {
        guard !busy else { return }
        do {
            let directory=stateURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath:directory.path) { try FileManager.default.removeItem(at:directory) }
            job=Job(); library=JobLibrary(); sample=false; verifyQueue=[]
            if let identifier=Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName:identifier) }
            extraFails=false; filenames=false; appearance="System"; HotKey.shared.register(4)
            message="Local job and saved permissions cleared. Input files are unchanged."
        } catch { message="Could not clear local data. \(error.localizedDescription)" }
    }
    var menuTitle: String {
        let prefix=sample ? "S " : ""
        if busy { return prefix+D("Checking…") }
        let pending=job.recipients.filter { $0.staleReason != nil || $0.result?.current(job.manifest) != true || !["Verified","Verified with extras"].contains($0.result?.status ?? "") }.count
        guard !job.recipients.isEmpty else { return prefix+D("No inputs") }
        let last=job.recipients.compactMap { $0.result?.completed }.max()?.formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier:Locale.preferredLanguages.first ?? "en"))) ?? L("no completed check","sin comprobación completada")
        return prefix+(pending == 0 ? D("All checked") : L("\(pending) pending", "\(pending) pendientes"))+" · \(last)"
    }
    var symbol: String {
        if busy { return "externaldrive.badge.timemachine" }
        if job.recipients.isEmpty { return "externaldrive" }
        if job.recipients.contains(where: { $0.staleReason != nil || $0.result?.current(job.manifest) != true || ["Offline","Incomplete"].contains($0.result?.status ?? "") }) { return "externaldrive.badge.questionmark" }
        return job.recipients.allSatisfy { ["Verified","Verified with extras"].contains($0.result?.status ?? "") } ? "externaldrive.badge.checkmark" : "externaldrive.badge.exclamationmark"
    }
}
