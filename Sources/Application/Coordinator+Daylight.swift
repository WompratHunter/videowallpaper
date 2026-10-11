import Daylight

// MARK: - Daylight routes
// Where Daylight's events go, when Daylight asks for a new location fix (wake, a time zone change) and what the
// Rotation is handed of it: the level and where it came from, never coordinates.

extension Coordinator {
    func connectDaylight() {
        daylight.onEvent = { [weak self] event in self?.emit(.daylight(event)) }
    }

    // MARK: - Daylight commands

    /// Location Services is asked for only once `dynamic` aims at Daylight, never for `all`, `light` or `dark`.
    func daylightForRotation() -> (level: Double, source: String) {
        daylight.activate()
        let reading = daylight.current()
        return (reading.level, reading.basis.description)
    }

    func daylightNoteWake() {
        daylight.noteWake()
    }

    // MARK: - System inputs

    /// Travel: the cached fix and the time zone's city may both be elsewhere now. Call it once the system time zone
    /// has been reset, so Daylight reads the new one.
    package func timeZoneChanged() {
        daylight.timeZoneChanged()
    }
}
