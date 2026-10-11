import Foundation
import Testing

// MARK: - Legacy suites
// The check-based suites, one test per context in `LegacySuites+<Context>.swift`, so every check still gates
// `make build` and a context's ticket deletes its own file once its suites are native swift-testing in its context's
// test target. Serialized, because the check counters are shared. New tests are native `@Test`s.

@Suite(.serialized)
struct LegacySuites {
    /// Runs one context's suites; any failed check has already recorded an issue at its own line.
    static func run(_ context: String, _ suites: () -> Void) {
        resetCheckCounts()
        suites()
        let summary = "\(context): \(checkCount - failedCheckCount)/\(checkCount) checks passed\n"
        FileHandle.standardError.write(Data(summary.utf8))
        #expect(checkCount > 0)
    }
}
