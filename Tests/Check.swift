import Foundation

// MARK: - Check helper

private var failureCount = 0
private var checkCount = 0

func check(_ condition: Bool, _ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    checkCount += 1
    guard !condition else { return }
    failureCount += 1
    FileHandle.standardError.write(Data("FAIL \(file):\(line): \(message())\n".utf8))
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, file: String = #fileID, line: Int = #line) {
    check(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
}

func finishTests() -> Never {
    let summary = "\(checkCount - failureCount)/\(checkCount) checks passed\n"
    FileHandle.standardError.write(Data(summary.utf8))
    exit(failureCount == 0 ? 0 : 1)
}
