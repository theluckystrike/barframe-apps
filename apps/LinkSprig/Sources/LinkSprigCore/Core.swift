import Foundation

public struct DocumentLink: Codable, Equatable, Identifiable, Sendable {
    public var source: String
    public var line: Int
    public var column: Int?
    public var target: String
    public var image: Bool
    public var unchecked: Bool
    public var id: String { "\(source)|\(line)|\(column ?? 0)|\(target)|\(image)|\(unchecked)" }
    public init(source: String, line: Int, target: String, image: Bool = false, unchecked: Bool = false, column: Int = 0) {
        self.source = source; self.line = line; self.column = column; self.target = target; self.image = image; self.unchecked = unchecked
    }
}
public enum Markdown {
    public static func parse(_ text: String, source: String, includeImages: Bool = true) -> [DocumentLink] {
        var result: [DocumentLink] = []; var fence: Character?; var fenceCount = 0
        for (index, original) in text.components(separatedBy: "\n").enumerated() {
            let original = original.hasSuffix("\r") ? String(original.dropLast()) : original
            let trimmed = original.trimmingCharacters(in: .whitespaces)
            if let c = trimmed.first, c == "`" || c == "~" {
                let count = trimmed.prefix(while: { $0 == c }).count
                if count >= 3 {
                    if fence == nil { fence = c; fenceCount = count }
                    else if fence == c && count >= fenceCount && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    continue
                }
            }
            if fence != nil { continue }
            // Strip simple inline code while keeping Markdown outside the span.
            let line = original.replacingOccurrences(of: #"(`+).*?\1"#, with: "", options: .regularExpression)
            let ns = line as NSString; let range = NSRange(location: 0, length: ns.length)
            func captures(_ pattern: String) -> [NSTextCheckingResult] {
                (try? NSRegularExpression(pattern: pattern))?.matches(in: line, range: range) ?? []
            }
            var supported = 0
            let htmlRemainder = NSMutableString(string: line)
            var supportedRanges: [NSRange] = []
            for match in captures(#"(?<!\\)(!?)\[([^\[\]]*)\]\(\s*(<[^<>\n]+>|[^\s()]+)(?:\s+["'][^"']*["'])?\s*\)"#) {
                let image = ns.substring(with: match.range(at: 1)) == "!"
                var target = ns.substring(with: match.range(at: 3))
                if target.hasPrefix("<"), target.hasSuffix(">") { target = String(target.dropFirst().dropLast()) }
                if includeImages || !image { result.append(DocumentLink(source: source, line: index + 1, target: target, image: image, column: match.range.location)) }
                supported += 1
                supportedRanges.append(match.range)
            }
            for match in captures(#"^\s{0,3}\[([^\[\]]+)\]:\s*(<[^<>\n]+>|[^\s()]+)(?:\s+["'][^"']*["'])?\s*$"#) {
                var target = ns.substring(with: match.range(at: 2))
                if target.hasPrefix("<"), target.hasSuffix(">") { target = String(target.dropFirst().dropLast()) }
                result.append(DocumentLink(source: source, line: index + 1, target: target, column: match.range.location)); supported += 1
                supportedRanges.append(match.range)
            }
            for range in supportedRanges.sorted(by: { $0.location > $1.location }) { htmlRemainder.replaceCharacters(in: range, with: "") }
            let forms = captures(#"(?<!\\)!?\[[^\n]*?\]\("#).count
            let referenceLike = captures(#"^\s{0,3}\[[^\]]+\]:"#).count
            let nestedLabel = line.range(of: #"\[[^\]]*\[[^\]]*\][^\]]*\]\("#, options: .regularExpression) != nil
            if line.contains("[[") || (htmlRemainder as String).range(of: #"<\s*/?\s*[A-Za-z][A-Za-z0-9-]*(?:\s[^>]*|/?)>"#, options: [.regularExpression, .caseInsensitive]) != nil || forms + referenceLike > supported || nestedLabel {
                result.append(DocumentLink(source: source, line: index + 1, target: String(line.prefix(160)), unchecked: true))
            }
        }
        return result
    }
}
public enum PathRules {
    public static func normalize(_ path: String, relativeTo base: String = "") -> String? {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return nil }
        var stack = base.split(separator: "/").map(String.init)
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { guard !stack.isEmpty else { return nil }; stack.removeLast() }
            else { stack.append(String(part)) }
        }
        return stack.joined(separator: "/")
    }
    public static func parent(_ path: String) -> String { path.split(separator: "/").dropLast().joined(separator: "/") }
    public static func contains(_ parent: String, _ child: String) -> Bool { child == parent || child.hasPrefix(parent + "/") }
    public static func relative(from source: String, to target: String) -> String {
        var left = parent(source).split(separator: "/").map(String.init)
        var right = target.split(separator: "/").map(String.init)
        while let a = left.first, let b = right.first, a == b { left.removeFirst(); right.removeFirst() }
        let path = (Array(repeating: "..", count: left.count) + right).joined(separator: "/")
        return path.isEmpty ? "./" : path
    }
    public static func encode(_ path: String) -> String {
        var set = CharacterSet.urlPathAllowed; set.remove(charactersIn: "?#%[]")
        return path.addingPercentEncoding(withAllowedCharacters: set) ?? path
    }
}
public enum Target: Equatable, Sendable {
    case local(String, String), external, fragment, escape, unchecked
    public static func resolve(_ link: DocumentLink, source: String? = nil) -> Target {
        if link.unchecked { return .unchecked }
        let raw = link.target
        if raw.hasPrefix("#") { return .fragment }
        if raw.hasPrefix("//") || raw.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil { return .external }
        let parts = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let fragment = parts.count > 1 ? "#" + parts[1] : ""
        guard !parts[0].contains("?"), let decoded = String(parts[0]).removingPercentEncoding else { return .unchecked }
        guard !decoded.isEmpty else { return .unchecked }
        guard let path = PathRules.normalize(decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded, relativeTo: decoded.hasPrefix("/") ? "" : PathRules.parent(source ?? link.source)) else { return .escape }
        return .local(path, fragment)
    }
}
public struct Tree: Codable, Sendable {
    public var nodes: Set<String>
    public var directories: Set<String>
    public var links: [DocumentLink]
    public var warnings: [String]
    public var fingerprint: String
    public var unavailablePaths: Set<String>
    public var reverseIndex: [String: [DocumentLink]] {
        var index: [String: [DocumentLink]] = [:]
        for link in links {
            if case let .local(path, _) = Target.resolve(link) { index[path, default: []].append(link) }
        }
        return index
    }
    public init(nodes: Set<String>, directories: Set<String> = [""], links: [DocumentLink], warnings: [String] = [], fingerprint: String = "", unavailablePaths: Set<String> = []) {
        self.nodes = nodes; self.directories = directories; self.links = links; self.warnings = warnings; self.fingerprint = fingerprint; self.unavailablePaths = unavailablePaths
    }
}
public enum ScanError: Error, LocalizedError {
    case permission, symlinkRoot, cancelled
    public var errorDescription: String? {
        switch self {
        case .permission: return "Folder access unavailable. Choose the folder again."
        case .symlinkRoot: return "Choose a real folder instead of a symbolic link."
        case .cancelled: return "Scan cancelled. The previous result is stale."
        }
    }
}
public enum Scanner {
    public static let exclusions: Set<String> = [".git", ".svn", "node_modules", ".build", "vendor"]
    public static func scan(root: URL, includeImages: Bool = true, excluded: Set<String> = exclusions, cancelled: () -> Bool = { false }, parseDocuments: Bool = true) throws -> Tree {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let rootValues = try root.resourceValues(forKeys: keys)
        guard rootValues.isSymbolicLink != true else { throw ScanError.symlinkRoot }
        guard rootValues.isDirectory == true else { throw ScanError.permission }
        // Verify root can actually be read before accepting an empty tree.
        _ = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var tree = Tree(nodes: [""], links: [])
        var fingerprints: [String] = []
        let prefix = root.standardizedFileURL.path + "/"
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { url, _ in
            let path = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            tree.warnings.append(CoverageKind.unreadable.rawValue + " · " + path); tree.unavailablePaths.insert(path); return true
        }) else { throw ScanError.permission }
        for case let url as URL in enumerator {
            if cancelled() { throw ScanError.cancelled }
            guard url.standardizedFileURL.path.hasPrefix(prefix) else { tree.warnings.append(CoverageKind.escape.rawValue); enumerator.skipDescendants(); continue }
            let path = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { tree.warnings.append(CoverageKind.symlink.rawValue + " · " + path); tree.unavailablePaths.insert(path); enumerator.skipDescendants(); continue }
                if values.isDirectory == true && excluded.contains(url.lastPathComponent) { tree.warnings.append(CoverageKind.excluded.rawValue + " · " + path); tree.unavailablePaths.insert(path); enumerator.skipDescendants(); continue }
                tree.nodes.insert(path)
                if values.isDirectory == true { tree.directories.insert(path) }
                fingerprints.append("\(path)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)")
                if parseDocuments && values.isRegularFile == true && ["md", "markdown", "mdx"].contains(url.pathExtension.lowercased()) {
                    if (values.fileSize ?? 0) > 8_000_000 { tree.warnings.append(CoverageKind.large.rawValue + " · " + path); continue }
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data, encoding: .utf8) else { tree.warnings.append(CoverageKind.encoding.rawValue + " · " + path); continue }
                    tree.links += Markdown.parse(text, source: path, includeImages: includeImages)
                }
            } catch { tree.warnings.append(CoverageKind.unreadable.rawValue + " · " + path); tree.unavailablePaths.insert(path); enumerator.skipDescendants() }
        }
        tree.links.sort { ($0.source, $0.line, $0.target) < ($1.source, $1.line, $1.target) }
        tree.fingerprint = fingerprints.sorted().joined(separator: "\n")
        return tree
    }
}
public enum ProposalError: String, Error, LocalizedError {
    case invalid = "Use paths within the chosen root.", missing = "The source path does not exist in the scanned tree.", conflict = "The destination already exists.", parentMissing = "The destination parent must be an existing folder.", selfMove = "A folder cannot move into itself.", unchanged = "Choose a different destination."
    public var errorDescription: String? { rawValue }
}
public struct Proposal: Codable, Equatable, Sendable {
    public var source: String; public var destination: String
    public init(source: String = "", destination: String = "") { self.source = source; self.destination = destination }
    public func validated(in tree: Tree) throws -> Proposal {
        guard let a = PathRules.normalize(source), let b = PathRules.normalize(destination), !a.isEmpty, !b.isEmpty else { throw ProposalError.invalid }
        guard tree.nodes.contains(a) else { throw ProposalError.missing }
        guard a != b else { throw ProposalError.unchanged }
        guard !PathRules.contains(a, b) else { throw ProposalError.selfMove }
        guard !tree.nodes.contains(where: { $0.caseInsensitiveCompare(b) == .orderedSame }) else { throw ProposalError.conflict }
        var parent = PathRules.parent(b)
        while !parent.isEmpty {
            if tree.nodes.contains(where: { $0.caseInsensitiveCompare(parent) == .orderedSame }) && !tree.directories.contains(parent) { throw ProposalError.conflict }
            parent = PathRules.parent(parent)
        }
        return Proposal(source: a, destination: b)
    }
    public func map(_ path: String) -> String {
        PathRules.contains(source, path) ? destination + path.dropFirst(source.count) : path
    }
}
public enum FindingKind: String, Codable, Sendable {
    case newlyBroken = "Newly broken", changed = "Target changes", preexisting = "Already missing", escape = "Outside root", unchecked = "Unchecked", external = "External", fragment = "Fragment unchecked"
}
public struct Finding: Codable, Identifiable, Sendable {
    public var link: DocumentLink; public var sourceAfter: String; public var kind: FindingKind; public var replacement: String?
    public var id: String { link.id + kind.rawValue }
    public init(link: DocumentLink, sourceAfter: String, kind: FindingKind, replacement: String? = nil) { self.link = link; self.sourceAfter = sourceAfter; self.kind = kind; self.replacement = replacement }
}
public struct Plan: Codable, Sendable {
    public var proposal: Proposal; public var findings: [Finding]; public var warnings: [String]; public var scannedAt: Date
    public var affected: [Finding] { findings.filter { $0.replacement != nil } }
    public var broken: [Finding] { findings.filter { $0.kind == .newlyBroken } }
    public var preexisting: [Finding] { findings.filter { $0.kind == .preexisting } }
    public var incomplete: Bool { !warnings.isEmpty || findings.contains { [.unchecked, .escape, .fragment].contains($0.kind) || $0.link.target.contains("#") } }
    public var state: String { incomplete ? "\(affected.count) affected · Incomplete" : affected.isEmpty ? "Clear" : "\(affected.count) affected" }
    public func report(sample: Bool) -> String {
        var lines = ["LinkSprig " + (sample ? "Sample " : "") + "path change plan", "Move \(proposal.source) to \(proposal.destination)", "Dry run only. Source files were not changed."]
        for f in affected { lines += ["", "\(f.link.source) line \(f.link.line)", "Source after move \(f.sourceAfter)", "Original \(f.link.target)", "Proposed \(f.replacement ?? "")", f.kind.rawValue] }
        lines += ["", "Already missing \(preexisting.count)", "Unchecked forms and coverage warnings must be reviewed.", "URL fragments are preserved. Fragment validity is Unchecked."]
        for f in findings where f.replacement == nil && f.kind != .external { lines.append("\(f.kind.rawValue) · \(f.link.source) line \(f.link.line) · \(f.link.target)") }
        lines += warnings
        return lines.joined(separator: "\n")
    }
}
public enum Planner {
    public static func plan(tree: Tree, proposal: Proposal, at date: Date = Date()) throws -> Plan {
        let p = try proposal.validated(in: tree)
        var after = Set(tree.nodes.map(p.map))
        var parent = PathRules.parent(p.destination)
        while !parent.isEmpty { after.insert(parent); parent = PathRules.parent(parent) }
        var findings: [Finding] = []
        let incomingIDs = Set(tree.reverseIndex.filter { p.map($0.key) != $0.key }.values.flatMap { $0 }.map(\.id))
        for link in tree.links {
            let source = p.map(link.source)
            let kind: FindingKind
            switch Target.resolve(link) {
            case .external: kind = .external
            case .fragment: kind = .fragment
            case .escape: kind = .escape
            case .unchecked: kind = .unchecked
            case let .local(target, fragment):
                guard tree.nodes.contains(target) else {
                    let unknown = tree.unavailablePaths.contains { $0.isEmpty || PathRules.contains($0.lowercased(), target.lowercased()) }
                        || tree.nodes.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
                    findings.append(Finding(link: link, sourceAfter: source, kind: unknown ? .unchecked : .preexisting)); continue
                }
                if !fragment.isEmpty { findings.append(Finding(link: link, sourceAfter: source, kind: .fragment)) }
                if source == link.source && !incomingIDs.contains(link.id) { continue }
                let desired = p.map(target)
                let actual = Target.resolve(link, source: source)
                if actual != .local(desired, fragment) {
                    let newKind: FindingKind
                    if case let .local(path, _) = actual, after.contains(path) { newKind = .changed } else { newKind = .newlyBroken }
                    let replacement = (link.target.hasPrefix("/") ? "/" + PathRules.encode(desired) : PathRules.encode(PathRules.relative(from: source, to: desired))) + fragment
                    findings.append(Finding(link: link, sourceAfter: source, kind: newKind, replacement: replacement)); continue
                }
                continue
            }
            findings.append(Finding(link: link, sourceAfter: source, kind: kind))
        }
        return Plan(proposal: p, findings: findings, warnings: tree.warnings, scannedAt: date)
    }
}
public struct SavedState: Codable, Equatable {
    public var bookmark: Data?; public var rootName: String; public var proposal: Proposal
    public var shortcutModifiers: UInt32?
    public var includeImages: Bool; public var exclusions: [String]; public var shortcutKey: UInt32; public var appearance: String; public var language: String
    public init(bookmark: Data? = nil, rootName: String = "", proposal: Proposal = Proposal(), includeImages: Bool = true, exclusions: [String] = Scanner.exclusions.sorted(), shortcutKey: UInt32 = UInt32.max, appearance: String = "system", language: String = "en", shortcutModifiers: UInt32 = 2304) {
        self.shortcutModifiers = shortcutModifiers; self.bookmark = bookmark; self.rootName = rootName; self.proposal = proposal; self.includeImages = includeImages; self.exclusions = exclusions; self.shortcutKey = shortcutKey; self.appearance = appearance; self.language = language
    }
    public static func load(_ data: Data?) -> (SavedState, Bool) {
        guard let data else { return (SavedState(), false) }
        do {
            var state = try JSONDecoder().decode(SavedState.self, from: data)
            if state.shortcutModifiers == nil { state.shortcutKey = UInt32.max; state.shortcutModifiers = 2304 }
            return (state, false)
        } catch { return (SavedState(), true) }
    }
}
public enum Sample {
    public static let proposal = Proposal(source: "guide.md", destination: "archive/guide.md")
    public static func create(at root: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        for path in ["archive", "images", "nested"] { try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        let files = ["guide.md": "# Sample guide\n[Diagram](images/diagram.png)\n![Missing](images/missing.png)\n[Reference](nested/readme.md#setup)\n", "nested/readme.md": "# Sample readme\n[Guide](../guide.md)\n[Website](https://example.invalid)\n[[Wiki form]]\n", "images/diagram.png": "Sample image fixture"]
        for (name, text) in files { try Data(text.utf8).write(to: root.appendingPathComponent(name)) }
    }
}

/// Typed coverage labels keep legacy persisted warning strings readable.
public enum CoverageKind: String, CaseIterable, Sendable {
    case unreadable = "Unreadable descendant", escape = "Root escape skipped", symlink = "Symbolic link skipped", excluded = "Excluded folder", large = "Large document skipped", encoding = "Unsupported text encoding"
    public var spanish: String {
        switch self {
        case .unreadable: return "No se pudo leer el elemento"
        case .escape: return "Ruta fuera de la carpeta omitida"
        case .symlink: return "Enlace simbólico omitido"
        case .excluded: return "Carpeta excluida"
        case .large: return "Documento grande omitido"
        case .encoding: return "Codificación de texto no compatible"
        }
    }
    public static func localized(_ warning: String, spanish: Bool) -> String {
        guard spanish else { return warning }
        for kind in allCases where warning == kind.rawValue || warning.hasPrefix(kind.rawValue + " · ") {
            return kind.spanish + warning.dropFirst(kind.rawValue.count)
        }
        return "Cobertura incompleta"
    }
}
public extension ProposalError {
    var spanish: String {
        switch self {
        case .invalid: return "Usa rutas dentro de la carpeta elegida."
        case .missing: return "La ruta de origen no existe en la carpeta escaneada."
        case .conflict: return "La ruta de destino o una carpeta superior ya existe como archivo."
        case .parentMissing: return "La carpeta de destino no está disponible."
        case .selfMove: return "Una carpeta no puede moverse dentro de sí misma."
        case .unchanged: return "Elige otro destino."
        }
    }
}
public extension ScanError {
    var spanish: String {
        switch self {
        case .permission: return "Acceso no disponible. Vuelve a elegir la carpeta."
        case .symlinkRoot: return "Elige una carpeta real en lugar de un enlace simbólico."
        case .cancelled: return "Escaneo cancelado. El resultado anterior no está actualizado."
        }
    }
}
public enum ProductLink {
    public static let privacyPath = "/apps/linksprig/privacy/"
    public static let supportPath = "/apps/linksprig/support/"
    public static func webURL(_ raw: String?) -> URL? {
        guard let raw, !raw.contains("{"), !raw.contains("}"), let url = URL(string: raw), url.scheme == "https", url.host != nil, [privacyPath, supportPath].contains(url.path.hasSuffix("/") ? url.path : url.path + "/") else { return nil }
        return url
    }
}
