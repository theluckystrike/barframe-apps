import Foundation
import Darwin

/// Directory events compare visible names rather than file contents.
final class InputMonitor {
    struct Observation { let complete: Bool; let watched: Int }
    static let directoryLimit = 128
    private var sources: [DispatchSourceFileSystemObject] = []
    func stop() { for source in sources { source.cancel() }; sources = [] }
    static func fingerprint(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).map { WeaveName.identity($0.lastPathComponent) }.sorted()
    }
    static func namesChanged(_ directory: URL, since names: [String]) -> Bool {
        guard let current = try? fingerprint(directory) else { return true }
        return current != names
    }
    static func isLimited(_ count: Int, watched: Int) -> Bool { count > directoryLimit || watched < count + 1 }
    func watch(_ root: URL, relativeDirectories: [String], changed: @escaping @Sendable () -> Void) -> Observation {
        stop()
        let granted = root.startAccessingSecurityScopedResource()
        defer { if granted { root.stopAccessingSecurityScopedResource() } }
        guard granted else { return Observation(complete: false, watched: 0) }
        let urls = [root] + relativeDirectories.prefix(Self.directoryLimit).map { root.appendingPathComponent($0, isDirectory: true) }
        var snapshotsComplete = true
        for url in urls {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let names = try? Self.fingerprint(url)
            if names == nil { snapshotsComplete = false }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .revoke], queue: .global(qos: .utility))
            source.setEventHandler {
                if names == nil || Self.namesChanged(url, since: names ?? []) { changed() }
            }
            source.setCancelHandler { close(descriptor) }
            sources.append(source); source.resume()
        }
        return Observation(complete: snapshotsComplete && !Self.isLimited(relativeDirectories.count, watched: sources.count), watched: sources.count)
    }
    deinit { stop() }
}
// Preserve exact Unicode names when deciding whether the audited tree changed.
private enum WeaveName {
    static func identity(_ value: String) -> String { value.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ",") }
}
