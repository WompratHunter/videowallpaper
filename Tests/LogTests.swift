import Foundation

// MARK: - Log tests

func runLogTests() {
    runLogLineTests()
    runPlayerStateReportTests()
    runPlaybackAdvancedTests()
}

private func runLogLineTests() {
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

private func runPlayerStateReportTests() {
    let healthy = PlayerStateReport(
        playerStatus: "readyToPlay", itemStatus: "readyToPlay", itemError: nil,
        timeControl: "playing", waitingReason: nil, timeAdvanced: true)
    checkEqual(
        healthy.description,
        "player=readyToPlay item=readyToPlay error=none timeControl=playing waiting=none advanced=yes")

    let failed = PlayerStateReport(
        playerStatus: "readyToPlay", itemStatus: "failed",
        itemError: "Cannot Open (AVFoundationErrorDomain -11829)",
        timeControl: "waitingToPlayAtSpecifiedRate", waitingReason: "AVPlayerWaitingWithNoItemToPlayReason",
        timeAdvanced: false)
    checkEqual(
        failed.description,
        "player=readyToPlay item=failed error=\"Cannot Open (AVFoundationErrorDomain -11829)\" "
            + "timeControl=waitingToPlayAtSpecifiedRate waiting=AVPlayerWaitingWithNoItemToPlayReason advanced=no")

    checkEqual(PlayerStateReport.noPlayer.description, "player=none")

    let unknownAdvance = PlayerStateReport(
        playerStatus: "unknown", itemStatus: "none", itemError: nil,
        timeControl: "paused", waitingReason: nil, timeAdvanced: nil)
    check(unknownAdvance.description.hasSuffix("advanced=unknown"), unknownAdvance.description)
}

private func runPlaybackAdvancedTests() {
    checkEqual(playbackAdvanced(from: 1.0, to: 1.5), true)
    checkEqual(playbackAdvanced(from: 3.0, to: 3.0), false)
    // A looper wrapping back to the start still counts as progress.
    checkEqual(playbackAdvanced(from: 19.8, to: 0.4), true)
    checkEqual(playbackAdvanced(from: nil, to: 2.0), nil)
    checkEqual(playbackAdvanced(from: 2.0, to: .nan), nil)
}
