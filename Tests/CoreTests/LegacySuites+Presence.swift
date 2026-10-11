import Testing

// MARK: - Presence legacy suites
// Unseen, Veiled and Visible: classification, coverage and veil tracking.

extension LegacySuites {
    @Test func presence() {
        Self.run("Presence") {
            runVisibilityClassificationTests()
        }
    }
}
