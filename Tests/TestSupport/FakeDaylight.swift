import Daylight
import Foundation

// MARK: - Fake Daylight
// Fakes of Daylight's ports, and `FakeDaylight`, which bundles them and builds the real `DaylightService` on them.
// Location Services starts undetermined and records what it is asked; tests report its answers with `report(_:)`.

@MainActor
package final class FakeLocation: LocationPort {
    package var authorization: LocationAuthorization = .notDetermined
    package var onUpdate: (LocationUpdate) -> Void = { _ in }
    package private(set) var isStarted = false
    package private(set) var authorizationRequests = 0
    package private(set) var fixRequests = 0

    package init() {}

    package func start() {
        isStarted = true
    }

    package func requestAuthorization() {
        authorizationRequests += 1
    }

    package func requestFix() {
        fixRequests += 1
    }

    /// What the system reports; an authorization change also updates `authorization`, as CoreLocation's does.
    package func report(_ update: LocationUpdate) {
        if case .authorizationChanged(let status) = update { authorization = status }
        onUpdate(update)
    }

    /// Whether Location Services was touched at all.
    package var wasAsked: Bool { isStarted || authorizationRequests > 0 || fixRequests > 0 }
}

package final class FakeTimeZonePlaces: TimeZonePlacesPort {
    package static let newYork = Coordinates(latitude: 40.714_17, longitude: -74.006_39)
    package static let london = Coordinates(latitude: 51.508_33, longitude: -0.125_28)

    package var currentTimeZone: String
    package let places: [String: Coordinates]

    package init(
        currentTimeZone: String = "America/New_York",
        places: [String: Coordinates] = ["America/New_York": newYork, "Europe/London": london]
    ) {
        self.currentTimeZone = currentTimeZone
        self.places = places
    }
}

package final class FakeLocationCache: LocationCachePort {
    /// Set before Daylight is first worked out to stand for a fix cached by an earlier run.
    package var stored: LocationCache?
    /// Set to make `save` fail with it.
    package var saveError: Error?

    package init(_ stored: LocationCache? = nil) {
        self.stored = stored
    }

    package func load() -> LocationCache? { stored }

    package func save(_ fix: LocationCache) throws {
        if let saveError { throw saveError }
        stored = fix
    }
}

@MainActor
package final class FakeAppearance: AppearancePort {
    package var current: Appearance = .light

    package init() {}
}

/// Daylight's port fakes, and the real service built on them with the given wall clock.
@MainActor
package final class FakeDaylight {
    package let location = FakeLocation()
    package let appearance = FakeAppearance()
    package let places = FakeTimeZonePlaces()
    package let cache = FakeLocationCache()

    package init() {}

    package func service(now: @escaping () -> Date) -> DaylightService {
        DaylightService(location: location, places: places, cache: cache, appearance: appearance, now: now)
    }
}
