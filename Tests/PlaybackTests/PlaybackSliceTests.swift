@testable import Playback
import Testing

// MARK: - Playback slice and occlusion tests

@Test func playbackSliceStartsPlayingWithNoRecovery() {
    let slice = PlaybackSlice()
    #expect(slice.state == .playing)
    #expect(slice.recovery == .idle)
    #expect(slice.video == nil)
    #expect(!slice.isEveryWindowOccluded)
}

@Test func occlusionCountsOnlyEveryWindowCovered() {
    #expect(isEveryWindowOccluded(visibility: [false, false, false]), "every window covered")
    #expect(!isEveryWindowOccluded(visibility: [false, true, false]), "one visible display keeps playing")
    #expect(!isEveryWindowOccluded(visibility: []), "no windows is not occluded")
}
