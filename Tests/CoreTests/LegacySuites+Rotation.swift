import Testing

// MARK: - Rotation legacy suites
// Mode, the pick, Dwell, scheduling, library changes, the Target brightness and the allowed transitions.

extension LegacySuites {
    @Test func rotation() {
        Self.run("Rotation") {
            runRotationTests()
        }
    }
}
