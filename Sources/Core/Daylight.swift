import Foundation

// MARK: - Daylight
// How bright it is outdoors where the Mac is, from the sun's position alone: computed here from coordinates and the
// time, with no network. The Rotation aims its pick at this (the Target brightness) in `dynamic` Mode.

package struct Coordinates: Equatable, Codable {
    package let latitude: Double
    package let longitude: Double

    package init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Sun position

/// The sun's elevation above the horizon in degrees, without refraction (NOAA's solar position algorithm, good to
/// about a minute of sunrise time between 1900 and 2100).
package func solarElevation(at date: Date, at place: Coordinates) -> Double {
    let julianDay = date.timeIntervalSince1970 / 86400 + 2_440_587.5
    let jc = (julianDay - 2_451_545) / 36525  // Julian centuries since J2000
    let meanLongitude = (280.46646 + jc * (36000.76983 + jc * 0.0003032)).truncatingRemainder(dividingBy: 360)
    let meanAnomaly = 357.52911 + jc * (35999.05029 - 0.0001537 * jc)
    let eccentricity = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
    let centre = sin(radians(meanAnomaly)) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
        + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * jc)
        + sin(radians(3 * meanAnomaly)) * 0.000289
    let omega = 125.04 - 1934.136 * jc
    let apparentLongitude = meanLongitude + centre - 0.00569 - 0.00478 * sin(radians(omega))
    let meanObliquity = 23 + (26 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60) / 60
    let obliquity = meanObliquity + 0.00256 * cos(radians(omega))
    let declination = asin(sin(radians(obliquity)) * sin(radians(apparentLongitude)))

    let yTerm = pow(tan(radians(obliquity) / 2), 2)
    let l0 = radians(meanLongitude)
    let anomaly = radians(meanAnomaly)
    let equationOfTime = 4 * degrees(
        yTerm * sin(2 * l0) - 2 * eccentricity * sin(anomaly) + 4 * eccentricity * yTerm * sin(anomaly) * cos(2 * l0)
            - 0.5 * yTerm * yTerm * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * anomaly))

    let minutesUTC = (date.timeIntervalSince1970 / 60).truncatingRemainder(dividingBy: 1440)
    let trueSolarMinutes = minutesUTC + equationOfTime + 4 * place.longitude
    let hourAngle = radians(trueSolarMinutes / 4 - 180)
    let latitude = radians(place.latitude)
    let cosZenith = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)
    return 90 - degrees(acos(min(1, max(-1, cosZenith))))
}

// MARK: - Daylight curve

package enum DaylightRules {
    /// Civil twilight ends: below this it is night.
    package static let nightElevation = -6.0
    /// From here up it is full day, so a low winter noon sun still counts.
    package static let dayElevation = 25.0
}

/// Daylight from 0 (night) to 1 (full day), easing in and out between the two elevations.
/// (Not `daylight`: Darwin already exports a global of that name.)
package func daylightLevel(solarElevation elevation: Double) -> Double {
    let span = DaylightRules.dayElevation - DaylightRules.nightElevation
    let progress = min(1, max(0, (elevation - DaylightRules.nightElevation) / span))
    return progress * progress * (3 - 2 * progress)
}

package func daylightLevel(at date: Date, at place: Coordinates) -> Double {
    daylightLevel(solarElevation: solarElevation(at: date, at: place))
}

// MARK: - Target brightness

/// Each video's place from darkest (0) to brightest (1), evenly spaced whatever the luminance gaps, so the Target
/// brightness means the same with any library. Ties go by name so the order is stable; a lone video sits at 0.5.
package func brightnessRanks(_ videos: [EligibleVideo]) -> [String: Double] {
    let sorted = videos.sorted { ($0.meanLuminance, $0.name) < ($1.meanLuminance, $1.name) }
    let last = Double(max(sorted.count - 1, 1))
    let pairs = sorted.enumerated().map { ($1.name, sorted.count == 1 ? 0.5 : Double($0) / last) }
    return Dictionary(pairs) { first, _ in first }
}

// MARK: - Location

package enum LocationSource: String {
    /// A Location Services fix taken this run.
    case fix
    /// The last fix from an earlier run, taken in the current time zone.
    case cache
    /// The reference city of the current time zone (`zone.tab`): no permission needed, up to ~30 min off at sunrise.
    case timeZone = "timezone"
}

/// The last fix, stored between runs so a launch without Location Services still knows roughly where it is.
package struct LocationCache: Equatable, Codable {
    package let coordinates: Coordinates
    package let timeZone: String

    package init(coordinates: Coordinates, timeZone: String) {
        self.coordinates = coordinates
        self.timeZone = timeZone
    }
}

/// Stored and logged locations are rounded to a tenth of a degree (about 10 km): enough for sun times, no more.
package func roundedForPrivacy(_ place: Coordinates) -> Coordinates {
    Coordinates(
        latitude: (place.latitude * 10).rounded() / 10, longitude: (place.longitude * 10).rounded() / 10)
}

package struct ResolvedLocation: Equatable {
    package let coordinates: Coordinates
    package let source: LocationSource

    package init(coordinates: Coordinates, source: LocationSource) {
        self.coordinates = coordinates
        self.source = source
    }
}

/// Where Daylight is computed for: this run's fix, else the cached fix, each only if taken in the current time zone
/// (after travel both may be far away until a new fix arrives), else the time zone's reference city. Nil only for a
/// zone with no place, e.g. UTC.
package func resolveLocation(
    fix: LocationCache?, cached: LocationCache?, timeZone: String, zones: [String: Coordinates]
) -> ResolvedLocation? {
    if let fix, fix.timeZone == timeZone {
        return ResolvedLocation(coordinates: roundedForPrivacy(fix.coordinates), source: .fix)
    }
    if let cached, cached.timeZone == timeZone {
        return ResolvedLocation(coordinates: cached.coordinates, source: .cache)
    }
    return zones[timeZone].map { ResolvedLocation(coordinates: $0, source: .timeZone) }
}

/// What Daylight was worked out from: the sun at a location, or the appearance when there is no place at all.
package enum DaylightBasis: Equatable, CustomStringConvertible {
    case sun(LocationSource)
    case appearance

    package var description: String {
        switch self {
        case .sun(let source): return source.rawValue
        case .appearance: return "appearance"
        }
    }
}

/// Daylight now. With no place (a time zone like UTC and no fix) the appearance stands in: Dark as night, Light as
/// day, so `dynamic` still means something.
package func currentDaylight(
    at date: Date, location: ResolvedLocation?, appearance: Appearance
) -> (level: Double, basis: DaylightBasis) {
    guard let location else { return (appearance == .dark ? 0 : 1, .appearance) }
    return (daylightLevel(at: date, at: location.coordinates), .sun(location.source))
}

/// The time zone identifiers in `/usr/share/zoneinfo/zone.tab` with their reference city's coordinates.
package func parseZoneTab(_ text: String) -> [String: Coordinates] {
    var zones: [String: Coordinates] = [:]
    for line in text.split(separator: "\n") where !line.hasPrefix("#") {
        let fields = line.split(separator: "\t")
        guard fields.count >= 3, let place = parseISO6709(String(fields[1])) else { continue }
        zones[String(fields[2])] = place
    }
    return zones
}

/// `±DDMM[SS]±DDDMM[SS]`, as zone.tab writes it.
private func parseISO6709(_ text: String) -> Coordinates? {
    guard let split = text.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
    guard let latitude = parseAngle(text[..<split], degreeDigits: 2),
          let longitude = parseAngle(text[split...], degreeDigits: 3)
    else { return nil }
    return Coordinates(latitude: latitude, longitude: longitude)
}

private func parseAngle(_ text: Substring, degreeDigits: Int) -> Double? {
    guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
    let digits = Array(text.dropFirst())
    guard digits.count == degreeDigits + 2 || digits.count == degreeDigits + 4,
          digits.allSatisfy(\.isNumber)
    else { return nil }
    let parts = stride(from: degreeDigits, to: digits.count, by: 2).map { Double(String(digits[$0..<$0 + 2])) ?? 0 }
    guard let degrees = Double(String(digits[0..<degreeDigits])) else { return nil }
    let value = degrees + parts[0] / 60 + (parts.count > 1 ? parts[1] / 3600 : 0)
    return sign == "-" ? -value : value
}

private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
