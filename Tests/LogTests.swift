import Foundation

// MARK: - Log tests

func runLogTests() {
    let utc = TimeZone(identifier: "UTC") ?? .current
    let plusOne = TimeZone(secondsFromGMT: 3600) ?? .current
    let instant = Date(timeIntervalSince1970: 1_791_032_645.25)

    checkEqual(
        Log.line(cause: "launch", message: "started", at: instant, timeZone: utc),
        "2026-10-03T13:04:05.250Z [launch] started\n")
    checkEqual(
        Log.line(cause: "wake", message: "x", at: instant, timeZone: plusOne),
        "2026-10-03T14:04:05.250+01:00 [wake] x\n")
    // Embedded newlines would split one event across lines and break grep-ability.
    checkEqual(
        Log.line(cause: "unlock", message: "a\nb\r\nc", at: instant, timeZone: utc),
        "2026-10-03T13:04:05.250Z [unlock] a b c\n")
}
