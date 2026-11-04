import Foundation
import CryptoKit
import Darwin
import Security

/// Why an inspection did not produce a complete observation. Raw system error text is never stored.
public enum InspectionFailure: String, Codable, Sendable, CaseIterable {
    case accessUnavailable, bundleUnreadable, architectureUnreadable, signingUnreadable, executableUnreadable
    case changedDuringInspection, identityDiffers
    /// Fixed, path-free text for the UI and the report.
    public var safeMessage: String {
        switch self {
        case .accessUnavailable: return "Access to the selected app is unavailable. Choose the app again to renew access."
        case .bundleUnreadable: return "The selected app bundle could not be read."
        case .architectureUnreadable: return "The main executable architecture could not be read."
        case .signingUnreadable: return "Signing information could not be read."
        case .executableUnreadable: return "The main executable could not be read for hashing."
        case .changedDuringInspection: return "The app changed while it was being inspected. Inspect it again."
        case .identityDiffers: return "The app at this location has a different bundle identifier. Add it as a new app."
        }
    }
}

/// Opaque identity of the inspected inputs (size, modification time and inode). It holds no paths.
public struct Fingerprint: Codable, Equatable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

public struct BundleInfo: Equatable, Sendable {
    public var bundleID: String
    public var version: String
    public var build: String
    public init(bundleID: String, version: String, build: String) { self.bundleID = bundleID; self.version = version; self.build = build }
}

/// Info.plist declarations and bundle contents recorded with each full observation.
public struct BundleDetails: Equatable, Sendable {
    public var usageDescriptions: [String: String]
    public var backgroundItems: [String]
    public var updateFeedURL: String?
    public var minimumSystemVersion: String?
    public var architectureSlices: [String]
    public init(usageDescriptions: [String: String] = [:], backgroundItems: [String] = [], updateFeedURL: String? = nil,
                minimumSystemVersion: String? = nil, architectureSlices: [String] = []) {
        self.usageDescriptions = usageDescriptions; self.backgroundItems = backgroundItems.sorted()
        self.updateFeedURL = updateFeedURL; self.minimumSystemVersion = minimumSystemVersion
        self.architectureSlices = architectureSlices.sorted()
    }
}

public enum SigningRead: Equatable, Sendable {
    case read(identifier: String, team: String?, entitlements: [String: String])
    case unsigned
    case failed
}

public struct InspectionResult: Sendable, Equatable {
    public var observation: LedgerObservation?
    public var failure: InspectionFailure?
    /// A renewed read-only bookmark when the saved one resolved as stale. The caller saves it.
    public var refreshedBookmark: Data?
    public init(observation: LedgerObservation?, failure: InspectionFailure?, refreshedBookmark: Data? = nil) {
        self.observation = observation; self.failure = failure; self.refreshedBookmark = refreshedBookmark
    }
    public static func failed(_ failure: InspectionFailure) -> InspectionResult { InspectionResult(observation: nil, failure: failure) }
    /// Only a complete result belongs in a ledger.
    public var isComplete: Bool { failure == nil && observation != nil }
}

/// Injectable seams. Tests change state between these calls.
public protocol BundleInspectionSource: Sendable {
    func fingerprint(_ bundle: URL) -> Fingerprint?
    func bundleInfo(_ bundle: URL) -> BundleInfo?
    func architecture(_ bundle: URL) -> Arch
    func signing(_ bundle: URL) -> SigningRead
    func binary(_ bundle: URL) -> BinaryIdentity
    /// nil when the source does not read details. The observation then records no extended fields.
    func details(_ bundle: URL) -> BundleDetails?
    func signatureValidity(_ bundle: URL) -> SignatureValidity
}

public extension BundleInspectionSource {
    func details(_ bundle: URL) -> BundleDetails? { nil }
    func signatureValidity(_ bundle: URL) -> SignatureValidity { .notChecked }
}

/// Reads fingerprint, bundle info, architecture, signing and binary identity, then reads the fingerprint again.
/// A changed fingerprint refuses the whole result, so fields from two versions never combine.
/// This detects ordinary replacement during inspection. It is not protection against adversarial races.
public struct LedgerInspector: Sendable {
    let source: BundleInspectionSource
    let now: @Sendable () -> Date
    public init(source: BundleInspectionSource = SystemInspectionSource(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source; self.now = now
    }
    public func inspect(_ bundle: URL) -> InspectionResult {
        guard let before = source.fingerprint(bundle), let info = source.bundleInfo(bundle) else { return .failed(.bundleUnreadable) }
        let arch = source.architecture(bundle)
        let signing = source.signing(bundle)
        let binary = source.binary(bundle)
        let details = source.details(bundle)
        let validity = source.signatureValidity(bundle)
        guard let after = source.fingerprint(bundle), after == before else { return .failed(.changedDuringInspection) }
        let state: SigningState
        switch signing {
        case .read(let id, let team, let ent): state = .read(identifier: id, team: team, entitlements: ent)
        case .unsigned: state = .unsigned
        case .failed: state = .unavailable
        }
        var failure: InspectionFailure?
        if signing == .failed { failure = .signingUnreadable }
        else if binary.executableSHA256 == nil { failure = .executableUnreadable }
        else if arch == .unknown { failure = .architectureUnreadable }
        let extra = details ?? BundleDetails()
        let obs = LedgerObservation(bundleID: info.bundleID, version: info.version, build: info.build, architecture: arch,
                                    signing: state, binary: binary, observedAt: now(),
                                    usageDescriptions: extra.usageDescriptions, backgroundItems: extra.backgroundItems,
                                    updateFeedURL: extra.updateFeedURL, minimumSystemVersion: extra.minimumSystemVersion,
                                    architectureSlices: extra.architectureSlices, signatureValidity: validity,
                                    extendedFields: details != nil)
        return InspectionResult(observation: obs, failure: failure)
    }
}

/// Public Security APIs only. Reading signing information is not signature validation.
/// signatureValidity runs SecStaticCodeCheckValidity separately, with a time limit.
public struct SystemInspectionSource: BundleInspectionSource {
    public static let chunkSize = 1 << 20
    /// Seconds before a signature check is recorded as notChecked.
    public static let validityTimeout: TimeInterval = 20
    /// Folders inside Contents whose entries are recorded as background items.
    public static let backgroundItemFolders = ["Library/LoginItems", "Library/LaunchServices", "Library/LaunchAgents",
                                               "Library/LaunchDaemons", "XPCServices", "Helpers"]
    public init() {}
    static func statString(_ url: URL) -> String {
        var st = Darwin.stat()
        guard lstat(url.path, &st) == 0 else { return "absent" }
        return "\(st.st_size):\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec):\(st.st_ino)"
    }
    private func plist(_ bundle: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let p = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return p
    }
    public func fingerprint(_ bundle: URL) -> Fingerprint? {
        guard let p = plist(bundle) else { return nil }
        let exe = (p["CFBundleExecutable"] as? String).flatMap { $0.contains("/") ? nil : $0 } ?? ""
        let parts = [
            Self.statString(bundle.appendingPathComponent("Contents/Info.plist")),
            Self.statString(bundle.appendingPathComponent("Contents/MacOS/\(exe)")),
            Self.statString(bundle.appendingPathComponent("Contents/_CodeSignature/CodeResources")),
            Self.statString(bundle.appendingPathComponent("Contents/_CodeSignature")),
        ]
        return Fingerprint(parts.joined(separator: "|"))
    }
    public func bundleInfo(_ bundle: URL) -> BundleInfo? {
        guard let p = plist(bundle), let id = p["CFBundleIdentifier"] as? String, !id.isEmpty else { return nil }
        let short = p["CFBundleShortVersionString"] as? String
        let build = p["CFBundleVersion"] as? String
        return BundleInfo(bundleID: id, version: short ?? build ?? "Unknown", build: build ?? "Unknown")
    }
    public func architecture(_ bundle: URL) -> Arch { MachOArchitecture.classifyAppBundle(at: bundle) }

    private static func signingInfo(_ url: URL) -> (OSStatus, [String: Any]?) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return (errSecCSStaticCodeNotFound, nil) }
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return (status, info as? [String: Any])
    }
    public func signing(_ bundle: URL) -> SigningRead {
        let (status, dict) = Self.signingInfo(bundle)
        if status == errSecCSUnsigned { return .unsigned }
        guard status == errSecSuccess, let dict else { return .failed }
        // For code with no signature the call can succeed and return only the main executable URL.
        guard let id = dict[kSecCodeInfoIdentifier as String] as? String else {
            return dict[kSecCodeInfoUnique as String] == nil ? .unsigned : .failed
        }
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let ent = (dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any]) ?? [:]
        return .read(identifier: id, team: team, entitlements: DeclarationNormalizer.normalize(entitlements: ent))
    }
    /// The code directory hash of the slice macOS selects, as lowercase hex. nil for unsigned code.
    public static func cdhash(of url: URL) -> String? {
        let (status, dict) = signingInfo(url)
        guard status == errSecSuccess, let unique = dict?[kSecCodeInfoUnique as String] as? Data, !unique.isEmpty else { return nil }
        return Hex.string(unique)
    }
    /// SHA-256 of a file, read in 1 MiB chunks.
    public static func sha256(of url: URL, chunkSize: Int = chunkSize) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty { hasher.update(data: chunk) }
        } catch { return nil }
        return Hex.string(hasher.finalize())
    }
    public func binary(_ bundle: URL) -> BinaryIdentity {
        let sha = MachOArchitecture.executableURL(forBundle: bundle).flatMap { Self.sha256(of: $0) }
        return BinaryIdentity(cdhash: Self.cdhash(of: bundle), executableSHA256: sha)
    }

    /// Text that looks like a file path is replaced by a digest, as for entitlement values.
    static func screened(_ text: String) -> String {
        PathScreen.looksLikePath(text) ? "path value sha256 " + String(Hex.sha256(Data(text.utf8)).prefix(16)) : text
    }
    public func details(_ bundle: URL) -> BundleDetails? {
        let p = MachOArchitecture.infoPlist(bundle)
        guard !p.isEmpty else { return nil }
        var usage: [String: String] = [:]
        for (key, value) in p where key.hasPrefix("NS") && key.hasSuffix("UsageDescription") {
            usage[key] = Self.screened((value as? String) ?? DeclarationNormalizer.normalize(value))
        }
        return BundleDetails(usageDescriptions: usage, backgroundItems: Self.backgroundItems(in: bundle),
                             updateFeedURL: (p["SUFeedURL"] as? String).map(Self.screened),
                             minimumSystemVersion: (p["LSMinimumSystemVersion"] as? String).map(Self.screened),
                             architectureSlices: MachOArchitecture.slicesOfAppBundle(at: bundle))
    }

    /// Sorted, distinct names of nested background code: the CFBundleIdentifier of a nested bundle when it can be read,
    /// otherwise the file name.
    public static func backgroundItems(in bundle: URL) -> [String] {
        let fm = FileManager.default
        var items: Set<String> = []
        for folder in backgroundItemFolders {
            let dir = bundle.appendingPathComponent("Contents").appendingPathComponent(folder)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where !name.hasPrefix(".") {
                let item = dir.appendingPathComponent(name)
                let plistURL = [item.appendingPathComponent("Contents/Info.plist"), item.appendingPathComponent("Info.plist")]
                    .first { fm.fileExists(atPath: $0.path) }
                let id = plistURL.flatMap { try? Data(contentsOf: $0) }
                    .flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any] }
                    .flatMap { $0["CFBundleIdentifier"] as? String }
                if let id, !id.isEmpty, !id.contains("/") { items.insert(id) } else { items.insert(screened(name)) }
            }
        }
        return items.sorted()
    }

    /// SecStaticCodeCheckValidity with kSecCSCheckAllArchitectures and kSecCSStrictValidate, run on a background queue.
    /// Strict validation also rejects bytes appended after the last Mach-O slice, as codesign --verify --strict does.
    /// A check that does not finish within the timeout is recorded as notChecked.
    public static func checkValidity(of bundle: URL, timeout: TimeInterval = validityTimeout) -> SignatureValidity {
        ValidityChecks.shared.check(bundle, timeout: timeout, using: { validity(of: $0) })
    }
    static func validity(of bundle: URL) -> SignatureValidity {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(bundle as CFURL, [], &code)
        guard created == errSecSuccess, let code else { return .invalid(code: created == errSecSuccess ? errSecCSStaticCodeNotFound : created) }
        let status = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil)
        return status == errSecSuccess ? .valid : .invalid(code: status)
    }
    public func signatureValidity(_ bundle: URL) -> SignatureValidity { Self.checkValidity(of: bundle) }
}

/// Runs signature checks with a time limit. A check that passes the limit keeps running in the background,
/// because the Security call cannot be cancelled. At most `lingeringLimit` such checks may still run; while the
/// limit is reached, new checks are recorded as notChecked at once, so slow checks of very large apps never pile up.
public final class ValidityChecks: @unchecked Sendable {
    public static let shared = ValidityChecks()
    public let lingeringLimit: Int
    private let lock = NSLock()
    private var lingering = 0
    public init(lingeringLimit: Int = 2) { self.lingeringLimit = lingeringLimit }

    /// Checks that passed the time limit and are still running.
    public var lingeringCount: Int { lock.lock(); defer { lock.unlock() }; return lingering }

    public func check(_ bundle: URL, timeout: TimeInterval,
                      using validity: @escaping @Sendable (URL) -> SignatureValidity) -> SignatureValidity {
        final class Box: @unchecked Sendable {
            var value = SignatureValidity.notChecked
            var finished = false
            var timedOut = false
        }
        lock.lock()
        let full = lingering >= lingeringLimit
        lock.unlock()
        if full { return .notChecked }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { [self] in
            let result = validity(bundle)
            lock.lock()
            box.value = result; box.finished = true
            if box.timedOut { lingering -= 1 }
            lock.unlock()
            done.signal()
        }
        let inTime = done.wait(timeout: .now() + timeout) == .success
        lock.lock(); defer { lock.unlock() }
        if inTime || box.finished { return box.value }
        box.timedOut = true
        lingering += 1
        return .notChecked
    }
}

/// Size, modification time and inode of Info.plist, the main executable and CodeResources, hashed.
/// The value holds no paths. Any rewrite of these files changes it.
public enum CheapFingerprint {
    public static func of(bundle: URL) -> Fingerprint? {
        let (base, wrapped) = MachOArchitecture.bundleLocation(bundle)
        let contents = wrapped ? base : base.appendingPathComponent("Contents")
        let plist = SystemInspectionSource.statString(contents.appendingPathComponent("Info.plist"))
        guard plist != "absent" else { return nil }
        let parts = [
            plist,
            MachOArchitecture.executableURL(forBundle: bundle).map(SystemInspectionSource.statString) ?? "none",
            SystemInspectionSource.statString(contents.appendingPathComponent("_CodeSignature/CodeResources")),
        ]
        return Fingerprint("c1:" + Hex.sha256(Data(parts.joined(separator: "|").utf8)))
    }
}


/// The model-facing seam. Implementations may block. Callers run them away from the main actor.
public protocol AppInspecting: Sendable {
    func inspect(bookmark: Data?, id: UUID) -> InspectionResult
}

/// Resolves a read-only security-scoped bookmark and inspects the selected copy inside its scope.
public struct BookmarkInspector: AppInspecting {
    let inspector: LedgerInspector
    public init(inspector: LedgerInspector = LedgerInspector()) { self.inspector = inspector }
    public func inspect(bookmark: Data?, id: UUID) -> InspectionResult {
        guard let bookmark else { return .failed(.accessUnavailable) }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return .failed(.accessUnavailable) }
        let active = url.startAccessingSecurityScopedResource()
        defer { if active { url.stopAccessingSecurityScopedResource() } }
        var result = inspector.inspect(url)
        if stale && active { result.refreshedBookmark = try? Self.bookmark(for: url) }
        return result
    }
    public static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
