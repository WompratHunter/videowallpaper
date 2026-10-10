import Foundation

// MARK: - Daylight tests
// Sunrise and sunset references are the published times (timeanddate.com / NOAA) for each place and date, converted
// to UTC; the sun's centre is 0.833° below the horizon at those moments (refraction plus the solar radius).

func runDaylightTests() {
    runSunPositionTests()
    runDaylightCurveTests()
    runLocationTests()
}

private let newYork = Coordinates(latitude: 40.7128, longitude: -74.0060)
private let london = Coordinates(latitude: 51.5074, longitude: -0.1278)
private let sydney = Coordinates(latitude: -33.8688, longitude: 151.2093)
private let tromso = Coordinates(latitude: 69.6492, longitude: 18.9553)

private func utc(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: text) else { fatalError("bad date \(text)") }
    return date
}

/// The first minute in `[start, start + 24 h)` at which the sun crosses the horizon going up (or down).
private func crossing(_ place: Coordinates, from start: Date, rising: Bool) -> Date? {
    let horizon = -0.833
    var previous = solarElevation(at: start, at: place)
    for minute in 1..<(24 * 60) {
        let time = start.addingTimeInterval(Double(minute) * 60)
        let elevation = solarElevation(at: time, at: place)
        if rising ? (previous < horizon && elevation >= horizon) : (previous >= horizon && elevation < horizon) {
            return time
        }
        previous = elevation
    }
    return nil
}

private func checkCrossing(
    _ place: Coordinates, from start: String, rising: Bool, expected: String, line: Int = #line
) {
    guard let actual = crossing(place, from: utc(start), rising: rising) else {
        check(false, "no \(rising ? "sunrise" : "sunset") after \(start)", line: line)
        return
    }
    let error = abs(actual.timeIntervalSince(utc(expected)))
    check(error <= 2 * 60, "expected \(expected), got \(actual) (off by \(Int(error))s)", line: line)
}

private func runSunPositionTests() {
    // New York, summer and winter solstice (EDT 05:25 / 20:31; EST 07:17 / 16:32).
    checkCrossing(newYork, from: "2026-06-21T04:00:00Z", rising: true, expected: "2026-06-21T09:25:00Z")
    checkCrossing(newYork, from: "2026-06-21T12:00:00Z", rising: false, expected: "2026-06-22T00:31:00Z")
    checkCrossing(newYork, from: "2026-12-21T05:00:00Z", rising: true, expected: "2026-12-21T12:17:00Z")
    checkCrossing(newYork, from: "2026-12-21T17:00:00Z", rising: false, expected: "2026-12-21T21:32:00Z")
    // London, summer solstice (BST 04:43 / 21:21).
    checkCrossing(london, from: "2026-06-21T00:00:00Z", rising: true, expected: "2026-06-21T03:43:00Z")
    checkCrossing(london, from: "2026-06-21T12:00:00Z", rising: false, expected: "2026-06-21T20:21:00Z")
    // Sydney, southern summer (AEDT 05:41 / 20:05).
    checkCrossing(sydney, from: "2026-12-20T12:00:00Z", rising: true, expected: "2026-12-20T18:41:00Z")
    checkCrossing(sydney, from: "2026-12-21T00:00:00Z", rising: false, expected: "2026-12-21T09:05:00Z")
    // Tromsø: midnight sun in June, polar night in December.
    check(crossing(tromso, from: utc("2026-06-21T00:00:00Z"), rising: false) == nil, "Tromsø sets in June")
    check(solarElevation(at: utc("2026-06-21T23:00:00Z"), at: tromso) > 0, "Tromsø midnight sun is up")
    check(crossing(tromso, from: utc("2026-12-21T00:00:00Z"), rising: true) == nil, "Tromsø rises in December")
    let polarNoon = solarElevation(at: utc("2026-12-21T10:45:00Z"), at: tromso)
    check(polarNoon < 0 && polarNoon > -6, "Tromsø December noon is civil twilight, got \(polarNoon)")
}

/// Night until civil twilight ends (sun 6° below), full day from 25° up, so a low winter noon still counts as day.
private func runDaylightCurveTests() {
    checkEqual(daylightLevel(solarElevation: -30), 0)
    checkEqual(daylightLevel(solarElevation: -6), 0)
    checkEqual(daylightLevel(solarElevation: 9.5), 0.5)
    checkEqual(daylightLevel(solarElevation: 25), 1)
    checkEqual(daylightLevel(solarElevation: 60), 1)
    check(daylightLevel(solarElevation: 0) < daylightLevel(solarElevation: 5), "Daylight rises with the sun")
    // New York, 21 December: dark before dawn, full day at noon (sun ~26°), dark again after dusk.
    checkEqual(daylightLevel(at: utc("2026-12-21T11:30:00Z"), at: newYork), 0)
    checkEqual(daylightLevel(at: utc("2026-12-21T17:00:00Z"), at: newYork), 1)
    checkEqual(daylightLevel(at: utc("2026-12-21T22:30:00Z"), at: newYork), 0)
    let morning = daylightLevel(at: utc("2026-12-21T13:30:00Z"), at: newYork)
    check(morning > 0.2 && morning < 0.8, "08:30 EST is mid-ramp, got \(morning)")
}

// MARK: - Location

private let zoneTab = """
# tz zone descriptions
#
# country-code	coordinates	TZ	comments
US	+404251-0740023	America/New_York	Eastern (most areas)
GB	+513030-0000731	Europe/London
AU	-3352+15113	Australia/Sydney	New South Wales (most areas)
"""

private func near(_ a: Coordinates?, _ b: Coordinates, line: Int = #line) {
    guard let a else { return check(false, "expected \(b), got nil", line: line) }
    let isNear = abs(a.latitude - b.latitude) < 0.001 && abs(a.longitude - b.longitude) < 0.001
    check(isNear, "expected \(b), got \(a)", line: line)
}

private func runLocationTests() {
    // zone.tab coordinates are ISO 6709: ±DDMM[SS] latitude then ±DDDMM[SS] longitude.
    let zones = parseZoneTab(zoneTab)
    checkEqual(zones.count, 3)
    near(zones["America/New_York"], Coordinates(latitude: 40.714_17, longitude: -74.006_39))
    near(zones["Europe/London"], Coordinates(latitude: 51.508_33, longitude: -0.125_28))
    near(zones["Australia/Sydney"], Coordinates(latitude: -33.866_67, longitude: 151.216_67))

    // Rounded to a tenth of a degree (about 10 km) before it is stored or logged.
    near(roundedForPrivacy(Coordinates(latitude: 40.712_84, longitude: -74.006_01)),
         Coordinates(latitude: 40.7, longitude: -74.0))

    // A fresh fix wins; then the cached fix; each only if taken in the current time zone; then the time zone's city.
    let boston = "America/New_York"
    let fix = LocationCache(coordinates: Coordinates(latitude: 42.36, longitude: -71.06), timeZone: boston)
    let cached = LocationCache(coordinates: Coordinates(latitude: 42.4, longitude: -71.1), timeZone: boston)
    let fromFix = resolveLocation(fix: fix, cached: cached, timeZone: boston, zones: zones)
    near(fromFix?.coordinates, Coordinates(latitude: 42.4, longitude: -71.1))
    checkEqual(fromFix?.source, .fix)
    let fromCache = resolveLocation(fix: nil, cached: cached, timeZone: boston, zones: zones)
    near(fromCache?.coordinates, cached.coordinates)
    checkEqual(fromCache?.source, .cache)
    // After travel, neither this run's fix nor the cache is trusted until a new fix arrives.
    let travelled = resolveLocation(fix: fix, cached: cached, timeZone: "Europe/London", zones: zones)
    near(travelled?.coordinates, Coordinates(latitude: 51.508_33, longitude: -0.125_28))
    checkEqual(travelled?.source, .timeZone)
    check(resolveLocation(fix: nil, cached: nil, timeZone: "UTC", zones: zones) == nil, "UTC has no place")

    // Daylight with a place comes from the sun; with none, the appearance stands in (Dark as night, Light as day).
    let noonInNewYork = ResolvedLocation(coordinates: newYork, source: .cache)
    let sunlit = currentDaylight(at: utc("2026-12-21T17:00:00Z"), location: noonInNewYork, appearance: .dark)
    checkEqual(sunlit.level, 1)
    checkEqual(sunlit.basis, .sun(.cache))
    checkEqual(currentDaylight(at: utc("2026-12-21T17:00:00Z"), location: nil, appearance: .dark).level, 0)
    let light = currentDaylight(at: utc("2026-12-21T05:00:00Z"), location: nil, appearance: .light)
    checkEqual(light.level, 1)
    checkEqual(light.basis, .appearance)
    checkEqual(light.basis.description, "appearance")
    checkEqual(DaylightBasis.sun(.timeZone).description, "timezone")
}
