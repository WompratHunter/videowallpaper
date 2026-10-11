import Application
import Daylight
import SharedKernel
import TestSupport
import Testing

// MARK: - Daylight routes
// Daylight through the coordinator, on fakes of its ports: Location Services is asked for only when `dynamic` Mode
// aims at Daylight, a denied request or a fix from another time zone falls back to the time zone's city, and the
// snapshot names the source but never coordinates.

@MainActor
struct DaylightRoutesTests {
    /// `dynamic` follows Daylight only with at least four eligible videos.
    private let videos = [
        AppHarness.video("night.mp4", 0.05),
        AppHarness.video("dusk.mp4", 0.16),
        AppHarness.video("dawn.mp4", 0.30),
        AppHarness.video("noon.mp4", 0.60)
    ]

    private func daylightLines(_ app: AppHarness) -> [String] {
        app.events.compactMap { event in
            guard case .daylight(let daylight) = event, let line = daylight.logLine else { return nil }
            return "\(line.cause): \(line.message)"
        }
    }

    @Test func locationServicesIsNotRequestedInAllMode() {
        let app = AppHarness(library: FakeLibrary(eligible: videos), preferences: Preferences(modeSetting: "all"))
        app.coordinator.launch()
        app.clock.advance(by: 60 * 60)
        app.coordinator.systemDidWake()

        #expect(!app.daylight.location.wasAsked)
        #expect(daylightLines(app).isEmpty)
        #expect(app.coordinator.snapshot.daylight == DaylightSlice())
    }

    @Test func dynamicModeAsksForLocationServicesOnce() {
        let app = AppHarness(library: FakeLibrary(eligible: videos), preferences: Preferences(modeSetting: "dynamic"))
        app.coordinator.launch()
        app.clock.advance(by: 60)

        #expect(app.daylight.location.isStarted)
        #expect(app.daylight.location.authorizationRequests == 1)
        #expect(daylightLines(app).first == "location: asking for Location Services on=launch")
    }

    @Test func deniedLocationFallsBackToTheTimeZone() {
        let app = AppHarness(library: FakeLibrary(eligible: videos), preferences: Preferences(modeSetting: "dynamic"))
        app.daylight.location.authorization = .denied
        app.coordinator.launch()
        app.daylight.location.report(.authorizationChanged(.denied))
        app.coordinator.systemDidWake()
        app.clock.advance(by: 60)

        #expect(app.daylight.location.authorizationRequests == 0)
        #expect(app.daylight.location.fixRequests == 0)
        #expect(app.coordinator.snapshot.daylight.source == .sun(.timeZone))
        #expect(daylightLines(app) == [
            "location: source=timezone at=40.7,-74.0",
            "location: authorization=denied"
        ])
    }

    @Test func aCachedFixFromAnotherTimeZoneIsIgnored() {
        let app = AppHarness(library: FakeLibrary(eligible: videos), preferences: Preferences(modeSetting: "dynamic"))
        app.daylight.location.authorization = .denied
        app.daylight.cache.stored = LocationCache(
            coordinates: Coordinates(latitude: 51.5, longitude: -0.1), timeZone: "Europe/London")
        app.coordinator.launch()

        #expect(app.coordinator.snapshot.daylight.source == .sun(.timeZone))
        #expect(daylightLines(app) == ["location: source=timezone at=40.7,-74.0"])

        // Back in London, the cached fix is trusted again.
        app.daylight.places.currentTimeZone = "Europe/London"
        app.coordinator.timeZoneChanged()
        app.clock.advance(by: 5)
        #expect(app.coordinator.snapshot.daylight.source == .sun(.cache))
        #expect(daylightLines(app).suffix(2) == [
            "timezone: timezone=Europe/London",
            "location: source=cache at=51.5,-0.1"
        ])
    }

    @Test func aNewFixIsUsedAndOnlyItsRoundedPlaceIsLogged() {
        let app = AppHarness(library: FakeLibrary(eligible: videos), preferences: Preferences(modeSetting: "dynamic"))
        app.daylight.location.authorization = .authorized
        app.coordinator.launch()
        #expect(app.daylight.location.fixRequests == 1)

        app.daylight.location.report(.fixed(Coordinates(latitude: 40.689_25, longitude: -74.044_50)))
        app.clock.advance(by: 5)

        #expect(app.coordinator.snapshot.daylight.source == .sun(.fix))
        #expect(daylightLines(app).suffix(2) == [
            "location: fix at=40.7,-74.0",
            "location: source=fix at=40.7,-74.0"
        ])
    }
}
