import Foundation

public struct Entry: Codable, Hashable, Identifiable, Sendable {
    public var path: String
    public var directory: Bool
    public var id: String { Weave.identity(path) }
    public init(_ path: String, directory: Bool = false) { self.path = path; self.directory = directory }
    public var name: String { String(path.split(separator: "/", omittingEmptySubsequences: false).last ?? "") }
    public var parent: String { path.split(separator: "/", omittingEmptySubsequences: false).dropLast().joined(separator: "/") }
}
public struct Policy: Codable, Equatable, Sendable {
    public var prefix = ""
    public var legacyBudget: Int? = nil
    public var normalize = true
    public var exclusions: [String] = []
    public init() {}
}
public struct Coverage: Codable, Equatable, Sendable {
    public var omissions: [String] = []
    public var cancelled = false
    public var complete: Bool { omissions.isEmpty && !cancelled }
    public init() {}
}
public struct Scan: Codable, Sendable {
    public var entries: [Entry]
    public var coverage: Coverage
    public init(entries: [Entry], coverage: Coverage = Coverage()) { self.entries = entries; self.coverage = coverage }
}
public struct Row: Identifiable, Sendable {
    public var entry: Entry
    public var proposed: String
    public var originalReasons: [String]
    public var unresolved: [String]
    public var length: Int
    public var id: String { entry.id }
}
public struct Plan: Sendable {
    public var rows: [Row]
    public var coverage: Coverage
    public var ready: Bool { coverage.complete && rows.allSatisfy { $0.unresolved.isEmpty } }
    public var issueCount: Int { rows.filter { !$0.originalReasons.isEmpty }.count }
    public var unresolvedCount: Int { rows.filter { !$0.unresolved.isEmpty }.count }
    public func report(sample: Bool, stale: Bool = false, policy: Policy = Policy()) -> String {
        var lines = [sample ? "Sample NameWeave plan" : "NameWeave plan", "Windows conservative compatibility profile", "Case insensitive comparison and optional canonical Unicode normalization", "Destination prefix " + (policy.prefix.isEmpty ? "none" : policy.prefix), "Legacy UTF16 path budget " + (policy.legacyBudget.map(String.init) ?? "off"), stale ? "Stale result requires rescan" : ready ? "Ready" : "Unresolved or incomplete", "Source files remain unchanged"]
        for row in rows {
            lines += [row.entry.path + " → " + row.proposed,
                      "Reasons " + (row.originalReasons.isEmpty ? "clear" : row.originalReasons.joined(separator: ", ")),
                      "Unresolved " + (row.unresolved.isEmpty ? "none" : row.unresolved.joined(separator: ", ")) + " | target UTF16 length \(row.length)"]
        }
        lines += coverage.omissions.map { "Incomplete " + $0 }
        if coverage.cancelled { lines.append("Incomplete scan cancelled") }
        return lines.joined(separator: "\n")
    }
}
public enum Weave {
    public static func identity(_ value: String) -> String { "id:" + value.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ",") }
    public static let source = "https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file"
    public static func key(_ value: String, normalize: Bool = true) -> String {
        let canonical = normalize ? value.precomposedStringWithCanonicalMapping : value
        return canonical.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ",")
    }
    public static func reasons(_ name: String) -> [String] {
        var reasons: [String] = []
        if name.isEmpty || name == "." || name == ".." { reasons.append("Empty or navigation component") }
        if name.unicodeScalars.contains(where: { $0.value < 32 || "<>:\"/\\|?*".unicodeScalars.contains($0) }) { reasons.append("Restricted character") }
        if name.last == "." || name.last == " " { reasons.append("Trailing dot or space") }
        let stem = String(name.split(separator: ".", omittingEmptySubsequences: false).first ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        let reserved = ["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] } + ["COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³"]
        if reserved.contains(stem) { reasons.append("Reserved device stem") }
        if name.utf16.count > 255 { reasons.append("Component UTF16 budget exceeded") }
        return reasons
    }
    public static func sanitize(_ name: String) -> String {
        if reasons(name).isEmpty { return name }
        var result = String(String.UnicodeScalarView(name.unicodeScalars.map { scalar in
            scalar.value < 32 || "<>:\"/\\|?*".unicodeScalars.contains(scalar) ? UnicodeScalar(95)! : scalar
        }))
        while result.last == "." || result.last == " " { result.removeLast() }
        if result.isEmpty || result == "." || result == ".." { result = "untitled" }
        if reasons(result).contains("Reserved device stem") { result = "_" + result }
        while result.utf16.count > 245 { result.removeLast() }
        return result
    }
    public static func virtual(_ entry: Entry, edits: [String: String]) -> String {
        let components = entry.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return components.indices.map { index in
            edits[identity(components.prefix(index + 1).joined(separator: "/"))] ?? edits[components.prefix(index + 1).joined(separator: "/")] ?? components[index]
        }.joined(separator: "/")
    }
    public static func targetLength(_ path: String, policy: Policy) -> Int {
        var prefix = policy.prefix
        while prefix.last == "\\" || prefix.last == "/" { prefix.removeLast() }
        return (prefix.isEmpty ? path : prefix + "\\" + path.replacingOccurrences(of: "/", with: "\\")).utf16.count
    }
    public static func plan(_ scan: Scan, policy: Policy, edits: [String: String]) -> Plan {
        var rows = scan.entries.map { entry -> Row in
            let path = virtual(entry, edits: edits)
            var original = reasons(entry.name)
            var unresolved = reasons(edits[entry.id] ?? edits[entry.path] ?? entry.name)
            let length = targetLength(path, policy: policy)
            if let budget = policy.legacyBudget, length > budget { unresolved.append("Legacy target budget exceeded") }
            if let budget = policy.legacyBudget, targetLength(entry.path, policy: policy) > budget { original.append("Legacy target budget exceeded") }
            return Row(entry: entry, proposed: path, originalReasons: original, unresolved: unresolved, length: length)
        }
        let originalGroups = Dictionary(grouping: rows.indices, by: { key(rows[$0].entry.path, normalize: policy.normalize) })
        for group in originalGroups.values where group.count > 1 {
            for i in group { rows[i].originalReasons.append("Case or Unicode portability collision") }
        }
        let groups = Dictionary(grouping: rows.indices, by: { key(rows[$0].proposed, normalize: policy.normalize) })
        for group in groups.values where group.count > 1 {
            for i in group { rows[i].unresolved.append("Virtual destination collision") }
        }
        // A changed parent must also be valid before any child can be ready.
        for i in rows.indices {
            let components = rows[i].entry.path.split(separator: "/").map(String.init)
            for depth in 1..<max(1, components.count) {
                let ancestor = components.prefix(depth).joined(separator: "/")
                if let edit = edits[identity(ancestor)] ?? edits[ancestor], !reasons(edit).isEmpty { rows[i].unresolved.append("Invalid parent replacement") }
            }
        }
        return Plan(rows: rows, coverage: scan.coverage)
    }
    public static func suggestions(_ scan: Scan) -> [String: String] {
        Dictionary(uniqueKeysWithValues: scan.entries.compactMap { entry in
            let candidate = sanitize(entry.name)
            return candidate == entry.name ? nil : (entry.id, candidate)
        })
    }
    public static func resolve(_ scan: Scan, policy: Policy, edits: [String: String]) -> [String: String] {
        var result = edits
        // Keep valid unchanged names before allocating repaired candidates.
        for group in Dictionary(grouping: scan.entries, by: \.parent).values {
            var used = Set<String>()
            let ordered = group.sorted { a, b in
                let aUnchanged = (result[a.id] ?? result[a.path] ?? a.name) == a.name && reasons(a.name).isEmpty
                let bUnchanged = (result[b.id] ?? result[b.path] ?? b.name) == b.name && reasons(b.name).isEmpty
                return aUnchanged != bUnchanged ? aUnchanged : a.path < b.path
            }
            for entry in ordered {
                let base = sanitize(result[entry.id] ?? result[entry.path] ?? entry.name)
                var name = base
                var index = 2
                while used.contains(key(name, normalize: policy.normalize)) {
                    let ext = (base as NSString).pathExtension
                    var stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
                    let suffix = "_\(index)" + (ext.isEmpty ? "" : "." + ext)
                    while (stem + suffix).utf16.count > 255 && !stem.isEmpty { stem.removeLast() }
                    name = stem + suffix
                    index += 1
                }
                used.insert(key(name, normalize: policy.normalize))
                result.removeValue(forKey: entry.path)
                if name != entry.name { result[entry.id] = name } else { result.removeValue(forKey: entry.id) }
            }
        }
        return result
    }
    public static func mergingEdits(_ saved: [String: String], into scan: Scan) -> [String: String] {
        var result = suggestions(scan)
        for entry in scan.entries {
            if let value = saved[entry.id] ?? saved[entry.path] { result[entry.id] = value }
        }
        return result
    }
    public static func applyingExclusions(_ policy: Policy, to scan: Scan) -> Scan {
        var result = scan
        let excluded = scan.entries.filter { $0.directory && policy.exclusions.contains($0.path) }.map(\.path)
        result.entries.removeAll { entry in excluded.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") } }
        result.coverage.omissions += excluded.map { "Excluded directory " + $0 }
        return result
    }
    public static let sample = Scan(entries: [Entry("report?.txt"), Entry("report*.txt"), Entry("AUX.txt"), Entry("Readme.md"), Entry("README.md"), Entry("Design.", directory: true), Entry("Design./final?.pdf"), Entry("notes.txt"), Entry("archive", directory: true), Entry("archive/brief.txt")])
}
public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    public func cancel() { lock.lock(); flag = true; lock.unlock() }
}
public enum Scanner {
    public static func scan(_ root: URL, policy: Policy, limit: Int = 20_000, cancellation: ScanCancellation = ScanCancellation()) -> Scan {
        var entries: [Entry] = []
        var coverage = Coverage()
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            coverage.omissions = ["Root unavailable or permission denied"]
            return Scan(entries: [], coverage: coverage)
        }
        if (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            coverage.omissions = ["Unsupported symbolic link root"]
            return Scan(entries: [], coverage: coverage)
        }
        var pending: [(URL, String)] = [(root, "")]
        while let (directory, prefix) = pending.popLast() {
            if cancellation.cancelled { coverage.cancelled = true; break }
            do {
                let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles])
                for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if cancellation.cancelled { coverage.cancelled = true; break }
                    if entries.count >= limit { coverage.omissions.append("Scan limit reached at " + prefix); pending = []; break }
                    let relative = prefix.isEmpty ? url.lastPathComponent : prefix + "/" + url.lastPathComponent
                    do {
                        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                        if values.isSymbolicLink == true { coverage.omissions.append("Unsupported symbolic link " + relative); continue }
                        if values.isDirectory == true && policy.exclusions.contains(relative) { coverage.omissions.append("Excluded directory " + relative); continue }
                        entries.append(Entry(relative, directory: values.isDirectory == true))
                        if values.isDirectory == true && url.lastPathComponent == "node_modules" { coverage.omissions.append("Dependency directory contents skipped " + relative) }
                        else if values.isDirectory == true && values.isPackage != true { pending.append((url, relative)) }
                    } catch { coverage.omissions.append("Inaccessible " + relative + " " + error.localizedDescription) }
                }
            } catch { coverage.omissions.append("Inaccessible " + (prefix.isEmpty ? "selected root" : prefix) + " " + error.localizedDescription) }
        }
        return Scan(entries: entries.sorted(by: { $0.path < $1.path }), coverage: coverage)
    }
}
public struct SavedState: Codable {
    public var bookmark: Data?
    public var rootLabel = ""
    public var policy = Policy()
    public var scan: Scan?
    public var edits: [String: String] = [:]
    public var checkedAt: Date?
    public init() {}
}
public enum StateStore {
    public static func load(_ url: URL) throws -> SavedState { try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url)) }
    public static func save(_ state: SavedState, to url: URL) throws { try JSONEncoder().encode(state).write(to: url, options: .atomic) }
}
