import Foundation

/// A saved stargazing location (persisted in UserDefaults as JSON).
public struct SavedLocation: Codable, Equatable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timezone: String

    public init(name: String, latitude: Double, longitude: Double, timezone: String) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
    }

    public static let none = SavedLocation(name: "", latitude: 0, longitude: 0, timezone: "UTC")
    public var isEmpty: Bool { name.isEmpty }
}

/// Persists the location and the last forecast for offline use.
public struct LocationStore {
    public let defaults: UserDefaults
    public let cacheDirectory: URL

    public static let locationKey = "Starglass.savedLocation"
    public static let cacheFile = "last-forecast.json"

    public init(defaults: UserDefaults = .standard, cacheDirectory: URL? = nil) {
        self.defaults = defaults
        let base = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = base
    }

    public var location: SavedLocation? {
        get {
            guard let data = defaults.data(forKey: Self.locationKey) else { return nil }
            return try? JSONDecoder().decode(SavedLocation.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.locationKey)
            } else {
                defaults.removeObject(forKey: Self.locationKey)
            }
        }
    }

    /// Saves the latest forecast; corrupt or stale files are replaced silently.
    public func saveForecast(_ forecast: Forecast) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(forecast) else { return }
        try? data.write(to: cacheDirectory.appendingPathComponent(Self.cacheFile), options: .atomic)
    }

    /// Loads the cached forecast. Returns nil when missing or unreadable.
    public func loadForecast() -> Forecast? {
        let url = cacheDirectory.appendingPathComponent(Self.cacheFile)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Forecast.self, from: data)
    }

    public func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(Self.cacheFile))
    }
}
