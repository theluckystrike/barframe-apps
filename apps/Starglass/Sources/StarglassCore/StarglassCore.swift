import Foundation

/// A geocoding result from the free Open-Meteo geocoding API.
public struct Place: Codable, Equatable, Identifiable {
    public var id: Int { geocodeID }
    public let geocodeID: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let country: String?
    public let admin1: String?
    public let timezone: String

    enum CodingKeys: String, CodingKey {
        case geocodeID = "id"
        case name, latitude, longitude, country, admin1, timezone
    }

    public var summary: String {
        [name, admin1, country].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Decoded Open-Meteo forecast for one location.
public struct Forecast: Codable, Equatable {
    public struct Hour: Codable, Equatable {
        public let time: Date
        public let cloudCoverLow: Double?
        public let cloudCoverMid: Double?
        public let cloudCoverHigh: Double?
        public let visibility: Double?
        public let humidity: Double?
        public let windSpeed: Double?
    }
    public let latitude: Double
    public let longitude: Double
    public let timezone: String
    public let hours: [Hour]
    public let fetchedAt: Date

    public func hours(between start: Date, and end: Date) -> [Hour] {
        hours.filter { $0.time >= start && $0.time < end }
    }
}

/// Errors surfaced to the UI with clear, actionable copy.
public enum StarglassError: LocalizedError, Equatable {
    case network(String)
    case decoding(String)
    case noLocation
    case badURL

    public var errorDescription: String? {
        switch self {
        case .network(let detail): return "Could not reach the forecast service. Check your connection. (\(detail))"
        case .decoding(let detail): return "The forecast response was unreadable. Try again later. (\(detail))"
        case .noLocation: return "Choose a location first in Settings."
        case .badURL: return "The forecast request could not be built."
        }
    }
}

/// Fetches geocoding and forecasts from the free Open-Meteo APIs.
public struct OpenMeteoClient {
    public var geocodeBase = "https://geocoding-api.open-meteo.com/v1/search"
    public var forecastBase = "https://api.open-meteo.com/v1/forecast"
    public var session: URLSession = .shared

    public init() {}

    public static let hourlyVariables = "cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,relative_humidity_2m,wind_speed_10m"

    public func geocode(_ query: String) async throws -> [Place] {
        guard var components = URLComponents(string: geocodeBase) else { throw StarglassError.badURL }
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { throw StarglassError.badURL }
        let (data, response) = try await fetch(url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw StarglassError.network("status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        do {
            let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            return decoded.results ?? []
        } catch {
            throw StarglassError.decoding(String(describing: error))
        }
    }

    public func forecast(latitude: Double, longitude: Double) async throws -> Forecast {
        guard var components = URLComponents(string: forecastBase) else { throw StarglassError.badURL }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "hourly", value: Self.hourlyVariables),
            URLQueryItem(name: "forecast_days", value: "8"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw StarglassError.badURL }
        let (data, response) = try await fetch(url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw StarglassError.network("status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        do {
            let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
            return Forecast(latitude: decoded.latitude, longitude: decoded.longitude,
                            timezone: decoded.timezone, hours: decoded.hours, fetchedAt: Date())
        } catch {
            throw StarglassError.decoding(String(describing: error))
        }
    }

    private func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            return try await session.data(for: request)
        } catch {
            throw StarglassError.network(error.localizedDescription)
        }
    }
}

struct GeocodeResponse: Codable {
    let results: [Place]?
}

struct ForecastResponse: Codable {
    struct Hourly: Codable {
        let time: [String]
        let cloudCoverLow: [Double?]
        let cloudCoverMid: [Double?]
        let cloudCoverHigh: [Double?]
        let visibility: [Double?]
        let relativeHumidity2m: [Double?]
        let windSpeed10m: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case cloudCoverLow = "cloud_cover_low"
            case cloudCoverMid = "cloud_cover_mid"
            case cloudCoverHigh = "cloud_cover_high"
            case visibility
            case relativeHumidity2m = "relative_humidity_2m"
            case windSpeed10m = "wind_speed_10m"
        }
    }
    let latitude: Double
    let longitude: Double
    let timezone: String
    let hourly: Hourly

    var hours: [Forecast.Hour] {
        let formatter = ISO8601LocalOrPlain(timezone: timezone)
        return zip(zip(zip(hourly.time, hourly.cloudCoverLow), zip(hourly.cloudCoverMid, hourly.cloudCoverHigh)),
                   zip(hourly.visibility, zip(hourly.relativeHumidity2m, hourly.windSpeed10m)))
            .compactMap { element in
                let (pair, pair2) = (element.0, element.1)
                let ((timeString, low), (mid, high)) = (pair.0, pair.1)
                let (vis, pair3) = (pair2.0, pair2.1)
                let (hum, wind) = (pair3.0, pair3.1)
                guard let time = formatter.parse(timeString) else { return nil }
                return Forecast.Hour(time: time, cloudCoverLow: low, cloudCoverMid: mid,
                                     cloudCoverHigh: high, visibility: vis, humidity: hum, windSpeed: wind)
            }
    }
}

/// Open-Meteo local time strings look like "2026-10-14T21:00"; parse with or without an offset.
struct ISO8601LocalOrPlain {
    let offset = ISO8601DateFormatter()
    let plain: DateFormatter
    init(timezone: String = "UTC") {
        offset.formatOptions = [.withInternetDateTime]
        plain = DateFormatter()
        plain.dateFormat = "yyyy-MM-dd'T'HH:mm"
        plain.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)
        plain.locale = Locale(identifier: "en_US_POSIX")
    }
    func parse(_ string: String) -> Date? {
        if string.count > 16, string[string.index(string.startIndex, offsetBy: 16)] == ":" {
            return offset.date(from: string)
        }
        if string.hasSuffix("Z") { return offset.date(from: string) }
        return plain.date(from: string)
    }
}
