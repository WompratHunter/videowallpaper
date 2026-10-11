import Application
import Core
import Daylight

// MARK: - Fake Daylight
// Stands in for the Daylight service until ticket 04 replaces it with fakes of the location and time-zone-places
// ports. Reports a fixed Daylight and counts the requests for Location Services.

package final class FakeDaylight: DaylightService {
    package var level = 1.0
    package private(set) var activations = 0

    package init() {}

    package var slice: DaylightSlice { DaylightSlice() }

    package func activate() {
        activations += 1
    }

    package func refresh(cause: String) {}

    package func current() -> (level: Double, basis: DaylightBasis) { (level, .sun(.timeZone)) }
}
