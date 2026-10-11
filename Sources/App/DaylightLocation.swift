import AppKit
import Application
import Core
import CoreLocation
import Daylight

// MARK: - Daylight location
// Where Daylight is computed for. A one-shot Location Services fix (asked for only once `dynamic` is in effect, at
// launch, on wake and on a time zone change), else the last fix cached in Application Support if it was taken in
// this time zone, else the time zone's reference city from `zone.tab`. The choice is Core's `resolveLocation`; this
// only talks to CoreLocation and the cache file. Only rounded coordinates are stored or logged. With no place at all,
// the system appearance stands in.

package final class DaylightLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let cacheFile: URL
    private let zones: [String: Coordinates]
    /// This run's fix, with the time zone it was taken in.
    private var fix: LocationCache?
    private var cached: LocationCache?
    private var isActive = false
    private var loggedLocation: String?

    package init(cacheFile: URL, zoneTab: URL = URL(fileURLWithPath: "/usr/share/zoneinfo/zone.tab")) {
        self.cacheFile = cacheFile
        zones = (try? String(contentsOf: zoneTab, encoding: .utf8)).map(parseZoneTab) ?? [:]
        cached = (try? Data(contentsOf: cacheFile)).flatMap { try? JSONDecoder().decode(LocationCache.self, from: $0) }
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Daylight now (Core's `currentDaylight`), at the debug clock's time in a `make debug` build.
    package func current() -> (level: Double, basis: DaylightBasis) {
        currentDaylight(at: Self.now(), location: resolved(), appearance: Self.currentAppearance())
    }

    /// Resolves the location to use now (logged when it changes); nil only in a time zone with no place (e.g. UTC).
    private func resolved() -> ResolvedLocation? {
        if let forced = Self.debugLocation { return ResolvedLocation(coordinates: forced, source: .fix) }
        let location = resolveLocation(fix: fix, cached: cached, timeZone: TimeZone.current.identifier, zones: zones)
        let description = location.map { "source=\($0.source.rawValue) at=\(Self.describe($0.coordinates))" }
            ?? "source=none timezone=\(TimeZone.current.identifier)"
        if description != loggedLocation {
            Log.write("location", description)
            loggedLocation = description
        }
        return location
    }

    /// Asks for permission the first time (macOS never asks again once denied), then for a fix. Idempotent, so the
    /// scheduler can call it on every decision that wants Daylight.
    package func activate() {
        guard !isActive else { return }
        isActive = true
        manager.delegate = self
        requestFix(cause: "launch")
    }

    /// Wake or a time zone change: ask for a new fix. A fix from another time zone is already ignored by Core.
    package func refresh(cause: String) {
        guard isActive else { return }
        requestFix(cause: cause)
    }

    private func requestFix(cause: String) {
        switch manager.authorizationStatus {
        case .notDetermined:
            Log.write("location", "asking for Location Services on=\(cause)")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    package func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Log.write("location", "authorization=\(Self.describe(status))")
        if status == .authorizedAlways { manager.requestLocation() }
    }

    package func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let place = roundedForPrivacy(Coordinates(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
        let record = LocationCache(coordinates: place, timeZone: TimeZone.current.identifier)
        fix = record
        cached = record
        Log.write("location", "fix at=\(Self.describe(place))")
        do {
            try FileManager.default.createDirectory(
                at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: cacheFile, options: .atomic)
        } catch {
            Log.write("location", "cannot cache the fix: \(error.localizedDescription)")
        }
    }

    package func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.write("location", "fix failed: \(error.localizedDescription)")
    }

    private static func describe(_ place: Coordinates) -> String {
        String(format: "%.1f,%.1f", place.latitude, place.longitude)
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not-determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorized"
        @unknown default: return "unknown"
        }
    }
}

extension DaylightLocation: DaylightService {
    package var slice: DaylightSlice { DaylightSlice() }

    private static func currentAppearance() -> Appearance {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

// MARK: - Debug location and clock

extension DaylightLocation {
    /// `VIDEOWALLPAPER_LOCATION=lat,lon`, honoured only by a `make debug` build.
    static var debugLocation: Coordinates? {
        #if DEBUG
        let parts = ProcessInfo.processInfo.environment["VIDEOWALLPAPER_LOCATION"]?
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let parts, parts.count == 2 else { return nil }
        return Coordinates(latitude: parts[0], longitude: parts[1])
        #else
        return nil
        #endif
    }

    /// The time Daylight is computed for. A `make debug` build can start it at `VIDEOWALLPAPER_CLOCK` (ISO 8601)
    /// and run it `VIDEOWALLPAPER_CLOCK_SPEED` times faster, to watch a dusk in minutes.
    static func now() -> Date {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let start = environment["VIDEOWALLPAPER_CLOCK"].flatMap(ISO8601DateFormatter().date(from:)) {
            let speed = environment["VIDEOWALLPAPER_CLOCK_SPEED"].flatMap(Double.init) ?? 1
            return start.addingTimeInterval(Date().timeIntervalSince(launchDate) * speed)
        }
        #endif
        return Date()
    }

    private static let launchDate = Date()
}
