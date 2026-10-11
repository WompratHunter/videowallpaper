import Foundation
import Testing

// MARK: - Check helper
// The suites predate swift-testing: each failed check records an issue at the caller's line, so `swift test` fails
// without stopping the remaining checks. Only `LegacySuites` runs them, one context at a time (serialized), so the
// count isn't shared.

private(set) var checkCount = 0
private(set) var failedCheckCount = 0

func resetCheckCounts() {
    checkCount = 0
    failedCheckCount = 0
}

func check(
    _ condition: Bool,
    _ message: @autoclosure () -> String,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column
) {
    checkCount += 1
    guard !condition else { return }
    failedCheckCount += 1
    Issue.record(
        Comment(rawValue: message()),
        sourceLocation: SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column))
}

func checkEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column
) {
    check(
        actual == expected, "expected \(expected), got \(actual)",
        fileID: fileID, filePath: filePath, line: line, column: column)
}
