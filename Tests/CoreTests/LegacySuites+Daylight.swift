import Testing

// MARK: - Daylight legacy suites
// Sun position, the Daylight curve and where the location comes from.

extension LegacySuites {
    @Test func daylight() {
        Self.run("Daylight") {
            runDaylightTests()
        }
    }
}
