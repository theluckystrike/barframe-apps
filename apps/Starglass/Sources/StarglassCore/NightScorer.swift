import Foundation

/// One night's stargazing outlook, scored 0-100.
public struct NightOutlook: Equatable, Identifiable {
    public var id: Date { nightStart }
    public let nightStart: Date       // astronomical dusk (or 21:00 fallback)
    public let nightEnd: Date         // astronomical dawn (or 05:00 fallback)
    public let score: Int             // 0-100
    public let averageCloud: Double   // percent, weighted low/mid/high
    public let averageVisibility: Double // meters
    public let averageHumidity: Double   // percent
    public let averageWind: Double       // km/h
    public let moonIllumination: Double  // 0-1 at moon-up weighting
    public let moonUpFraction: Double    // 0-1 of night with moon above horizon
    public let darkHours: Double         // hours inside astronomical darkness
    public let hasAstronomicalDark: Bool
    public let sampleHours: Int

    public var label: String {
        switch score {
        case 80...: return "Excellent"
        case 60..<80: return "Good"
        case 40..<60: return "Fair"
        case 20..<40: return "Poor"
        default: return "Washed out"
        }
    }
}

/// Pure scoring and night-window logic. No I/O: fully unit-testable.
public enum NightScorer {
    /// Local-midnight-to-midnight calendar in the location's timezone.
    public static func nightWindow(for date: Date, latitude: Double, longitude: Double, calendar: Calendar = .current) -> (start: Date, end: Date, dark: Bool) {
        // Transfer the requested civil date to UTC for the solar formula's date basis.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let solarDate = utc.date(from: components)!
        if let dusk = SkyMath.astronomicalTwilight(date: solarDate, latitude: latitude, longitude: longitude)?.set {
            for offset in 0...2 {
                let day = utc.date(byAdding: .day, value: offset, to: solarDate)!
                if let dawn = SkyMath.astronomicalTwilight(date: day, latitude: latitude, longitude: longitude)?.rise, dawn > dusk {
                    return (dusk, dawn, true)
                }
            }
        }
        let start = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date) ?? date
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
        let end = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: tomorrow)!
        return (start, end, false)
    }

    /// Score one night from hourly forecast data.
    /// Weights: cloud 55 (low cover weighted heaviest), visibility 20, humidity 10, wind 5, moon 10.
    public static func score(forecast: Forecast, latitude: Double, longitude: Double, now: Date = Date(), calendar: Calendar = .current) -> [NightOutlook] {
        var out: [NightOutlook] = []
        let cursor = calendar.startOfDay(for: now)
        // Tonight: start from the upcoming dusk after `now`. Later nights: successive days.
        for dayOffset in 0..<8 {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: cursor)!
            let window = nightWindow(for: day, latitude: latitude, longitude: longitude, calendar: calendar)
            var hours = forecast.hours(between: window.start, and: window.end)
            if dayOffset == 0 {
                // Tonight only counts hours still in the future.
                hours = hours.filter { $0.time >= now.addingTimeInterval(-1800) }
            }
            guard !hours.isEmpty else { continue }
            var cloudSum = 0.0, visSum = 0.0, humSum = 0.0, windSum = 0.0
            var moonUpSum = 0.0, moonWeightedIllum = 0.0, weightSum = 0.0
            for hour in hours {
                let low = hour.cloudCoverLow ?? 50
                let mid = hour.cloudCoverMid ?? 50
                let high = hour.cloudCoverHigh ?? 50
                // Low clouds matter most to the observer; high cirrus least.
                let weighted = 0.5 * low + 0.3 * mid + 0.2 * high
                cloudSum += weighted
                visSum += hour.visibility ?? 10000
                humSum += hour.humidity ?? 60
                windSum += hour.windSpeed ?? 10
                let moonAlt = SkyMath.moonAltitude(hour.time, latitude: latitude, longitude: longitude)
                let moonUp = moonAlt > 0 ? 1.0 : 0.0
                moonUpSum += moonUp
                let illumination = SkyMath.moon(date: hour.time).illumination
                // Bright moon low on the horizon hurts less than a bright moon overhead.
                let penalty = moonUp * illumination * max(0, sin(moonAlt * .pi / 180))
                moonWeightedIllum += penalty
                weightSum += 1
            }
            let n = Double(hours.count)
            let avgCloud = cloudSum / n
            let avgVis = visSum / n
            let avgHum = humSum / n
            let avgWind = windSum / n
            let moonUpFraction = moonUpSum / n
            let moonPenalty = weightSum > 0 ? moonWeightedIllum / weightSum : 0

            let cloudScore = max(0, 100 - avgCloud * 1.1)          // 0% cloud -> 100, 90% -> 1
            let visScore = min(1, avgVis / 20000) * 100            // 20 km visibility = full marks
            let humScore = max(0, 100 - max(0, avgHum - 60) * 2.5) // transparent air below 60% RH
            let windScore = max(0, 100 - max(0, avgWind - 15) * 2) // calm up to 15 km/h
            let moonScore = (1 - moonPenalty) * 100
            let windowHours = max(0.1, window.end.timeIntervalSince(window.start) / 3600)
            let darkBonus = window.dark ? min(1, hours.count == 0 ? 0 : windowHours / 10) : 0.3

            let raw = 0.55 * cloudScore + 0.20 * visScore + 0.10 * humScore + 0.05 * windScore + 0.10 * moonScore
            let score = Int((raw * (0.7 + 0.3 * darkBonus)).rounded().clamped(0...100))
            out.append(NightOutlook(nightStart: window.start, nightEnd: window.end, score: score,
                                    averageCloud: avgCloud, averageVisibility: avgVis, averageHumidity: avgHum,
                                    averageWind: avgWind, moonIllumination: SkyMath.moon(date: window.start).illumination,
                                    moonUpFraction: moonUpFraction,
                                    darkHours: window.dark ? windowHours : 0,
                                    hasAstronomicalDark: window.dark, sampleHours: hours.count))
        }
        return out
    }

    /// Menu bar score for tonight: the first outlook.
    public static func tonightScore(_ outlooks: [NightOutlook]) -> Int? {
        outlooks.first?.score
    }

    /// Best upcoming night (highest score, ties broken by earliest date).
    public static func bestNight(_ outlooks: [NightOutlook]) -> NightOutlook? {
        outlooks.max { a, b in
            if a.score != b.score { return a.score < b.score }
            return a.nightStart > b.nightStart
        }
    }

    /// A night worth a notification: score 70+ and at least 3 sampled dark hours.
    public static func isWorthNotifying(_ outlook: NightOutlook) -> Bool {
        outlook.score >= 70 && outlook.sampleHours >= 3
    }
}

extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
