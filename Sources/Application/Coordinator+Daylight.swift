// MARK: - Daylight routes
// When Daylight asks for a new location fix (wake, a time zone change) and what the Rotation is handed of it: the
// level and where it came from, never coordinates.

extension Coordinator {
    // MARK: - Daylight commands

    /// Location Services is asked for only once `dynamic` aims at Daylight, never for `all`, `light` or `dark`.
    func daylightForRotation() -> (level: Double, source: String) {
        daylight.activate()
        let reading = daylight.current()
        return (reading.level, reading.basis.description)
    }

    func daylightNoteWake() {
        daylight.refresh(cause: "wake")
    }

    // MARK: - System inputs

    /// Travel: the cached fix and the time zone's city may both be elsewhere now.
    package func timeZoneChanged() {
        daylight.refresh(cause: "timezone")
    }
}
