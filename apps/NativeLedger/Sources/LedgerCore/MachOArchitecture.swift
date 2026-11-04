import Foundation

/// The CPU architectures declared in the main executable header. Stored as one ledger field.
public enum Arch: String, CaseIterable, Codable, Sendable {
    case appleSilicon = "Apple silicon"
    case universal = "Universal"
    case intelOnly = "x86_64 only"
    case script = "Script"
    case unknown = "Unknown"
    public var isArmCapable: Bool { self == .appleSilicon || self == .universal }
}

public enum CPUType {
    public static let x86: UInt32 = 7
    public static let x86_64: UInt32 = 0x01000007
    public static let arm64: UInt32 = 0x0100000c
}

/// Reads Mach-O thin and fat headers byte by byte, without aligned pointer loads.
public enum MachOArchitecture {
    private static func word(_ bytes: [UInt8], _ offset: Int, little: Bool) -> UInt32 {
        let indexes = little ? Array((offset..<offset + 4).reversed()) : Array(offset..<offset + 4)
        return indexes.reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[$1]) }
    }

    public static func classifyCPUs(_ cpus: [UInt32]) -> Arch {
        let intel = cpus.contains(CPUType.x86) || cpus.contains(CPUType.x86_64)
        let arm = cpus.contains(CPUType.arm64)
        if intel && arm { return .universal }
        if arm { return .appleSilicon }
        if intel { return .intelOnly }
        return .unknown
    }

    public static func classify(_ data: Data) -> Arch {
        if data.starts(with: [0x23, 0x21]) { return .script }
        guard let cpus = cpuTypes(data) else { return .unknown }
        return classifyCPUs(cpus)
    }

    /// The CPU types in a thin or fat Mach-O header. nil for a header that is not Mach-O or is truncated.
    public static func cpuTypes(_ data: Data) -> [UInt32]? {
        guard data.count >= 8 else { return nil }
        let b = Array(data)
        let magic = Array(b.prefix(4))
        let thinLittle: Bool
        let thinSize: Int
        switch magic {
        case [0xce, 0xfa, 0xed, 0xfe]: thinLittle = true; thinSize = 28
        case [0xcf, 0xfa, 0xed, 0xfe]: thinLittle = true; thinSize = 32
        case [0xfe, 0xed, 0xfa, 0xce]: thinLittle = false; thinSize = 28
        case [0xfe, 0xed, 0xfa, 0xcf]: thinLittle = false; thinSize = 32
        default: return fatCPUTypes(b, magic: magic)
        }
        guard b.count >= thinSize else { return nil }
        return [word(b, 4, little: thinLittle)]
    }

    private static func fatCPUTypes(_ b: [UInt8], magic: [UInt8]) -> [UInt32]? {
        let little: Bool
        let size: Int
        switch magic {
        case [0xca, 0xfe, 0xba, 0xbe]: little = false; size = 20
        case [0xbe, 0xba, 0xfe, 0xca]: little = true; size = 20
        case [0xca, 0xfe, 0xba, 0xbf]: little = false; size = 32
        case [0xbf, 0xba, 0xfe, 0xca]: little = true; size = 32
        default: return nil
        }
        let count = Int(word(b, 4, little: little))
        guard count > 0, count <= 64, b.count >= 8 + count * size else { return nil }
        return (0..<count).map { word(b, 8 + $0 * size, little: little) }
    }

    /// Slice names: arm64, x86_64, i386, or other for any other CPU type.
    public static func sliceName(_ cpu: UInt32) -> String {
        switch cpu {
        case CPUType.arm64: return "arm64"
        case CPUType.x86_64: return "x86_64"
        case CPUType.x86: return "i386"
        default: return "other"
        }
    }

    /// Sorted, distinct slice names of a Mach-O header. Empty for scripts and unreadable headers.
    public static func slices(_ data: Data) -> [String] {
        guard !data.starts(with: [0x23, 0x21]), let cpus = cpuTypes(data) else { return [] }
        return Array(Set(cpus.map(sliceName))).sorted()
    }

    /// Sorted slice names of the main executable of an app bundle.
    public static func slicesOfAppBundle(at app: URL) -> [String] {
        guard let exe = executableURL(forBundle: app), let handle = try? FileHandle(forReadingFrom: exe) else { return [] }
        defer { try? handle.close() }
        return slices((try? handle.read(upToCount: 4096)) ?? Data())
    }

    /// The bundle that holds Info.plist, and whether it is a wrapped bundle.
    static func bundleLocation(_ app: URL) -> (URL, Bool) {
        let fm = FileManager.default
        if fm.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) { return (app, false) }
        let wrapped = app.appendingPathComponent("WrappedBundle").resolvingSymlinksInPath()
        if fm.fileExists(atPath: wrapped.appendingPathComponent("Info.plist").path) { return (wrapped, true) }
        if let inner = try? fm.contentsOfDirectory(at: app.appendingPathComponent("Wrapper"), includingPropertiesForKeys: nil)
            .sorted(by: { $0.path < $1.path }).first(where: { $0.pathExtension == "app" }) {
            return (inner, true)
        }
        return (app, false)
    }

    static func infoPlist(_ app: URL) -> [String: Any] {
        let (bundle, wrapped) = bundleLocation(app)
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent(wrapped ? "Info.plist" : "Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    /// The main executable named by CFBundleExecutable. A name with a path separator is refused.
    public static func executableURL(forBundle app: URL) -> URL? {
        guard let executable = infoPlist(app)["CFBundleExecutable"] as? String,
              !executable.isEmpty, executable != ".", executable != "..", !executable.contains("/") else { return nil }
        let (bundle, wrapped) = bundleLocation(app)
        return (wrapped ? bundle : bundle.appendingPathComponent("Contents/MacOS")).appendingPathComponent(executable)
    }

    public static func classifyAppBundle(at app: URL) -> Arch {
        guard let exe = executableURL(forBundle: app), let handle = try? FileHandle(forReadingFrom: exe) else { return .unknown }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 4096)) ?? Data()
        let arch = classify(header)
        if bundleLocation(app).1 && arch.isArmCapable { return .appleSilicon }
        return arch
    }

    /// Finder display name with directional marks and the .app suffix removed.
    public static func displayName(at app: URL) -> String {
        let plist = infoPlist(app)
        let finder = FileManager.default.displayName(atPath: app.path)
        let fallback = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? app.lastPathComponent
        let value = finder.isEmpty ? fallback : finder
        let clean = value.replacingOccurrences(of: "\u{200E}", with: "").replacingOccurrences(of: "\u{200F}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.lowercased().hasSuffix(".app") ? String(clean.dropLast(4)) : clean
    }
}
