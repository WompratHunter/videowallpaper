import Daylight
import Foundation
import SharedKernel
import TestSupport
import Testing

// MARK: - Daylight service tests
// The service on fakes of its ports: when Location Services is asked, what is kept of a fix, which source Daylight
// comes from, and the log lines, which read exactly as the lines the app wrote before events existed.

@MainActor
struct DaylightServiceTests {
    private let fakes = FakeDaylight()
    private let service: DaylightService
    private var lines: [String] { events.compactMap { $0.logLine.map { "\($0.cause): \($0.message)" } } }
    private var events: [DaylightEvent] { recorder.events }
    private let recorder = Recorder()

    /// Noon in New York (17:00 UTC), 21 December 2026: full day.
    private static let noon = Date(timeIntervalSince1970: 1_797_872_400)

    final class Recorder {
        var events: [DaylightEvent] = []
    }

    init() {
        service = fakes.service { Self.noon }
        service.onEvent = { [recorder] event in recorder.events.append(event) }
    }

    @Test func nothingIsAskedUntilActivated() {
        service.noteWake()
        service.timeZoneChanged()
        #expect(!fakes.location.wasAsked)
        #expect(lines == ["timezone: timezone=America/New_York"])
    }

    @Test func activatingAsksForPermissionOnce() {
        service.activate()
        service.activate()
        #expect(fakes.location.isStarted)
        #expect(fakes.location.authorizationRequests == 1)
        #expect(lines == ["location: asking for Location Services on=launch"])
    }

    @Test func grantedPermissionAsksForAFix() {
        service.activate()
        fakes.location.report(.authorizationChanged(.authorized))
        #expect(fakes.location.fixRequests == 1)
        service.noteWake()
        #expect(fakes.location.fixRequests == 2)
        service.timeZoneChanged()
        #expect(fakes.location.fixRequests == 3)
        #expect(lines.last == "timezone: timezone=America/New_York")
        #expect(lines.contains("location: authorization=authorized"))
    }

    @Test func aDeniedRequestIsNotRepeated() {
        fakes.location.authorization = .denied
        service.activate()
        service.noteWake()
        #expect(fakes.location.authorizationRequests == 0)
        #expect(fakes.location.fixRequests == 0)
    }

    @Test func aFixIsRoundedKeptAndUsed() {
        service.activate()
        fakes.location.report(.fixed(Coordinates(latitude: 42.361_45, longitude: -71.057_08)))
        let kept = LocationCache(
            coordinates: Coordinates(latitude: 42.4, longitude: -71.1), timeZone: "America/New_York")
        #expect(fakes.cache.stored == kept)
        #expect(service.current().basis == .sun(.fix))
        #expect(service.slice.source == .sun(.fix))
        #expect(lines.suffix(2) == ["location: fix at=42.4,-71.1", "location: source=fix at=42.4,-71.1"])
    }

    @Test func aFixThatCannotBeCachedIsStillUsed() {
        fakes.cache.saveError = CocoaError(.fileWriteNoPermission)
        service.activate()
        fakes.location.report(.fixed(Coordinates(latitude: 42.36, longitude: -71.06)))
        #expect(lines.last?.hasPrefix("location: cannot cache the fix: ") == true)
        #expect(service.current().basis == .sun(.fix))
    }

    @Test func aFailedFixIsLogged() {
        service.activate()
        fakes.location.report(.failed(reason: "The operation couldn’t be completed."))
        #expect(lines.last == "location: fix failed: The operation couldn’t be completed.")
    }

    @Test func theSourceIsLoggedOnlyWhenItChanges() {
        _ = service.current()
        _ = service.current()
        #expect(lines == ["location: source=timezone at=40.7,-74.0"])
        fakes.places.currentTimeZone = "UTC"
        fakes.appearance.current = .dark
        let reading = service.current()
        #expect(reading == DaylightReading(level: 0, basis: .appearance))
        #expect(lines.last == "location: source=none timezone=UTC")
        #expect(service.slice == DaylightSlice(level: 0, source: .appearance))
    }

    /// A debug build's `VIDEOWALLPAPER_LOCATION` replaces every source but is never logged, as before, so its
    /// precise coordinates reach no event.
    @Test func aDebugLocationIsUsedButNeverReported() {
        let debug = DaylightService(
            location: fakes.location, places: fakes.places, cache: fakes.cache, appearance: fakes.appearance,
            now: { Self.noon }, debugLocation: Coordinates(latitude: 42.361_45, longitude: -71.057_08))
        debug.onEvent = { [recorder] event in recorder.events.append(event) }
        #expect(debug.current().basis == .sun(.fix))
        #expect(events.isEmpty)
        #expect(debug.slice.source == .sun(.fix))
    }

    @Test func theSliceHoldsTheLastReadingAndNoCoordinates() {
        #expect(service.slice == DaylightSlice())
        let reading = service.current()
        #expect(reading.level == 1)
        #expect(service.slice == DaylightSlice(level: 1, source: .sun(.timeZone)))
        #expect(service.slice.targetBrightness == 1)
    }
}

// MARK: - Log lines

@Test(arguments: [
    (DaylightEvent.timeZoneChanged("Europe/London"), "timezone", "timezone=Europe/London"),
    (.locationResolved(source: .cache, at: Coordinates(latitude: 42.4, longitude: -71.1)),
     "location", "source=cache at=42.4,-71.1"),
    (.locationUnavailable(timeZone: "UTC"), "location", "source=none timezone=UTC"),
    (.askingForAuthorization(cause: .timeZone), "location", "asking for Location Services on=timezone"),
    (.authorizationChanged(.notDetermined), "location", "authorization=not-determined"),
    (.fixed(at: Coordinates(latitude: -33.9, longitude: 151.2)), "location", "fix at=-33.9,151.2"),
    (.fixNotCached(reason: "disk full"), "location", "cannot cache the fix: disk full"),
    (.fixFailed(reason: "denied"), "location", "fix failed: denied")
])
func eachEventLogsAsBefore(event: DaylightEvent, cause: String, message: String) {
    #expect(event.logLine == LogLine(cause: cause, message: message))
}
