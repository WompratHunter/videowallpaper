// MARK: - Daylight ports
// What Daylight needs from the system, each with today's behaviour as its adapter: Location Services (CoreLocation,
// built in Platform so this target never imports it), the time zone's reference places (`zone.tab`), the cached fix
// (a file in Application Support) and the system appearance (AppKit, built in Platform). Wall-clock time comes from
// the clock port, handed in by Platform as `now`.

/// Location Services as the user has set it for the app.
public enum LocationAuthorization: String, Equatable, Sendable {
    case notDetermined = "not-determined"
    case restricted
    case denied
    case authorized
    case unknown
}

/// What Location Services reports, once `start()` has been called.
public enum LocationUpdate: Equatable, Sendable {
    /// Also reported once when updates start, with the current authorization.
    case authorizationChanged(LocationAuthorization)
    /// A one-shot fix, precise: Daylight rounds it before keeping or logging it.
    case fixed(Coordinates)
    case failed(reason: String)
}

/// Location Services: authorization and a one-shot fix, on the main actor.
@MainActor
public protocol LocationPort: AnyObject {
    var authorization: LocationAuthorization { get }
    /// Updates, on the main thread.
    var onUpdate: (LocationUpdate) -> Void { get set }

    /// Starts delivering updates. Called once, when `dynamic` Mode first wants Daylight.
    func start()
    /// Asks the user for permission (macOS asks only once).
    func requestAuthorization()
    /// Asks for one fix, reported through `onUpdate`.
    func requestFix()
}

/// The current time zone and every time zone's reference place.
public protocol TimeZonePlacesPort: AnyObject {
    /// The current time zone's identifier, e.g. `Europe/London`.
    var currentTimeZone: String { get }
    /// Each time zone identifier's reference city. Read once, when Daylight is built.
    var places: [String: Coordinates] { get }
}

/// The last fix, kept between runs.
public protocol LocationCachePort: AnyObject {
    func load() -> LocationCache?
    func save(_ fix: LocationCache) throws
}

/// The system appearance, Daylight's stand-in when there is no place. Read on the main actor, as AppKit requires.
@MainActor
public protocol AppearancePort: AnyObject {
    var current: Appearance { get }
}
