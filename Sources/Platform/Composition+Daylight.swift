import Application
import Daylight
import Foundation

// MARK: - Daylight adapters

extension Composition {
    static func daylight(clock: ClockPort) -> DaylightService {
        DaylightService(
            location: CoreLocationProvider(),
            places: ZoneTabPlaces(file: URL(fileURLWithPath: "/usr/share/zoneinfo/zone.tab")),
            cache: LocationCacheFile(file: AppFiles.locationCacheFile),
            appearance: SystemAppearance(),
            now: { [clock] in DaylightDebug.now(clock.now) },
            debugLocation: DaylightDebug.location)
    }
}

// MARK: - Debug location and clock

enum DaylightDebug {
    /// `VIDEOWALLPAPER_LOCATION=lat,lon`, honoured only by a `make debug` build.
    static var location: Coordinates? {
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
    static func now(_ wallClock: Date) -> Date {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let start = environment["VIDEOWALLPAPER_CLOCK"].flatMap(ISO8601DateFormatter().date(from:)) {
            let speed = environment["VIDEOWALLPAPER_CLOCK_SPEED"].flatMap(Double.init) ?? 1
            return start.addingTimeInterval(wallClock.timeIntervalSince(launchDate) * speed)
        }
        #endif
        return wallClock
    }

    /// Set the first time Daylight asks for the time, as before.
    private static let launchDate = Date()
}
