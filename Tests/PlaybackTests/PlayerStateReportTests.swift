import Foundation
@testable import Playback
import Testing

// MARK: - Player state report tests

@Test func reportDescription() {
    let healthy = PlayerStateReport(
        playerStatus: "readyToPlay", itemStatus: "readyToPlay", itemError: nil,
        timeControl: "playing", waitingReason: nil, timeAdvanced: true)
    #expect(
        healthy.description
            == "player=readyToPlay item=readyToPlay error=none timeControl=playing waiting=none advanced=yes")

    let failed = PlayerStateReport(
        playerStatus: "readyToPlay", itemStatus: "failed",
        itemError: "Cannot Open (AVFoundationErrorDomain -11829)",
        timeControl: "waitingToPlayAtSpecifiedRate", waitingReason: "AVPlayerWaitingWithNoItemToPlayReason",
        timeAdvanced: false)
    #expect(
        failed.description
            == "player=readyToPlay item=failed error=\"Cannot Open (AVFoundationErrorDomain -11829)\" "
            + "timeControl=waitingToPlayAtSpecifiedRate waiting=AVPlayerWaitingWithNoItemToPlayReason advanced=no")

    #expect(PlayerStateReport.noPlayer.description == "player=none")

    let unknownAdvance = PlayerStateReport(
        playerStatus: "unknown", itemStatus: "none", itemError: nil,
        timeControl: "paused", waitingReason: nil, timeAdvanced: nil)
    #expect(unknownAdvance.description.hasSuffix("advanced=unknown"), "\(unknownAdvance.description)")
}

@Test func reportPlaybackAdvanced() {
    #expect(playbackAdvanced(from: 1.0, to: 1.5) == true)
    #expect(playbackAdvanced(from: 3.0, to: 3.0) == false)
    // A looper wrapping back to the start still counts as progress.
    #expect(playbackAdvanced(from: 19.8, to: 0.4) == true)
    #expect(playbackAdvanced(from: nil, to: 2.0) == nil)
    #expect(playbackAdvanced(from: 2.0, to: .nan) == nil)
}
