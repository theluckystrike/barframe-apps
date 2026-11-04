import Foundation
import CoreFoundation

public struct Snapshot: Codable, Equatable, Sendable {
    public var identity: String
    public var version: String
    public var team: String
    public var declarations: [String: String]
    public init(identity: String, version: String, team: String, declarations: [String: String]) {
        self.identity = identity; self.version = version; self.team = team; self.declarations = declarations
    }
    public var fields: [String:String] { declarations.merging(["Bundle identity": identity, "Version": version, "Signing team": team]) { _, b in b } }
    public var sandboxed: Bool { declarations["com.apple.security.app-sandbox"] == "true" }
    public var networkExplanation: String {
        if !sandboxed { return "Sandbox not declared. Effective network access is unknown." }
        return declarations["com.apple.security.network.client"] == "true" ? "Outgoing network declared. Actual traffic is unknown." : "Outgoing network not declared. Complete effective access is unknown."
    }
}
public struct Change: Identifiable, Equatable, Sendable {
    public var key: String; public var before: String?; public var after: String?
    public var id: String { key }
    public var kind: String { before == nil ? "Added" : after == nil ? "Removed" : "Changed" }
}
public enum Compare {
    public static func changes(_ baseline: Snapshot, _ current: Snapshot) -> [Change] {
        let a = baseline.fields, b = current.fields
        return Set(a.keys).union(b.keys).sorted().compactMap { a[$0] == b[$0] ? nil : Change(key: $0, before: a[$0], after: b[$0]) }
    }
    private static func quoted(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
    public static func normalize(_ value: Any) -> String {
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if let d = value as? [String:Any] { return "{" + d.keys.sorted().map { "\(quoted($0))=\(normalize(d[$0]!))" }.joined(separator: ", ") + "}" }
        if let a = value as? [Any] { return "[" + a.map(normalize).sorted().joined(separator: ", ") + "]" }
        if let s = value as? String { return quoted(s) }
        if let d = value as? Data { return "data " + d.base64EncodedString() }
        return String(describing: value)
    }
}
public struct Watch: Codable, Identifiable, Sendable {
    public var id: String; public var name: String; public var bookmark: Data?
    public var baseline: Snapshot?; public var current: Snapshot?; public var error: String?
    public var scanned: Date?
    public init(id: String, name: String, bookmark: Data? = nil, baseline: Snapshot? = nil, current: Snapshot? = nil, error: String? = nil) {
        self.id=id; self.name=name; self.bookmark=bookmark; self.baseline=baseline; self.current=current; self.error=error
    }
    public var changes: [Change] { guard let baseline, let current else { return [] }; return Compare.changes(baseline,current) }
    public mutating func receive(_ snapshot: Snapshot) { current=snapshot; error=nil; scanned=Date() }
    public mutating func fail(_ message: String) { error=message }
    public mutating func acknowledge() { guard error == nil, let current else { return }; baseline=current }
    public var report: String {
        var lines = [name, "Main executable only", "Helpers, traffic, TCC grants and effective access are unknown"]
        if let error { lines.append("Inspection unknown • " + error) }
        for c in changes { lines.append("\(c.kind) \(c.key)\nBefore  \(c.before ?? "Not declared")\nAfter  \(c.after ?? "Not declared")") }
        if baseline == nil { lines.append("No acknowledged baseline") }
        if let current {
            lines.append("Current declarations")
            for key in current.fields.keys.sorted() { lines.append(key + "  " + current.fields[key]!) }
        }
        if let baseline {
            lines.append("Acknowledged baseline")
            for key in baseline.fields.keys.sorted() { lines.append(key + "  " + baseline.fields[key]!) }
        }
        return lines.joined(separator: "\n\n")
    }
}
public enum Samples {
    public static var watches: [Watch] {
        let base=Snapshot(identity:"com.example.canvaskit",version:"1.0",team:"EXAMPLE A",declarations:["com.apple.security.app-sandbox":"true","com.apple.security.files.user-selected.read-only":"true"])
        var next=base; next.version="1.1"; next.team="EXAMPLE B"; next.declarations["com.apple.security.network.client"]="true"
        return [Watch(id:"sample.canvas",name:"CanvasKit",baseline:base,current:next),Watch(id:"sample.notes",name:"QuietNotes",baseline:base,error:"Sample signature could not be read. Previous baseline retained.")]
    }
}

public struct MenuPresentation: Equatable, Sendable {
    public let symbol: String
    public let title: String
    public init(watches: [Watch], sampleMode: Bool) {
        title = sampleMode ? "Sample" : ""
        symbol = watches.contains(where: { $0.error != nil }) ? "questionmark.circle" :
            watches.isEmpty ? "shield" :
            watches.contains(where: { !$0.changes.isEmpty || $0.baseline == nil }) ? "exclamationmark.shield" : "shield.lefthalf.filled"
    }
}
