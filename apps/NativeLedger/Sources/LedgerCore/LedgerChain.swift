import Foundation
import CryptoKit

enum Hex {
    static func string(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    static func sha256(_ data: Data) -> String { string(SHA256.hash(data: data)) }
}

/// JSON coding shared by the chain, the store and exported files.
/// Dates are ISO 8601 UTC strings with exactly three fractional digits.
public enum LedgerCoding {
    private static func wholeSeconds() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }
    static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    static func date(milliseconds ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
    /// The date rounded to the nearest millisecond, as the chain stores it.
    public static func normalized(_ date: Date) -> Date { Self.date(milliseconds: milliseconds(date)) }

    public static func string(from date: Date) -> String {
        let ms = milliseconds(date)
        let seconds = ms >= 0 ? ms / 1000 : (ms - 999) / 1000
        let fraction = ms - seconds * 1000
        let base = wholeSeconds().string(from: Date(timeIntervalSince1970: Double(seconds)))
        return String(base.dropLast()) + String(format: ".%03lldZ", fraction)
    }
    public static func date(from text: String) -> Date? {
        guard text.hasSuffix("Z") else { return nil }
        let body = text.dropLast()
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = wholeSeconds().date(from: String(parts[0]) + "Z") else { return nil }
        var fraction: Int64 = 0
        if parts.count == 2 {
            let digits = parts[1]
            guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            let padded = (digits + "000").prefix(3)
            fraction = Int64(padded) ?? 0
            if digits.count > 3, let next = digits.dropFirst(3).first, next >= "5" { fraction += 1 }
        }
        return date(milliseconds: Int64(whole.timeIntervalSince1970) * 1000 + fraction)
    }

    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted] : [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(string(from: date))
        }
        return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported date")
            }
            return date
        }
        return d
    }
}

/// Numeric dotted version order. "1.10" is above "1.9" and "2.0" equals "2.0.0".
public enum VersionOrder {
    static func components(_ version: String) -> [Substring]? {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        return parts.map { part in
            let stripped = part.drop { $0 == "0" }
            return stripped.isEmpty ? "0" : stripped
        }
    }
    /// nil when either version has a component that is not a plain number.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult? {
        guard let x = components(a), let y = components(b) else { return nil }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : "0", q = i < y.count ? y[i] : "0"
            if p.count != q.count { return p.count < q.count ? .orderedAscending : .orderedDescending }
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
    /// Numeric equality when both are numeric, otherwise exact text equality.
    public static func sameVersion(_ a: String, _ b: String) -> Bool {
        if let order = compare(a, b) { return order == .orderedSame }
        return a == b
    }
}

public enum AnomalyDetector {
    public static func anomalies(previous: LedgerObservation?, current: LedgerObservation) -> [Anomaly] {
        var found: Set<Anomaly> = []
        // A failed signature needs no previous entry. An unchanged reading does not repeat it.
        if current.signatureValidity.isFailure, previous.map({ !$0.hasSameContent(as: current) }) ?? true {
            found.insert(.signatureInvalid)
        }
        guard let previous else { return Anomaly.allCases.filter(found.contains) }
        let binaryChanged = BinaryIdentity.differ(previous.binary, current.binary)
        if binaryChanged && previous.version == current.version && previous.build == current.build { found.insert(.silentRebuild) }
        if VersionOrder.compare(current.version, previous.version) == .orderedAscending { found.insert(.versionRegression) }
        let signingKnown = previous.signing.isKnown && current.signing.isKnown
        if signingKnown && previous.team != current.team { found.insert(.teamChange) }
        if signingKnown && !Set(current.entitlements.keys).subtracting(previous.entitlements.keys).isEmpty { found.insert(.newEntitlement) }
        if previous.architecture != current.architecture && previous.architecture != .unknown && current.architecture != .unknown {
            found.insert(.architectureChange)
        }
        // These fields are compared only when both readings recorded them.
        if previous.extendedFields && current.extendedFields {
            if !Set(current.backgroundItems).subtracting(previous.backgroundItems).isEmpty { found.insert(.newBackgroundItem) }
            if !Set(current.usageDescriptions.keys).subtracting(previous.usageDescriptions.keys).isEmpty { found.insert(.newPrivacyUsage) }
            if let feed = current.updateFeedURL, feed != previous.updateFeedURL { found.insert(.updateFeedChanged) }
        }
        return Anomaly.allCases.filter(found.contains)
    }
}

public enum AckOutcome: Equatable, Sendable {
    case acknowledged(LedgerEntry)
    /// The fresh reading differs from the latest entry. It was appended as an observed entry to review first.
    case changedSinceLatest(LedgerEntry)
    case nothingToAcknowledge
    case alreadyAcknowledged
    /// The chain does not verify, so no baseline is recorded on top of it.
    case chainBroken
}

public enum LedgerChain {
    public static let genesisHash = String(repeating: "0", count: 64)

    private struct Canonical: Encodable {
        let seq: Int
        let kind: EntryKind
        let observation: LedgerObservation
        let changes: [Change]
        let anomalies: [Anomaly]
        let previousHash: String
    }

    /// Sorted keys, millisecond ISO 8601 dates, unescaped slashes. entryHash is excluded.
    public static func canonicalBytes(_ entry: LedgerEntry) -> Data {
        let c = Canonical(seq: entry.seq, kind: entry.kind, observation: entry.observation, changes: entry.changes,
                          anomalies: entry.anomalies, previousHash: entry.previousHash)
        return (try? LedgerCoding.encoder().encode(c)) ?? Data()
    }
    public static func hash(_ entry: LedgerEntry) -> String { Hex.sha256(canonicalBytes(entry)) }

    /// Appends a new entry. Returns nil for an observed reading whose content equals the latest entry,
    /// unless the latest entry records a removal. A removed entry has no changes and no anomalies.
    @discardableResult
    public static func append(_ obs: LedgerObservation, kind: EntryKind, to ledger: inout AppLedger) -> LedgerEntry? {
        var current = obs
        current.observedAt = LedgerCoding.normalized(obs.observedAt)
        let previous = ledger.entries.last
        if kind == .observed, let previous, previous.kind != .removed, previous.observation.hasSameContent(as: current) { return nil }
        let removed = kind == .removed
        var entry = LedgerEntry(seq: ledger.entries.count + 1, kind: kind, observation: current,
                                changes: removed ? [] : previous.map { LedgerComparison.changes($0.observation, current) } ?? [],
                                anomalies: removed ? [] : AnomalyDetector.anomalies(previous: previous?.observation, current: current),
                                previousHash: previous?.entryHash ?? genesisHash, entryHash: "")
        entry.entryHash = hash(entry)
        ledger.entries.append(entry)
        return entry
    }

    /// Accepts the latest entry as the reviewed baseline, using a fresh reading of the same copy.
    public static func acknowledge(_ fresh: LedgerObservation, in ledger: inout AppLedger) -> AckOutcome {
        guard let latest = ledger.entries.last, latest.kind != .removed else { return .nothingToAcknowledge }
        guard verify(ledger).isIntact else { return .chainBroken }
        guard latest.observation.hasSameContent(as: fresh) else {
            guard let entry = append(fresh, kind: .observed, to: &ledger) else { return .nothingToAcknowledge }
            return .changedSinceLatest(entry)
        }
        if latest.kind == .acknowledged { return .alreadyAcknowledged }
        guard let entry = append(fresh, kind: .acknowledged, to: &ledger) else { return .nothingToAcknowledge }
        return .acknowledged(entry)
    }

    /// Checks numbering, links and hashes from the first entry. The verdict names the first broken position.
    /// A chain without an outside copy cannot reveal removal of the newest entries or a full rewrite.
    public static func verify(_ ledger: AppLedger) -> ChainVerdict {
        var expectedPrevious = genesisHash
        for (index, entry) in ledger.entries.enumerated() {
            let position = index + 1
            if entry.seq != position {
                return .broken(atSeq: position, reason: "Entry \(position) is missing or out of order. Found entry \(entry.seq) in its place.")
            }
            if entry.previousHash != expectedPrevious {
                return .broken(atSeq: position, reason: position == 1
                    ? "Entry 1 does not start the chain."
                    : "Entry \(position) does not link to entry \(position - 1).")
            }
            if hash(entry) != entry.entryHash {
                return .broken(atSeq: position, reason: "Entry \(position) was changed after it was recorded.")
            }
            expectedPrevious = entry.entryHash
        }
        return .intact(count: ledger.entries.count)
    }

    /// Appends a removed entry that repeats the latest observation at the given date.
    /// Returns nil when the ledger is empty or already ends with a removed entry.
    @discardableResult
    public static func markRemoved(_ ledger: inout AppLedger, at date: Date) -> LedgerEntry? {
        guard var last = ledger.latest, last.kind != .removed else { return nil }
        last.observation.observedAt = date
        return append(last.observation, kind: .removed, to: &ledger)
    }
}
