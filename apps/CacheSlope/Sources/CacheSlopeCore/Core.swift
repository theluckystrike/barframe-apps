import Foundation

public struct Snapshot: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var sizes: [String: Int64]
    public var issues: [String]
    public var cancelled: Bool
    public var complete: Bool { issues.isEmpty && !cancelled }
    public var total: Int64 { sizes.values.reduce(0, +) }
    public init(sizes: [String: Int64], issues: [String] = [], cancelled: Bool = false) { self.sizes = sizes; self.issues = issues; self.cancelled = cancelled }
}
public struct Change: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let bytes: Int64
    public let delta: Int64
}
public enum Analysis {
    public static func compare(_ current: Snapshot, to baseline: Snapshot?) -> [Change] {
        guard current.complete, let baseline, baseline.complete else { return [] }
        return Set(current.sizes.keys).union(baseline.sizes.keys).map {
            Change(name: $0, bytes: current.sizes[$0, default: 0], delta: current.sizes[$0, default: 0] - baseline.sizes[$0, default: 0])
        }.sorted { $0.delta == $1.delta ? $0.name < $1.name : $0.delta > $1.delta }
    }
    public static func pair(_ history: [Snapshot], pinned: Snapshot?) -> (Snapshot?, Snapshot?) {
        let good = history.filter(\.complete)
        return (good.last, pinned?.complete == true && pinned?.id != good.last?.id ? pinned : good.dropLast().last)
    }
    public static func retain(_ history: [Snapshot], limit: Int) -> [Snapshot] { Array(history.suffix(max(2, limit))) }
    public static func attention(_ changes: [Change], threshold: Int64) -> Bool { threshold > 0 && changes.contains { $0.delta > threshold } }
    public static func bookmarkNeedsRecovery(stale: Bool, access: Bool) -> Bool { stale || !access }
    public static func report(_ changes: [Change]) -> String { "Logical file bytes\n" + changes.map { "\($0.name)  \($0.bytes)  \($0.delta >= 0 ? "+" : "")\($0.delta)" }.joined(separator: "\n") }
}
public enum Scanner {
    public static func scan(_ root: URL, cancelled: @Sendable () -> Bool = { false }) -> Snapshot {
        let fm = FileManager.default
        if cancelled() { return Snapshot(sizes: [:], cancelled: true) }
        do {
            let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { return Snapshot(sizes: [:], issues: ["Choose folder again"]) }
        } catch { return Snapshot(sizes: [:], issues: ["Permission unavailable"]) }
        let scanRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var sizes: [String: Int64] = [:]; var issues: [String] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let enumerator = fm.enumerator(at: scanRoot, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { url, _ in issues.append(url.lastPathComponent + " · Permission unavailable"); return true }) else { return Snapshot(sizes: [:], issues: ["Permission unavailable"]) }
        for case let url as URL in enumerator {
            if cancelled() { return Snapshot(sizes: sizes, issues: issues, cancelled: true) }
            do {
                let v = try url.resourceValues(forKeys: keys)
                if v.isSymbolicLink == true { enumerator.skipDescendants(); issues.append(url.lastPathComponent + " · Symbolic link skipped"); continue }
                if v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus != .current { enumerator.skipDescendants(); issues.append(url.lastPathComponent + " · Cloud item skipped"); continue }
                // Enumerator depth avoids /var and /private/var alias spelling differences.
                let parts = url.pathComponents.suffix(enumerator.level)
                guard let first = parts.first else { continue }
                if v.isDirectory == true && parts.count == 1 { sizes[String(first), default: 0] += 0 }
                if v.isRegularFile == true {
                    guard let size = v.fileSize else { issues.append(url.lastPathComponent + " · Size unavailable"); continue }
                    sizes[parts.count == 1 ? "Files in root" : String(first), default: 0] += Int64(size)
                }
            } catch { issues.append(url.lastPathComponent + " · Permission unavailable") }
        }
        return Snapshot(sizes: sizes, issues: issues)
    }
}
public enum Fixtures {
    public static var history: [Snapshot] { var values = [Snapshot(sizes: ["Dependencies": 800_000_000, "Previews": 500_000_000, "Build output": 200_000_000]), Snapshot(sizes: ["Dependencies": 1_700_000_000, "Previews": 300_000_000, "Build output": 650_000_000])]; values[0].date = Date().addingTimeInterval(-3600); return values }
    public static var partial: Snapshot { Snapshot(sizes: ["Textures": 420_000_000], issues: ["Source assets · Permission unavailable"]) }
}
