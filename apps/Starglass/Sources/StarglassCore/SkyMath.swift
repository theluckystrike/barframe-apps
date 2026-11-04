import Foundation

/// One date/time helper with fixed UTC handling for tests.
public enum SkyMath {
    /// Julian Day from a Date (noon-based UTC).
    public static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Geometric mean longitude of the sun (degrees), low-precision Astronomical Almanac formula.
    public static func sunLongitude(_ jd: Double) -> Double {
        let n = jd - 2451545.0
        return normalize(280.460 + 0.9856474 * n)
    }

    /// Mean anomaly of the sun (degrees).
    public static func sunAnomaly(_ jd: Double) -> Double {
        let n = jd - 2451545.0
        return normalize(357.528 + 0.9856003 * n)
    }

    /// Apparent ecliptic longitude of the sun (degrees).
    public static func sunApparentLongitude(_ jd: Double) -> Double {
        let g = sunAnomaly(jd) * .pi / 180
        return normalize(sunLongitude(jd) + 1.915 * sin(g) + 0.020 * sin(2 * g))
    }

    /// Obliquity of the ecliptic (degrees).
    public static func obliquity(_ jd: Double) -> Double {
        23.439 - 0.0000004 * (jd - 2451545.0)
    }

    /// Sun declination (degrees).
    public static func sunDeclination(_ jd: Double) -> Double {
        let lambda = sunApparentLongitude(jd) * .pi / 180
        let eps = obliquity(jd) * .pi / 180
        return asin(sin(eps) * sin(lambda)) * 180 / .pi
    }

    /// Equation of time in minutes.
    public static func equationOfTime(_ jd: Double) -> Double {
        let g = sunAnomaly(jd) * .pi / 180
        let lambda = sunApparentLongitude(jd) * .pi / 180
        let eps = obliquity(jd) * .pi / 180
        let y = tan(eps / 2) * tan(eps / 2)
        return 4 * degrees(
            y * sin(2 * lambda)
            - 2 * 0.0167 * sin(g)
            + 4 * 0.0167 * y * sin(g) * cos(2 * lambda)
            - 0.5 * y * y * sin(4 * lambda)
            - 1.25 * 0.0167 * 0.0167 * sin(2 * g))
    }

    /// Sun rise/set times for a date at a location. Zenith -0.833° for rise/set.
    /// - Returns: (rise, set) or nil for polar day/night.
    public static func sunRiseSet(date: Date, latitude: Double, longitude: Double) -> (rise: Date, set: Date)? {
        solarTimes(date: date, latitude: latitude, longitude: longitude, zenith: -0.833)
    }

    /// Civil twilight (-6°): morning begins, evening ends.
    public static func civilTwilight(date: Date, latitude: Double, longitude: Double) -> (rise: Date, set: Date)? {
        solarTimes(date: date, latitude: latitude, longitude: longitude, zenith: -6)
    }

    /// Astronomical twilight (-18°): the dark window bounds.
    public static func astronomicalTwilight(date: Date, latitude: Double, longitude: Double) -> (rise: Date, set: Date)? {
        solarTimes(date: date, latitude: latitude, longitude: longitude, zenith: -18)
    }

    /// NOAA solar calculation. Zenith is the sun altitude threshold in degrees (negative = below horizon).
    public static func solarTimes(date: Date, latitude: Double, longitude: Double, zenith: Double) -> (rise: Date, set: Date)? {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = utc.startOfDay(for: date)
        let jd = julianDay(dayStart) + 0.5 // solar calcs at local-solar midnight basis
        let cosH = (sinDegrees(zenith) - sinDegrees(latitude) * sinDegrees(sunDeclination(jd)))
            / (cosDegrees(latitude) * cosDegrees(sunDeclination(jd)))
        guard cosH >= -1, cosH <= 1 else { return nil }
        let h = degrees(acos(cosH)) // hour angle magnitude
        let solarNoonUTC = 720 - 4 * longitude - equationOfTime(jd) // minutes from UTC midnight
        let riseMinutes = solarNoonUTC - 4 * h
        let setMinutes = solarNoonUTC + 4 * h
        return (dayStart.addingTimeInterval(riseMinutes * 60), dayStart.addingTimeInterval(setMinutes * 60))
    }

    /// Moon phase age in days (0 = new moon) and illuminated fraction (0-1), from a low-precision
    /// synodic algorithm referenced to a known new moon (2000-01-06 18:14 UTC).
    public static func moon(date: Date) -> (ageDays: Double, illumination: Double) {
        let synodic = 29.530588853
        let reference = Date(timeIntervalSince1970: 947182440) // 2000-01-06 18:14 UTC new moon
        var age = date.timeIntervalSince(reference) / 86400.0
        age = age.truncatingRemainder(dividingBy: synodic)
        if age < 0 { age += synodic }
        // Phase angle from age; illumination = (1 - cos(phase))/2
        let phase = 2 * .pi * age / synodic
        let illumination = (1 - cos(phase)) / 2
        return (age, illumination)
    }

    /// Human phase name from age in days.
    public static func moonPhaseName(ageDays: Double) -> String {
        let synodic = 29.530588853
        let names = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                     "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
        let index = Int(floor((ageDays + synodic / 16) / (synodic / 8))) % 8
        return names[max(0, min(7, index))]
    }

    /// Moon rise/set (approximate, ±1h): sample the moon's hourly elevation for the day
    /// and interpolate crossings of the horizon.
    public static func moonRiseSet(date: Date, latitude: Double, longitude: Double) -> (rise: Date, set: Date)? {
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = utc.startOfDay(for: date)
        var previous: Double? = nil
        var rise: Date? = nil
        var set: Date? = nil
        for step in 0...288 { // 5-minute samples over 24h
            let t = dayStart.addingTimeInterval(Double(step) * 300)
            let alt = moonAltitude(t, latitude: latitude, longitude: longitude)
            if let prev = previous {
                if prev < 0 && alt >= 0 && rise == nil { rise = dayStart.addingTimeInterval(Double(step - 1) * 300 + 300 * (0 - prev) / (alt - prev)) }
                if prev >= 0 && alt < 0 && set == nil { set = dayStart.addingTimeInterval(Double(step - 1) * 300 + 300 * prev / (prev - alt)) }
            }
            previous = alt
        }
        guard let r = rise, let s = set else { return nil }
        return (r, s)
    }

    /// Moon altitude above horizon (degrees) at a time and location.
    public static func moonAltitude(_ date: Date, latitude: Double, longitude: Double) -> Double {
        let jd = julianDay(date)
        let d = jd - 2451545.0
        // Low-precision lunar ecliptic coordinates (degrees).
        let L = normalize(218.316 + 13.176396 * d)       // mean longitude
        let M = normalize(134.963 + 13.064993 * d)       // mean anomaly
        let F = normalize(93.273 + 13.229350 * d)        // mean distance argument
        let lambda = L + 6.289 * sinDegrees(M)
        let beta = 5.128 * sinDegrees(F)
        let eps = obliquity(jd)
        // Ecliptic -> equatorial.
        let lamR = lambda * .pi / 180, betR = beta * .pi / 180, epsR = eps * .pi / 180
        let sinDec = sin(betR) * cos(epsR) + cos(betR) * sin(epsR) * sin(lamR)
        let dec = asin(sinDec)
        let ra = atan2(sin(lamR) * cos(epsR) - tan(betR) * sin(epsR), cos(lamR))
        // Hour angle.
        let gmst = normalize(280.46061837 + 360.98564736629 * d)
        let lst = normalize(gmst + longitude)
        var ha = lst - degrees(ra)
        if ha > 180 { ha -= 360 }
        let latR = latitude * .pi / 180
        let alt = asin(sin(latR) * sin(dec) + cos(latR) * cos(dec) * cos(ha * .pi / 180))
        return degrees(alt)
    }

    static func normalize(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return a
    }
    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func sinDegrees(_ d: Double) -> Double { sin(radians(d)) }
    static func cosDegrees(_ d: Double) -> Double { cos(radians(d)) }
}
