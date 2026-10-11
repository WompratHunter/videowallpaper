import Foundation
import SharedKernel

// MARK: - Daylight events
// What Daylight tells the rest of the app, in order, on the main actor. Each case has its single log rendering here;
// Platform's log sink writes it. Coordinates appear only to a tenth of a degree (about 10 km), never precisely.

public enum DaylightEvent: Equatable {
    /// The time zone changed (travel); logged whether or not Daylight is in use.
    case timeZoneChanged(String)
    /// Daylight is now worked out for a different place or source. `at` is never a precise fix: a fix is rounded
    /// before it is kept, and a time zone's place is its reference city.
    case locationResolved(source: LocationSource, at: Coordinates)
    /// No place to compute the sun for (a time zone like UTC and no fix): the appearance stands in.
    case locationUnavailable(timeZone: String)
    /// Location Services is asked for the first time.
    case askingForAuthorization(cause: LocationRequestCause)
    case authorizationChanged(LocationAuthorization)
    /// A new fix, already rounded.
    case fixed(at: Coordinates)
    case fixNotCached(reason: String)
    case fixFailed(reason: String)
}

/// What asked for a new fix; it is also the log's `on=`.
public enum LocationRequestCause: String, Equatable, Sendable {
    case launch
    case wake
    case timeZone = "timezone"
}

extension DaylightEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {
        case .timeZoneChanged(let identifier):
            return LogLine(cause: "timezone", message: "timezone=\(identifier)")
        case let .locationResolved(source, place):
            return location("source=\(source.rawValue) at=\(Self.describe(place))")
        case .locationUnavailable(let timeZone):
            return location("source=none timezone=\(timeZone)")
        case .askingForAuthorization(let cause):
            return location("asking for Location Services on=\(cause.rawValue)")
        case .authorizationChanged(let status):
            return location("authorization=\(status.rawValue)")
        case .fixed(let place):
            return location("fix at=\(Self.describe(place))")
        case .fixNotCached(let reason):
            return location("cannot cache the fix: \(reason)")
        case .fixFailed(let reason):
            return location("fix failed: \(reason)")
        }
    }

    private func location(_ message: String) -> LogLine {
        LogLine(cause: "location", message: message)
    }

    private static func describe(_ place: Coordinates) -> String {
        String(format: "%.1f,%.1f", place.latitude, place.longitude)
    }
}
