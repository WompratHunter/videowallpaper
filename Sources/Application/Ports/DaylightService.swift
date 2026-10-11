import Core
import Daylight

// MARK: - Daylight service
// Daylight as the coordinator sees it, with today's `DaylightLocation` (Sources/App) as its adapter. A seam for the
// move only: ticket 04 replaces it with the Daylight context's own service, built on location and time-zone-places
// ports and the clock port.

package protocol DaylightService: AnyObject {
    var slice: DaylightSlice { get }

    /// Asks for Location Services the first time, then for a fix. Idempotent.
    func activate()
    /// Wake or a time zone change: asks for a new fix, if active.
    func refresh(cause: String)
    /// Daylight now, from the sun where the Mac is, or from the appearance when there is no place.
    func current() -> (level: Double, basis: DaylightBasis)
}
