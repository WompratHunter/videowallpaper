import Testing

// MARK: - Desktop legacy suites
// Recording the original desktop pictures and the restore plan.

extension LegacySuites {
    @Test func desktop() {
        Self.run("Desktop") {
            runFootprintTests()
        }
    }
}
