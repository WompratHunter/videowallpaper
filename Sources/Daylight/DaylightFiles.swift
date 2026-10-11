import Foundation

// MARK: - Daylight file adapters
// The time-zone-places and location-cache ports over files, Foundation only. Platform hands in the paths: the system
// `zone.tab` (a bundled table can replace it later) and the cache in Application Support.

/// Every time zone's reference city from a `zone.tab` file, read once.
public final class ZoneTabPlaces: TimeZonePlacesPort {
    public let places: [String: Coordinates]

    public init(file: URL) {
        places = (try? String(contentsOf: file, encoding: .utf8)).map(parseZoneTab) ?? [:]
    }

    public var currentTimeZone: String { TimeZone.current.identifier }
}

/// The last fix as JSON. A missing or unreadable file reads as no fix.
public final class LocationCacheFile: LocationCachePort {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func load() -> LocationCache? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(LocationCache.self, from: $0) }
    }

    public func save(_ fix: LocationCache) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(fix).write(to: file, options: .atomic)
    }
}
