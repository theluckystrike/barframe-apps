import Foundation

public enum LedgerFileError: Error, Equatable, Sendable {
    case unreadable
    case unsupportedFormat(String)
}

/// The exported .nativeledger document. It never holds bookmarks or file paths.
public struct LedgerFile: Codable, Equatable, Sendable {
    public static let currentFormat = "nativeledger.v1"
    public static let fileExtension = "nativeledger"
    public var format: String
    public var exportedAt: Date
    public var ledgers: [AppLedger]

    public init(ledgers: [AppLedger], exportedAt: Date) {
        format = Self.currentFormat
        self.exportedAt = LedgerCoding.normalized(exportedAt)
        self.ledgers = ledgers.map(Self.stripped)
    }
    static func stripped(_ ledger: AppLedger) -> AppLedger {
        var copy = ledger
        copy.bookmark = nil
        copy.appKey = nil
        copy.lastFingerprint = nil
        if PathScreen.looksLikePath(copy.displayName) { copy.displayName = copy.pinnedBundleID ?? "App" }
        return copy
    }
    public func encoded() throws -> Data {
        var clean = self
        clean.ledgers = ledgers.map(Self.stripped)
        return try LedgerCoding.encoder(pretty: true).encode(clean)
    }
    public static func decode(_ data: Data) throws -> LedgerFile {
        struct Header: Decodable { var format: String }
        guard let header = try? LedgerCoding.decoder().decode(Header.self, from: data) else { throw LedgerFileError.unreadable }
        guard header.format == currentFormat else { throw LedgerFileError.unsupportedFormat(PathScreen.safeToken(header.format, max: 40)) }
        guard var file = try? LedgerCoding.decoder().decode(LedgerFile.self, from: data) else { throw LedgerFileError.unreadable }
        file.ledgers = file.ledgers.map(stripped)
        return file
    }
}

public enum CrossMacVerdict: String, Codable, Sendable, CaseIterable {
    case sameBuild, differentBinarySameVersion, differentVersion, onlyHere, onlyThere
    public var label: String {
        switch self {
        case .sameBuild: return "Same build"
        case .differentBinarySameVersion: return "Different binary for the same version"
        case .differentVersion: return "Different version"
        case .onlyHere: return "Only on this Mac"
        case .onlyThere: return "Only on the other Mac"
        }
    }
}

public struct CrossMacRow: Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var verdict: CrossMacVerdict
    public var here: LedgerObservation?
    public var there: LedgerObservation?
    public init(bundleID: String, verdict: CrossMacVerdict, here: LedgerObservation?, there: LedgerObservation?) {
        self.bundleID = bundleID; self.verdict = verdict; self.here = here; self.there = there
    }
    public var id: String { bundleID }
}

public enum CrossMacComparison {
    /// The newest observation per bundle identifier across all ledgers. Removed apps are left out.
    static func latest(_ ledgers: [AppLedger]) -> [String: LedgerObservation] {
        var out: [String: LedgerObservation] = [:]
        for ledger in ledgers where !ledger.isRemoved {
            guard let obs = ledger.latest?.observation else { continue }
            if let known = out[obs.bundleID], known.observedAt >= obs.observedAt { continue }
            out[obs.bundleID] = obs
        }
        return out
    }
    /// The executable SHA-256 decides when both sides have it, because the cdhash depends on the slice each Mac selects.
    static func sameBinary(_ a: BinaryIdentity, _ b: BinaryIdentity) -> Bool { BinaryIdentity.match(a, b) }
    public static func verdict(here: LedgerObservation, there: LedgerObservation) -> CrossMacVerdict {
        guard VersionOrder.sameVersion(here.version, there.version) else { return .differentVersion }
        return here.build == there.build && sameBinary(here.binary, there.binary) ? .sameBuild : .differentBinarySameVersion
    }
    /// Rows sorted by bundle identifier.
    public static func compare(here: [AppLedger], there: LedgerFile) -> [CrossMacRow] {
        let mine = latest(here), theirs = latest(there.ledgers)
        return Set(mine.keys).union(theirs.keys).sorted().map { id in
            let a = mine[id], b = theirs[id]
            let verdict: CrossMacVerdict
            switch (a, b) {
            case let (a?, b?): verdict = Self.verdict(here: a, there: b)
            case (_?, nil): verdict = .onlyHere
            default: verdict = .onlyThere
            }
            return CrossMacRow(bundleID: id, verdict: verdict, here: a, there: b)
        }
    }
}
