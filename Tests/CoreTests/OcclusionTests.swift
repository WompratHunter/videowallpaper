@testable import Core
import Testing

// MARK: - Occlusion tests
// Playback's occlusion rule, which stays in Core with `WallpaperWindows` until ticket 07 moves both.

@Test func everyWindowCoveredIsOccluded() {
    #expect(isEveryWindowOccluded(visibility: [false, false, false]))
}

@Test func oneVisibleDisplayKeepsPlaying() {
    #expect(!isEveryWindowOccluded(visibility: [false, true, false]))
}

@Test func noWindowsIsNotOccluded() {
    #expect(!isEveryWindowOccluded(visibility: []))
}
