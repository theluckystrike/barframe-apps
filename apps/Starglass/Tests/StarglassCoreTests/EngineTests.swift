import Testing
import Foundation
@testable import StarglassCore

private let gregorian: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

// Fixed reference: 2026-10-14 00:00 UTC (matches research/raw fixtures).
private let refDate = Date(timeIntervalSince1970: 1_791_936_000)

struct SkyMathTests {
    @Test func julianDayKnownValue() {
        // 2026-10-14 00:00 UTC -> JD 2461327.5 (standard formula).
        let jd = SkyMath.julianDay(refDate)
        #expect(abs(jd - 2_461_327.5) < 0.001)
    }
    @Test func sunCycleInBounds() {
        let sun = SkyMath.sunRiseSet(date: refDate, latitude: 50, longitude: 20)
        #expect(sun != nil)
        #expect(sun!.rise < sun!.set)
    }
    @Test func astronomicalTwilightShorterThanSun() {
        let sun = SkyMath.sunRiseSet(date: refDate, latitude: 50, longitude: 20)!
        let twilight = SkyMath.astronomicalTwilight(date: refDate, latitude: 50, longitude: 20)
        #expect(twilight != nil)
        // Darkness between astronomical twilight set (evening) and rise (next morning)
        // must be shorter than the daylight span.
        let day = sun.set.timeIntervalSince(sun.rise)
        let dark = twilight!.rise.addingTimeInterval(86400).timeIntervalSince(twilight!.set)
        #expect(dark > 0 && dark < day)
    }
    @Test func twilightNilNearMidnightAtPolarSummer() {
        // Tromsø in July: sun never goes below -18°, so no astronomical night.
        let july = gregorian.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 12))!
        #expect(SkyMath.astronomicalTwilight(date: july, latitude: 69.65, longitude: 18.96) == nil)
    }
    @Test func moonIlluminationInRange() {
        for day in 0..<30 {
            let date = refDate.addingTimeInterval(Double(day) * 86400)
            let moon = SkyMath.moon(date: date)
            #expect(moon.illumination >= 0 && moon.illumination <= 1)
            #expect(moon.ageDays >= 0 && moon.ageDays < 30)
        }
    }
    @Test func moonKnownPhases() {
        // Full moon 2026-10-26, new moon 2026-11-10 (Meeus rough algorithm tolerance 0.05).
        let full = gregorian.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        let new = gregorian.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        #expect(SkyMath.moon(date: full).illumination > 0.93)
        #expect(SkyMath.moon(date: new).illumination < 0.07)
    }
    @Test func moonRiseSetConsistent() {
        if let times = SkyMath.moonRiseSet(date: refDate, latitude: 50, longitude: 20) {
            #expect(times.rise != times.set)
        }
    }
    @Test func moonAltitudeInRange() {
        let alt = SkyMath.moonAltitude(refDate, latitude: 50, longitude: 20)
        #expect(alt >= -90 && alt <= 90)
    }
}

struct NightScorerTests {
    let forecast = SampleData.forecast(now: SampleData.epoch)

    @Test func eightOutlooksFromSample() {
        let outlooks = NightScorer.score(forecast: forecast, latitude: 38.7, longitude: -109.6,
                                         now: SampleData.epoch, calendar: gregorian)
        #expect(outlooks.count == 8)
    }
    @Test func scoresWithinBounds() {
        let outlooks = NightScorer.score(forecast: forecast, latitude: 38.7, longitude: -109.6,
                                         now: SampleData.epoch, calendar: gregorian)
        #expect(outlooks.allSatisfy { (0...100).contains($0.score) })
    }
    @Test func clearNightBeatsCloudyNight() {
        let outlooks = NightScorer.score(forecast: forecast, latitude: 38.7, longitude: -109.6,
                                         now: SampleData.epoch, calendar: gregorian)
        let clear = outlooks[2]
        let cloudy = outlooks[5]
        #expect(clear.averageCloud < 10)
        #expect(cloudy.averageCloud > 80)
        #expect(clear.score > cloudy.score + 20)
    }
    @Test func firstOutlookIsTonight() {
        let outlooks = NightScorer.score(forecast: forecast, latitude: 38.7, longitude: -109.6,
                                         now: SampleData.epoch, calendar: gregorian)
        #expect(NightScorer.tonightScore(outlooks) == outlooks.first?.score)
    }
    @Test func bestNightIsHighestScore() {
        let outlooks = NightScorer.score(forecast: forecast, latitude: 38.7, longitude: -109.6,
                                         now: SampleData.epoch, calendar: gregorian)
        let best = NightScorer.bestNight(outlooks)
        #expect(best != nil)
        #expect(best!.score == outlooks.map(\.score).max())
    }
    @Test func emptyForecastYieldsNoOutlooks() {
        let empty = Forecast(latitude: 0, longitude: 0, timezone: "UTC", hours: [], fetchedAt: SampleData.epoch)
        #expect(NightScorer.score(forecast: empty, latitude: 0, longitude: 0, now: SampleData.epoch, calendar: gregorian).isEmpty)
    }
    @Test func tonightSkipsPastHours() {
        // Half the night already passed: tonight's sample count shrinks but stays valid.
        let mid = SampleData.epoch.addingTimeInterval(4 * 3600)
        let outlooks = NightScorer.score(forecast: forecast, latitude: 38.7, longitude: -109.6,
                                         now: mid, calendar: gregorian)
        #expect(!outlooks.isEmpty)
    }
    @Test func notificationGate() {
        let clear = NightOutlook(nightStart: refDate, nightEnd: refDate.addingTimeInterval(36000),
                                 score: 80, averageCloud: 5, averageVisibility: 23000, averageHumidity: 40,
                                 averageWind: 5, moonIllumination: 0.2, moonUpFraction: 0.1, darkHours: 9,
                                 hasAstronomicalDark: true, sampleHours: 9)
        let poor = NightOutlook(nightStart: refDate, nightEnd: refDate.addingTimeInterval(36000),
                                score: 30, averageCloud: 90, averageVisibility: 3000, averageHumidity: 90,
                                averageWind: 20, moonIllumination: 1, moonUpFraction: 1, darkHours: 9,
                                hasAstronomicalDark: true, sampleHours: 9)
        #expect(NightScorer.isWorthNotifying(clear))
        #expect(!NightScorer.isWorthNotifying(poor))
    }
    @Test func labelsMatchScoreBands() {
        func label(_ score: Int) -> String {
            NightOutlook(nightStart: refDate, nightEnd: refDate, score: score, averageCloud: 0,
                         averageVisibility: 0, averageHumidity: 0, averageWind: 0, moonIllumination: 0,
                         moonUpFraction: 0, darkHours: 0, hasAstronomicalDark: true, sampleHours: 1).label
        }
        #expect(label(90) == "Excellent")
        #expect(label(70) == "Good")
        #expect(label(50) == "Fair")
        #expect(label(30) == "Poor")
        #expect(label(10) == "Washed out")
    }
    @Test func nightWindowFallsBackPolar() {
        // Polar location in summer: no astronomical dark, 21:00-05:00 fallback window.
        let july = gregorian.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 12))!
        let window = NightScorer.nightWindow(for: july, latitude: 78.2, longitude: 15.6, calendar: gregorian)
        #expect(!window.dark)
        #expect(window.end.timeIntervalSince(window.start) == 8 * 3600)
    }
}

struct ClientAndStoreTests {
    @Test func geocodeRequestURL() {
        let client = OpenMeteoClient()
        let base = client.geocodeBase + "?name=Krakow&count=8&language=en&format=json"
        #expect(URL(string: base) != nil)
    }
    @Test func hourlyVariableListMatchesAPI() {
        // Matches the raw API response saved in research/raw: 2026-10-14.
        let expected = "cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility,relative_humidity_2m,wind_speed_10m"
        #expect(OpenMeteoClient.hourlyVariables == expected)
    }
    @Test func errorCopyIsActionable() {
        #expect(StarglassError.noLocation.errorDescription?.contains("location") == true)
        #expect(StarglassError.network("x").errorDescription?.contains("connection") == true)
    }
    @Test func forecastHourFiltering() {
        let start = refDate
        let hours = (0..<24).map { Forecast.Hour(time: start.addingTimeInterval(Double($0) * 3600),
                                                 cloudCoverLow: 0, cloudCoverMid: 0, cloudCoverHigh: 0,
                                                 visibility: 20000, humidity: 50, windSpeed: 5) }
        let forecast = Forecast(latitude: 0, longitude: 0, timezone: "UTC", hours: hours, fetchedAt: start)
        let window = forecast.hours(between: start.addingTimeInterval(5 * 3600), and: start.addingTimeInterval(9 * 3600))
        #expect(window.count == 4)
    }
    @Test func placeSummaryJoinsFields() {
        let place = Place(geocodeID: 3094802, name: "Krakow", latitude: 50.06, longitude: 19.94,
                          country: "Poland", admin1: "Lesser Poland", timezone: "Europe/Warsaw")
        #expect(place.summary == "Krakow, Lesser Poland, Poland")
    }
}
