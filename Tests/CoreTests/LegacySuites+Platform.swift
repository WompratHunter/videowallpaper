import Testing

// MARK: - Platform legacy suites
// Log line formatting.

extension LegacySuites {
    @Test func platform() {
        Self.run("Platform") {
            runLogTests()
        }
    }
}
