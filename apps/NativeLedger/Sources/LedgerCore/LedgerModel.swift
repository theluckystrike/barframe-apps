import Foundation
import Security

/// Known absence (`unsigned`, nil team, empty entitlements) is distinct from a failed read (`unavailable`).
public enum SigningState: Codable, Equatable, Sendable {
    case read(identifier: String, team: String?, entitlements: [String: String])
    case unsigned
    case unavailable
    public var isKnown: Bool { self != .unavailable }
}

/// The code directory hash and the main executable digest, both lowercase hex.
public struct BinaryIdentity: Codable, Equatable, Sendable {
    public var cdhash: String?
    public var executableSHA256: String?
    public init(cdhash: String? = nil, executableSHA256: String? = nil) {
        self.cdhash = cdhash; self.executableSHA256 = executableSHA256
    }
    /// The whole-file SHA-256 decides when both sides have it. The cdhash belongs to the slice the reading Mac
    /// selects, so one universal executable can give two cdhashes. It decides only when a SHA-256 is missing.
    static func decisiveHashes(_ a: BinaryIdentity, _ b: BinaryIdentity) -> (String, String)? {
        if let x = a.executableSHA256, let y = b.executableSHA256 { return (x, y) }
        if let x = a.cdhash, let y = b.cdhash { return (x, y) }
        return nil
    }
    /// True when a decisive hash is known on both sides and differs.
    public static func differ(_ a: BinaryIdentity, _ b: BinaryIdentity) -> Bool {
        decisiveHashes(a, b).map { $0.0 != $0.1 } ?? false
    }
    /// True when a decisive hash is known on both sides and matches.
    public static func match(_ a: BinaryIdentity, _ b: BinaryIdentity) -> Bool {
        decisiveHashes(a, b).map { $0.0 == $0.1 } ?? false
    }
}

/// The result of SecStaticCodeCheckValidity on the whole bundle, all architectures.
public enum SignatureValidity: Codable, Equatable, Sendable {
    case valid
    case invalid(code: Int32)
    /// Not run, not finished within the time limit, or recorded before validation existed.
    case notChecked
    public static let unsignedCode = Int32(errSecCSUnsigned)
    /// An invalid result for code that carries a signature. Unsigned code is reported by the signing state instead.
    public var isFailure: Bool { if case .invalid(let code) = self { return code != Self.unsignedCode }; return false }
    public var label: String {
        switch self {
        case .valid: return "Valid"
        case .invalid(let code): return code == Self.unsignedCode ? "Not signed" : "Invalid (code \(code))"
        case .notChecked: return "Not checked"
        }
    }
}

/// One complete reading of an app copy. It holds no file paths.
public struct LedgerObservation: Codable, Equatable, Sendable {
    public var bundleID: String
    public var version: String
    public var build: String
    public var architecture: Arch
    public var signing: SigningState
    public var binary: BinaryIdentity
    public var observedAt: Date
    /// NS...UsageDescription keys from Info.plist and their text.
    public var usageDescriptions: [String: String]
    /// Sorted bundle identifiers or file names of nested login items, launchd jobs, XPC services and helpers.
    public var backgroundItems: [String]
    /// SUFeedURL from Info.plist.
    public var updateFeedURL: String?
    /// LSMinimumSystemVersion from Info.plist.
    public var minimumSystemVersion: String?
    /// Sorted CPU slices of the main executable: arm64, x86_64, i386 or other.
    public var architectureSlices: [String]
    public var signatureValidity: SignatureValidity
    /// True when the reading recorded the fields above. Entries written before these fields existed decode as false,
    /// and comparisons against them skip the fields they did not record.
    public var extendedFields: Bool

    public init(bundleID: String, version: String, build: String, architecture: Arch, signing: SigningState,
                binary: BinaryIdentity, observedAt: Date,
                usageDescriptions: [String: String] = [:], backgroundItems: [String] = [], updateFeedURL: String? = nil,
                minimumSystemVersion: String? = nil, architectureSlices: [String] = [],
                signatureValidity: SignatureValidity = .notChecked, extendedFields: Bool = true) {
        self.bundleID = bundleID; self.version = version; self.build = build; self.architecture = architecture
        self.signing = signing; self.binary = binary; self.observedAt = observedAt
        self.usageDescriptions = usageDescriptions; self.backgroundItems = backgroundItems.sorted()
        self.updateFeedURL = updateFeedURL; self.minimumSystemVersion = minimumSystemVersion
        self.architectureSlices = architectureSlices.sorted(); self.signatureValidity = signatureValidity
        self.extendedFields = extendedFields
    }

    enum CodingKeys: String, CodingKey {
        case bundleID, version, build, architecture, signing, binary, observedAt
        case usageDescriptions, backgroundItems, updateFeedURL, minimumSystemVersion, architectureSlices, signatureValidity, extendedFields
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        version = try c.decode(String.self, forKey: .version)
        build = try c.decode(String.self, forKey: .build)
        architecture = try c.decode(Arch.self, forKey: .architecture)
        signing = try c.decode(SigningState.self, forKey: .signing)
        binary = try c.decode(BinaryIdentity.self, forKey: .binary)
        observedAt = try c.decode(Date.self, forKey: .observedAt)
        usageDescriptions = try c.decodeIfPresent([String: String].self, forKey: .usageDescriptions) ?? [:]
        backgroundItems = try c.decodeIfPresent([String].self, forKey: .backgroundItems) ?? []
        updateFeedURL = try c.decodeIfPresent(String.self, forKey: .updateFeedURL)
        minimumSystemVersion = try c.decodeIfPresent(String.self, forKey: .minimumSystemVersion)
        architectureSlices = try c.decodeIfPresent([String].self, forKey: .architectureSlices) ?? []
        signatureValidity = try c.decodeIfPresent(SignatureValidity.self, forKey: .signatureValidity) ?? .notChecked
        extendedFields = try c.decodeIfPresent(Bool.self, forKey: .extendedFields) ?? false
    }
    /// Fields that hold their default value are left out, so an entry recorded before they existed
    /// re-encodes to its original bytes and keeps its hash. Any other value is part of the canonical form.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(version, forKey: .version)
        try c.encode(build, forKey: .build)
        try c.encode(architecture, forKey: .architecture)
        try c.encode(signing, forKey: .signing)
        try c.encode(binary, forKey: .binary)
        try c.encode(observedAt, forKey: .observedAt)
        if !usageDescriptions.isEmpty { try c.encode(usageDescriptions, forKey: .usageDescriptions) }
        if !backgroundItems.isEmpty { try c.encode(backgroundItems, forKey: .backgroundItems) }
        try c.encodeIfPresent(updateFeedURL, forKey: .updateFeedURL)
        try c.encodeIfPresent(minimumSystemVersion, forKey: .minimumSystemVersion)
        if !architectureSlices.isEmpty { try c.encode(architectureSlices, forKey: .architectureSlices) }
        if signatureValidity != .notChecked { try c.encode(signatureValidity, forKey: .signatureValidity) }
        if extendedFields { try c.encode(true, forKey: .extendedFields) }
    }

    public var signingIdentifier: String? { if case .read(let id, _, _) = signing { return id }; return nil }
    public var team: String? { if case .read(_, let team, _) = signing { return team }; return nil }
    public var entitlements: [String: String] { if case .read(_, _, let e) = signing { return e }; return [:] }
    /// Every recorded field except the observation date.
    public func hasSameContent(as other: LedgerObservation) -> Bool {
        var a = self; a.observedAt = other.observedAt
        return a == other
    }
}

public enum EntryKind: String, Codable, Sendable {
    case observed, acknowledged
    /// The app is no longer in its watched folder. The entry repeats the last observation.
    case removed
}

public enum Anomaly: String, Codable, Sendable, CaseIterable {
    case silentRebuild, versionRegression, teamChange, newEntitlement, architectureChange
    case newBackgroundItem, newPrivacyUsage, signatureInvalid, updateFeedChanged
    public var label: String {
        switch self {
        case .silentRebuild: return "Silent rebuild"
        case .versionRegression: return "Version regression"
        case .teamChange: return "Team change"
        case .newEntitlement: return "New entitlement"
        case .architectureChange: return "Architecture change"
        case .newBackgroundItem: return "New background item"
        case .newPrivacyUsage: return "New privacy usage"
        case .signatureInvalid: return "Signature invalid"
        case .updateFeedChanged: return "Update feed changed"
        }
    }
    public var explanation: String {
        switch self {
        case .silentRebuild: return "The executable or code directory hash changed while the version and build stayed the same."
        case .versionRegression: return "The version is lower than in the previous entry."
        case .teamChange: return "The signing team differs from the previous entry."
        case .newEntitlement: return "The app declares an entitlement that the previous entry did not have."
        case .architectureChange: return "The main executable architecture differs from the previous entry."
        case .newBackgroundItem: return "The app contains a login item, launchd job, XPC service or helper that the previous entry did not have."
        case .newPrivacyUsage: return "The app declares a privacy usage description that the previous entry did not have."
        case .signatureInvalid: return "The code signature did not pass validation for all architectures."
        case .updateFeedChanged: return "The update feed address differs from the previous entry."
        }
    }
    /// Most severe first. Use this order for display. Detection output keeps allCases order.
    public static let displayOrder: [Anomaly] = [.signatureInvalid, .teamChange, .newBackgroundItem, .silentRebuild,
                                                 .versionRegression, .newEntitlement, .newPrivacyUsage, .updateFeedChanged,
                                                 .architectureChange]
    /// Higher is more severe. signatureInvalid is 9 and architectureChange is 1.
    public var severity: Int { Self.displayOrder.count - (Self.displayOrder.firstIndex(of: self) ?? Self.displayOrder.count - 1) }
    /// signatureInvalid, teamChange and newBackgroundItem.
    public var isHighSeverity: Bool { severity >= 7 }
    /// The anomalies sorted most severe first, without repeats.
    public static func bySeverity(_ anomalies: [Anomaly]) -> [Anomaly] { displayOrder.filter(Set(anomalies).contains) }
}

public enum ChangeField: Codable, Hashable, Sendable {
    case architecture, bundleIdentifier, signingIdentifier, version, build, team, cdhash, executableSHA256, signingState
    case entitlement(String)
    case usageDescription(String)
    case backgroundItem(String)
    case updateFeedURL, minimumSystemVersion, architectureSlices, signatureValidity
    public var label: String {
        switch self {
        case .architecture: return "Architecture"
        case .bundleIdentifier: return "Bundle identifier"
        case .signingIdentifier: return "Signing identifier"
        case .version: return "Version"
        case .build: return "Build"
        case .team: return "Signing team"
        case .cdhash: return "Code directory hash"
        case .executableSHA256: return "Executable SHA-256"
        case .signingState: return "Signing"
        case .entitlement(let key): return "Entitlement \(key)"
        case .usageDescription(let key): return "Usage description \(key)"
        case .backgroundItem(let item): return "Background item \(item)"
        case .updateFeedURL: return "Update feed"
        case .minimumSystemVersion: return "Minimum macOS version"
        case .architectureSlices: return "Architecture slices"
        case .signatureValidity: return "Signature validity"
        }
    }
}

public struct Change: Codable, Equatable, Sendable, Identifiable {
    public var field: ChangeField
    public var before: String?
    public var after: String?
    public init(field: ChangeField, before: String?, after: String?) { self.field = field; self.before = before; self.after = after }
    public var id: ChangeField { field }
    public var kind: String { before == nil ? "Added" : after == nil ? "Removed" : "Changed" }
}

public struct LedgerEntry: Codable, Equatable, Sendable, Identifiable {
    public var seq: Int
    public var kind: EntryKind
    public var observation: LedgerObservation
    public var changes: [Change]
    public var anomalies: [Anomaly]
    public var previousHash: String
    public var entryHash: String
    public var id: Int { seq }
    public init(seq: Int, kind: EntryKind, observation: LedgerObservation, changes: [Change], anomalies: [Anomaly],
                previousHash: String, entryHash: String) {
        self.seq = seq; self.kind = kind; self.observation = observation; self.changes = changes
        self.anomalies = anomalies; self.previousHash = previousHash; self.entryHash = entryHash
    }
    public var shortHash: String { String(entryHash.prefix(12)) }
}

/// Where a ledger came from: an app the user picked, or an app found in a watched folder.
public enum LedgerSource: Codable, Equatable, Hashable, Sendable {
    case picked
    case folder(UUID)
    public var folderID: UUID? { if case .folder(let id) = self { return id }; return nil }
}

/// One chosen copy of an app and its hash-chained history. The UUID keys the ledger, not the bundle ID or path.
public struct AppLedger: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var displayName: String
    public var bookmark: Data?
    public var entries: [LedgerEntry]
    /// The newest complete reading, including readings that matched the latest entry and added none.
    /// It is not part of the chain.
    public var lastCheckedAt: Date?
    /// Ledgers decoded from files without this field are picked.
    public var source: LedgerSource
    /// The path-free key of a watched-folder app (see AutoRecorder.appKey). nil for picked apps.
    public var appKey: String?
    /// The cheap fingerprint of the last full inspection of a watched-folder app. Not part of the chain.
    public var lastFingerprint: Fingerprint?
    public init(id: UUID = UUID(), displayName: String, bookmark: Data? = nil, entries: [LedgerEntry] = [], lastCheckedAt: Date? = nil,
                source: LedgerSource = .picked, appKey: String? = nil, lastFingerprint: Fingerprint? = nil) {
        self.id = id; self.displayName = displayName; self.bookmark = bookmark; self.entries = entries
        self.lastCheckedAt = lastCheckedAt.map(LedgerCoding.normalized)
        self.source = source; self.appKey = appKey; self.lastFingerprint = lastFingerprint
    }
    enum CodingKeys: String, CodingKey { case id, displayName, bookmark, entries, lastCheckedAt, source, appKey, lastFingerprint }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        entries = try c.decode([LedgerEntry].self, forKey: .entries)
        lastCheckedAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        source = try c.decodeIfPresent(LedgerSource.self, forKey: .source) ?? .picked
        appKey = try c.decodeIfPresent(String.self, forKey: .appKey)
        lastFingerprint = try c.decodeIfPresent(Fingerprint.self, forKey: .lastFingerprint)
    }
    public var latest: LedgerEntry? { entries.last }
    /// The bundle identifier of the first entry. A later reading with another identifier is a different app.
    public var pinnedBundleID: String? { entries.first?.observation.bundleID }
    /// The newest acknowledged entry, if any.
    public var baseline: LedgerEntry? { entries.last { $0.kind == .acknowledged } }
    /// True when the newest entry records that the app left its watched folder.
    public var isRemoved: Bool { latest?.kind == .removed }
    /// Anomalies recorded after the newest acknowledgement, in Anomaly order without repeats.
    public var openAnomalies: [Anomaly] {
        let start = entries.lastIndex { $0.kind == .acknowledged }.map { $0 + 1 } ?? 0
        let found = Set(entries[start...].flatMap(\.anomalies))
        return Anomaly.allCases.filter(found.contains)
    }
}

public enum ChainVerdict: Equatable, Sendable {
    case intact(count: Int)
    case broken(atSeq: Int, reason: String)
    public var isIntact: Bool { if case .intact = self { return true }; return false }
}

public enum DeclarationNormalizer {
    private static func quoted(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }
    public static func normalize(_ value: Any) -> String {
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if let d = value as? [String: Any] { return "{" + d.keys.sorted().map { "\(quoted($0))=\(normalize(d[$0]!))" }.joined(separator: ", ") + "}" }
        if let a = value as? [Any] { return "[" + a.map(normalize).joined(separator: ", ") + "]" }
        if let s = value as? String { return quoted(s) }
        if let d = value as? Data { return "data " + d.base64EncodedString() }
        return String(describing: value)
    }
    /// Values that look like file paths are replaced by a digest, so the ledger never stores a path
    /// and a changed value is still detected.
    public static func normalize(entitlements: [String: Any]) -> [String: String] {
        entitlements.mapValues { value in
            let text = normalize(value)
            return PathScreen.looksLikePath(text) ? "path value sha256 " + String(Hex.sha256(Data(text.utf8)).prefix(16)) : text
        }
    }
}

public enum LedgerComparison {
    /// Compares every recorded field. A version-only difference is a real change.
    public static func changes(_ a: LedgerObservation, _ b: LedgerObservation) -> [Change] {
        var out: [Change] = []
        func add(_ f: ChangeField, _ x: String?, _ y: String?) { if x != y { out.append(Change(field: f, before: x, after: y)) } }
        func state(_ s: SigningState) -> String {
            switch s { case .read: return "signed"; case .unsigned: return "not signed"; case .unavailable: return "not read" }
        }
        add(.bundleIdentifier, a.bundleID, b.bundleID)
        add(.version, a.version, b.version)
        add(.build, a.build, b.build)
        add(.architecture, a.architecture.rawValue, b.architecture.rawValue)
        add(.signingState, state(a.signing), state(b.signing))
        add(.signingIdentifier, a.signingIdentifier, b.signingIdentifier)
        add(.team, a.team, b.team)
        add(.cdhash, a.binary.cdhash, b.binary.cdhash)
        add(.executableSHA256, a.binary.executableSHA256, b.binary.executableSHA256)
        let ea = a.entitlements, eb = b.entitlements
        for key in Set(ea.keys).union(eb.keys).sorted() { add(.entitlement(key), ea[key], eb[key]) }
        // Fields that the older reading did not record are not compared.
        guard a.extendedFields && b.extendedFields else { return out }
        let ua = a.usageDescriptions, ub = b.usageDescriptions
        for key in Set(ua.keys).union(ub.keys).sorted() { add(.usageDescription(key), ua[key], ub[key]) }
        let ba = Set(a.backgroundItems), bb = Set(b.backgroundItems)
        for item in ba.union(bb).sorted() { add(.backgroundItem(item), ba.contains(item) ? "present" : nil, bb.contains(item) ? "present" : nil) }
        add(.updateFeedURL, a.updateFeedURL, b.updateFeedURL)
        add(.minimumSystemVersion, a.minimumSystemVersion, b.minimumSystemVersion)
        func slices(_ s: [String]) -> String? { s.isEmpty ? nil : s.joined(separator: ", ") }
        add(.architectureSlices, slices(a.architectureSlices), slices(b.architectureSlices))
        add(.signatureValidity, a.signatureValidity.label, b.signatureValidity.label)
        return out
    }
}
