import Foundation
import CryptoKit
import Darwin

public struct Entry: Codable, Equatable, Sendable {
    public var path: String
    public var bytes: UInt64
    public var digest: String
    public init(path: String, bytes: UInt64, digest: String) { self.path=path; self.bytes=bytes; self.digest=digest }
}
public struct Manifest: Codable, Sendable {
    public var id = UUID().uuidString
    public var created = Date()
    public var entries: [Entry]
    public var warnings: [String]
    public init(entries: [Entry], warnings: [String] = []) { self.entries=entries; self.warnings=warnings }
}
public struct Verification: Codable, Sendable {
    public var revision: String
    public var date = Date()
    public var completed: Date?
    public var warnings: [String]?
    public var verified = 0
    public var missing: [String] = []
    public var changed: [String] = []
    public var extra: [String] = []
    public var unreadable: [String] = []
    public var interrupted = false
    public var offline = false
    public var extraFails = false
    public var status: String {
        if offline { return "Offline" }
        if interrupted || !unreadable.isEmpty { return "Incomplete" }
        if !missing.isEmpty || !changed.isEmpty || (extraFails && !extra.isEmpty) { return "Findings" }
        return extra.isEmpty ? "Verified" : "Verified with extras"
    }
    public init(revision: String) { self.revision=revision }
    public func current(_ manifest: Manifest?) -> Bool { manifest?.id == revision }
}
public enum ScanError: Error { case cancelled, changed, unsafePath, unavailable, emptyManifest }
public struct EmptySourceFailure: Error {
    public var warnings: [String]
    public init(warnings: [String]) { self.warnings=warnings }
}
public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock(); private var flag = false
    public init() {}
    public func cancel() { lock.lock(); flag=true; lock.unlock() }
    public var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
public enum Engine {
    public static func canonicalRoot(_ root: URL) throws -> URL {
        let values = try root.resourceValues(forKeys:[.isSymbolicLinkKey])
        guard values.isSymbolicLink != true, let pointer = realpath(root.path,nil) else { throw ScanError.unsafePath }
        defer { free(pointer) }
        return URL(fileURLWithPath:String(cString:pointer),isDirectory:true)
    }
    public static func safe(_ path: String) -> Bool { !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..") }
    public static func hash(_ url: URL, root: URL? = nil, token: Cancellation = Cancellation(), chunk: () -> Void = {}) throws -> Entry {
        // Open every directory component without following symbolic links. A replaced
        // parent cannot redirect a file read outside the selected directory.
        let base = root ?? url.deletingLastPathComponent()
        let canonical = try canonicalRoot(base).path
        let relative = root == nil ? url.lastPathComponent : String(url.path.dropFirst(base.path.count+1))
        guard safe(relative) else { throw ScanError.unsafePath }
        var directory = Darwin.open(canonical, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw ScanError.unavailable }
        defer { Darwin.close(directory) }
        let components = relative.split(separator:"/").map(String.init)
        for component in components.dropLast() {
            let next = openat(directory,component,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw ScanError.unsafePath }
            Darwin.close(directory); directory=next
        }
        let descriptor = openat(directory,components.last!,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ScanError.unavailable }
        let file=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true)
        defer { try? file.close() }
        var before=stat(); guard fstat(descriptor,&before) == 0, (before.st_mode & S_IFMT) == S_IFREG else { throw ScanError.unsafePath }
        var digest=SHA256(); var count:UInt64=0
        while true {
            if token.cancelled { throw ScanError.cancelled }
            guard let data=try file.read(upToCount:1024*1024), !data.isEmpty else { break }
            digest.update(data:data); count += UInt64(data.count); chunk()
        }
        var after=stat(); var pathAfter=stat()
        guard fstat(descriptor,&after) == 0, fstatat(directory,components.last!,&pathAfter,AT_SYMLINK_NOFOLLOW) == 0,
            before.st_size == after.st_size, after.st_size >= 0, UInt64(after.st_size) == count,
            before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
            before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
            before.st_ino == pathAfter.st_ino, before.st_dev == pathAfter.st_dev else { throw ScanError.changed }
        return Entry(path:url.lastPathComponent,bytes:count,digest:digest.finalize().map { String(format:"%02x",$0) }.joined())
    }
    public static func metadata(_ name: String) -> Bool {
        [".DS_Store", ".Spotlight-V100", ".fseventsd", ".Trashes", "Icon\r"].contains(name) || name.hasPrefix("._")
    }
    public static func files(_ root: URL, token: Cancellation = Cancellation()) throws -> ([(String,URL)],[String]) {
        var files: [(String,URL)] = []; var warnings: [String] = []
        // Descriptor traversal includes AppleDouble sidecars that Foundation's enumerator hides.
        // Every directory is opened without following a replaced symbolic link.
        func walk(_ descriptor: Int32, _ prefix: String) throws {
            guard let directory=fdopendir(descriptor) else { Darwin.close(descriptor); warnings.append("Unreadable · " + prefix); return }
            defer { closedir(directory) }
            while true {
                errno=0
                guard let entry=readdir(directory) else { if errno != 0 { warnings.append("Unreadable · " + (prefix.isEmpty ? "." : prefix)) }; break }
                if token.cancelled { throw ScanError.cancelled }
                let name=withUnsafePointer(to:&entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to:CChar.self,capacity:MemoryLayout.size(ofValue:entry.pointee.d_name)) { String(cString:$0) }
                }
                if name == "." || name == ".." { continue }
                let path=prefix.isEmpty ? name : prefix + "/" + name
                if metadata(name) { warnings.append("Skipped metadata · " + path); continue }
                var info=stat()
                guard fstatat(descriptor,name,&info,AT_SYMLINK_NOFOLLOW) == 0 else { warnings.append("Unreadable · " + path); continue }
                let kind=info.st_mode & S_IFMT
                if kind == S_IFLNK { warnings.append(path) }
                else if kind == S_IFDIR {
                    let child=openat(descriptor,name,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    if child < 0 { warnings.append("Unreadable · " + path) } else { try walk(child,path) }
                } else if kind == S_IFREG { files.append((path,root.appendingPathComponent(path))) }
            }
        }
        let descriptor=Darwin.open(root.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ScanError.unavailable }
        try walk(descriptor,"")
        return (files.sorted { $0.0 < $1.0 },warnings.sorted())
    }
    public static func freeze(_ root: URL, token: Cancellation = Cancellation(), progress: (String) -> Void = {_ in}) throws -> Manifest {
        let root = try canonicalRoot(root)
        let (files,initial)=try files(root,token:token); var warnings=initial; var entries: [Entry]=[]
        for (index,item) in files.enumerated() {
            let (path,url)=item; progress("\(index+1) of \(files.count) files · \(path)")
            do { var entry=try hash(url,root:root,token:token); entry.path=path; entries.append(entry) }
            catch ScanError.cancelled { throw ScanError.cancelled }
            catch { warnings.append("Unreadable · " + path) }
        }
        if token.cancelled { throw ScanError.cancelled }
        guard !entries.isEmpty else { if !warnings.isEmpty { throw EmptySourceFailure(warnings:warnings) }; throw ScanError.emptyManifest }
        return Manifest(entries:entries,warnings:warnings)
    }
    public static func verify(_ root: URL, manifest: Manifest, extraFails: Bool = false, token: Cancellation = Cancellation(), progress: (String) -> Void = {_ in}) -> Verification {
        var result=Verification(revision:manifest.id); result.extraFails=extraFails
        var rootInfo=stat()
        if lstat(root.path,&rootInfo) != 0 {
            if errno == ENOENT || errno == ENOTDIR { result.offline=true }
            else { result.unreadable=["Folder access denied. Choose again."] }
            return result
        }
        do {
            let root = try canonicalRoot(root)
            let (list,links)=try files(root,token:token); let paths=Set(list.map { $0.0 }); let expected=Set(manifest.entries.map(\.path))
            result.extra=Array(paths.subtracting(expected)).sorted()
            result.warnings=links.filter { $0.hasPrefix("Skipped metadata · ") }
            result.unreadable=links.filter { !$0.hasPrefix("Skipped metadata · ") }
            result.unreadable += manifest.warnings.filter { $0.hasPrefix("Unreadable · ") }
            if manifest.entries.isEmpty { result.unreadable.append("Empty source manifest") }
            for (index,entry) in manifest.entries.enumerated() {
                if token.cancelled { result.interrupted=true; break }
                progress("\(index+1) of \(manifest.entries.count) files · \(entry.path)")
                guard safe(entry.path) else { result.unreadable.append(entry.path); continue }
                guard paths.contains(entry.path) else { if !links.contains(entry.path) { result.missing.append(entry.path) }; continue }
                do { let actual=try hash(root.appendingPathComponent(entry.path),root:root,token:token)
                    if actual.digest == entry.digest && actual.bytes == entry.bytes { result.verified += 1 } else { result.changed.append(entry.path) }
                } catch ScanError.cancelled { result.interrupted=true; break } catch { result.unreadable.append(entry.path) }
            }
        } catch { result.unreadable.append("Folder access denied or scan failed") }
        if token.cancelled { result.interrupted=true }
        if !result.interrupted { result.completed=Date() }
        return result
    }
}
public struct Recipient: Codable, Identifiable {
    public var savedPath: String?
    public var id = UUID(); public var alias: String; public var bookmark: Data?; public var samplePath: String?; public var result: Verification?; public var staleReason: String?
    public init(alias: String, bookmark: Data? = nil, samplePath: String? = nil) { self.alias=alias; self.bookmark=bookmark; self.samplePath=samplePath }
}
public struct Job: Codable {
    public var name = "Delivery job"; public var sourceName: String?; public var source: Data?; public var sampleSource: String?; public var manifest: Manifest?; public var recipients: [Recipient] = []
    public init() {}
    public mutating func refresh(_ value: Manifest) { manifest=value; for i in recipients.indices { recipients[i].result=nil } }
    public mutating func removeRecipient(_ id: UUID) { recipients.removeAll { $0.id == id } }
    public func receipt(sample: Bool, filenames: Bool, spanish: Bool = false) -> String {
        func t(_ en: String,_ es: String) -> String { spanish ? es : en }
        func date(_ value: Date?) -> String { value?.formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier:spanish ? "es" : "en"))) ?? t("unavailable","no disponible") }
        var lines=[sample ? t("Sample delivery receipt","Recibo de entrega de ejemplo") : t("Delivery receipt","Recibo de entrega"), name, t("Manifest ","Manifiesto ") + (manifest?.id ?? t("none","ninguno")), t("Frozen ","Creado ") + date(manifest?.created)]
        for r in recipients {
            guard r.staleReason == nil, let v=r.result, v.current(manifest) else { lines.append(r.alias + " · " + t("Needs verification","Necesita verificación")); continue }
            let states=["Verified":"Verificado","Verified with extras":"Verificado con extras","Findings":"Diferencias","Offline":"Sin conexión","Incomplete":"Incompleto"]
            lines.append("\(r.alias) · \(spanish ? states[v.status] ?? v.status : v.status) · " + (v.interrupted ? t("Interrupted","Interrumpido") : (v.completed.map { t("Completed ","Completado ")+date($0) } ?? t("Check unavailable","Comprobación no disponible"))) + " · \(v.verified) " + t("of","de") + " \(manifest?.entries.count ?? 0) · " + t("missing","ausentes") + " \(v.missing.count) · " + t("changed","modificados") + " \(v.changed.count) · " + t("extras","extra") + " \(v.extra.count) · " + t("unreadable","ilegibles") + " \(v.unreadable.count)")
            if filenames {
                lines += v.missing.map { t("Missing ","Ausente ")+$0 } + v.changed.map { t("Changed ","Modificado ")+$0 } + v.extra.map { t("Extra ","Extra ")+$0 } + v.unreadable.map { t("Unreadable ","Ilegible ")+Diagnostics.localized($0,spanish:spanish) }
                lines += (v.warnings ?? []).map { Diagnostics.localized($0,spanish:spanish) }
            }
        }
        return lines.joined(separator:"\n")
    }
}

public struct JobLibrary: Codable {
    public var pinned = UUID().uuidString
    public var jobs: [String:Job] = [:]
    public init() { jobs[pinned]=Job() }
    public mutating func create() { pinned=UUID().uuidString; jobs[pinned]=Job() }
    public mutating func invalidatePolicy(_ policy: Bool) {
        for key in Array(jobs.keys) {
            guard var job=jobs[key] else { continue }
            for i in job.recipients.indices where job.recipients[i].result?.extraFails != policy { job.recipients[i].result=nil }
            jobs[key]=job
        }
    }
}

public enum PolicyLink {
    public static func webURL(_ raw: String?, path: String? = nil) -> URL? {
        guard let raw, !raw.contains("{"), !raw.contains("}"), let url=URL(string:raw), url.scheme == "https", url.host != nil else { return nil }
        func route(_ value: String) -> String { value != "/" && value.hasSuffix("/") ? String(value.dropLast()) : value }
        guard path == nil || route(url.path) == route(path!) else { return nil }
        return url
    }
}

public enum Diagnostics {
    public static func localized(_ value: String, spanish: Bool) -> String {
        guard spanish else { return value }
        switch value {
        case "Folder access denied. Choose again.": return "Acceso a la carpeta denegado. Elige otra vez."
        case "Folder access denied or scan failed": return "Acceso a la carpeta denegado o lectura fallida"
        case "Empty source manifest": return "Manifiesto de origen vacío"
        default:
            if value.hasPrefix("Skipped metadata · ") { return "Metadatos omitidos · " + value.dropFirst("Skipped metadata · ".count) }
            if value.hasPrefix("Unreadable · ") { return "Ilegible · " + value.dropFirst("Unreadable · ".count) }
            return value
        }
    }
}

public enum VolumePresence {
    public static func offline(path: String, volume: String?, mounted: [String]?, stalePermission: Bool = false) -> Bool {
        guard !stalePermission, let mounted, !mounted.isEmpty else { return false }
        let root: String
        if let volume { root=volume }
        else {
            let components=path.split(separator:"/")
            guard components.count >= 2, components[0] == "Volumes" else { return false }
            root="/Volumes/" + components[1]
        }
        func normalized(_ path: String) -> String { URL(fileURLWithPath:path,isDirectory:true).standardizedFileURL.path }
        return !mounted.map(normalized).contains(normalized(root))
    }
}
