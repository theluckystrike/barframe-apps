import Foundation

public struct Limits: Codable, Equatable, Sendable {
    public var fiveHours: Int
    public var sevenDays: Int
    public init(fiveHours: Int = 0, sevenDays: Int = 0) { self.fiveHours = fiveHours; self.sevenDays = sevenDays }
    public subscript(window: UsageWindow) -> Int { window == .fiveHours ? fiveHours : sevenDays }
}
public struct CachedUsage: Codable, Sendable {
    public let samples: [TokenSample]
    public let scannedAt: Date
    public let files: Int
    public init(samples: [TokenSample], scannedAt: Date, files: Int) {
        self.samples = samples; self.scannedAt = scannedAt; self.files = files
    }
}
public final class Preferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Discard the old cache schema, whose record IDs could contain source paths.
        for provider in Provider.allCases { defaults.removeObject(forKey: "cache.\(provider.rawValue)") }
    }
    private func key(_ prefix: String, _ provider: Provider) -> String { "\(prefix).\(provider.rawValue)" }
    public func grant(for provider: Provider) -> FolderGrant? { decode(FolderGrant.self, key: key("grant", provider)) }
    public func setGrant(_ grant: FolderGrant?, for provider: Provider) { encode(grant, key: key("grant", provider)) }
    public func limits(for provider: Provider) -> Limits { decode(Limits.self, key: key("limits", provider)) ?? Limits() }
    public func setLimits(_ limits: Limits, for provider: Provider) { encode(limits, key: key("limits", provider)) }
    public func cache(for provider: Provider) -> CachedUsage? { decode(CachedUsage.self, key: key("cache.v2", provider)) }
    public func setCache(_ cache: CachedUsage?, for provider: Provider) { encode(cache, key: key("cache.v2", provider)) }
    public var selected: Provider {
        get { Provider(rawValue: defaults.string(forKey: "selected") ?? "") ?? .claude }
        set { defaults.set(newValue.rawValue, forKey: "selected") }
    }
    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func encode<T: Encodable>(_ value: T?, key: String) {
        if let value, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}

public enum LimitEntryError: LocalizedError {
    case invalidCount
    public var errorDescription: String? { "Enter whole token counts from 0 to 1 trillion." }
}
public extension Limits {
    static func entered(fiveHours: String, sevenDays: String) throws -> Limits {
        func parse(_ value: String) throws -> Int {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return 0 }
            guard let count = Int(text), (0...1_000_000_000_000).contains(count) else { throw LimitEntryError.invalidCount }
            return count
        }
        return try Limits(fiveHours: parse(fiveHours), sevenDays: parse(sevenDays))
    }
}
