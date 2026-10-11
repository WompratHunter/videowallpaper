import Foundation
import SharedKernel

// MARK: - Daylight service
// Where Daylight is computed for, and Daylight now. A one-shot Location Services fix (asked for only once `dynamic`
// is in effect, at launch, on wake and on a time zone change), else the last fix cached between runs if it was taken
// in this time zone, else the time zone's reference city. The choice is `resolveLocation`; this only talks to the
// ports. Only rounded coordinates are kept or logged. With no place at all, the system appearance stands in.

@MainActor
public final class DaylightService {
    /// Daylight's events, on the main actor; the coordinator sets it.
    public var onEvent: (DaylightEvent) -> Void = { _ in }
    /// The last Daylight worked out and its source.
    public private(set) var slice = DaylightSlice()

    private let location: LocationPort
    private let places: TimeZonePlacesPort
    private let cache: LocationCachePort
    private let appearance: AppearancePort
    private let now: () -> Date
    private let debugLocation: Coordinates?
    private let zones: [String: Coordinates]
    /// This run's fix, with the time zone it was taken in.
    private var fix: LocationCache?
    /// The last fix from an earlier run, read when Daylight is first worked out.
    private lazy var cached: LocationCache? = cache.load()
    private var isActive = false
    private var loggedLocation: LogLine?

    /// `now` is the clock port's wall clock (a debug build may run it from another time). `debugLocation` replaces
    /// every source, as a fix; Platform passes it only in a debug build.
    public init(
        location: LocationPort,
        places: TimeZonePlacesPort,
        cache: LocationCachePort,
        appearance: AppearancePort,
        now: @escaping () -> Date,
        debugLocation: Coordinates? = nil
    ) {
        self.location = location
        self.places = places
        self.cache = cache
        self.appearance = appearance
        self.now = now
        self.debugLocation = debugLocation
        zones = places.places
        location.onUpdate = { [weak self] update in self?.apply(update) }
    }

    /// Daylight now, for the Rotation's Target brightness.
    public func current() -> DaylightReading {
        let reading = currentDaylight(at: now(), location: resolved(), appearance: appearance.current)
        slice = DaylightSlice(level: reading.level, source: reading.basis)
        return reading
    }

    /// Asks for permission the first time (macOS never asks again once denied), then for a fix. Idempotent, so the
    /// Rotation can call it on every decision that wants Daylight.
    public func activate() {
        guard !isActive else { return }
        isActive = true
        location.start()
        requestFix(cause: .launch)
    }

    /// Wake: ask for a new fix, if Daylight is in use.
    public func noteWake() {
        guard isActive else { return }
        requestFix(cause: .wake)
    }

    /// Travel: the cached fix and the time zone's city may both be elsewhere now. A fix from another time zone is
    /// already ignored by `resolveLocation`.
    public func timeZoneChanged() {
        emit(.timeZoneChanged(places.currentTimeZone))
        guard isActive else { return }
        requestFix(cause: .timeZone)
    }

    // MARK: - Location

    /// Resolves the location to use now (reported when it changes); nil only in a time zone with no place (e.g. UTC).
    private func resolved() -> ResolvedLocation? {
        if let debugLocation { return ResolvedLocation(coordinates: debugLocation, source: .fix) }
        let timeZone = places.currentTimeZone
        let location = resolveLocation(fix: fix, cached: cached, timeZone: timeZone, zones: zones)
        let event = location.map { DaylightEvent.locationResolved(source: $0.source, at: $0.coordinates) }
            ?? .locationUnavailable(timeZone: timeZone)
        if event.logLine != loggedLocation {
            loggedLocation = event.logLine
            emit(event)
        }
        return location
    }

    private func requestFix(cause: LocationRequestCause) {
        switch location.authorization {
        case .notDetermined:
            emit(.askingForAuthorization(cause: cause))
            location.requestAuthorization()
        case .authorized:
            location.requestFix()
        case .restricted, .denied, .unknown:
            break
        }
    }

    private func apply(_ update: LocationUpdate) {
        switch update {
        case .authorizationChanged(let status):
            emit(.authorizationChanged(status))
            if status == .authorized { location.requestFix() }
        case .fixed(let precise):
            let place = roundedForPrivacy(precise)
            let record = LocationCache(coordinates: place, timeZone: places.currentTimeZone)
            fix = record
            cached = record
            emit(.fixed(at: place))
            do {
                try cache.save(record)
            } catch {
                emit(.fixNotCached(reason: error.localizedDescription))
            }
        case .failed(let reason):
            emit(.fixFailed(reason: reason))
        }
    }

    private func emit(_ event: DaylightEvent) {
        onEvent(event)
    }
}
