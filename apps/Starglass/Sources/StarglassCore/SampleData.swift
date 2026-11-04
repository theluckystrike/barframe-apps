import Foundation

/// Fixed synthetic forecast and sample location for App Review and screenshots.
/// No live network is used in Sample mode.
public enum SampleData {
    public static let location = SavedLocation(name: "Sample Springs", latitude: 38.7, longitude: -109.6, timezone: "UTC")

    /// Builds a deterministic 8-day hourly forecast: one clear night (night of day 2, i.e. UTC
    /// evening of day 2 through morning of day 3), one cloudy night (day 5), and mixed nights
    /// elsewhere. Times are fixed dates so screenshots and tests are stable.
    public static func forecast(now: Date = Date(timeIntervalSince1970: 1_791_936_000)) -> Forecast {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.startOfDay(for: now)
        var hours: [Forecast.Hour] = []
        for day in 0..<9 {
            for hour in 0..<24 {
                let time = start.addingTimeInterval(Double(day * 24 + hour) * 3600)
                // UTC night hours 0-11 and 21-23 (local night at long -109.6 is ~UTC 3-13).
                let isNight = hour >= 21 || hour < 12
                let clearNight = (day == 3)
                let cloudyNight = (day == 6)
                let cloud: Double
                let vis: Double
                if clearNight && isNight { cloud = 3; vis = 24_000 }
                else if cloudyNight && isNight { cloud = 92; vis = 4_000 }
                else if isNight { cloud = 45; vis = 15_000 }
                else { cloud = 30; vis = 20_000 }
                hours.append(Forecast.Hour(time: time, cloudCoverLow: cloud, cloudCoverMid: max(0, cloud - 8),
                                           cloudCoverHigh: max(0, cloud - 15), visibility: vis,
                                           humidity: isNight ? 45 : 38, windSpeed: 6))
            }
        }
        return Forecast(latitude: SampleData.location.latitude, longitude: SampleData.location.longitude,
                        timezone: "UTC", hours: hours, fetchedAt: now)
    }

    /// Fixed epoch used by Sample and its tests (2026-10-14 00:00 UTC).
    public static let epoch = Date(timeIntervalSince1970: 1_791_936_000)
}
