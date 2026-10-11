@testable import Core
import Foundation
import Testing

// MARK: - Legacy suites
// Every area's check-based suite runs here, in one test, so all of them still gate `make build`. Every area has a
// suite (some still empty), so a ticket adds checks to its own file without editing this one. New tests are native
// swift-testing `@Test`s.

@Test func everyLegacySuite() {
    // Shared
    runLogTests()
    // Player: Recovery, the playback gate, the wake/unlock state line and the crossfade
    runRecoveryTests()
    runPlaybackGateTests()
    runPlayerStateReportTests()
    runCrossfadeTests()
    // Library: Wallpaper folder, settle, Poster files, flash screening, Analysis cache
    runWallpaperFolderTests()
    runPosterFilesTests()
    runFlashTests()
    runAnalysisCacheTests()
    // Visibility
    runVisibilityClassificationTests()
    // Daylight: sun position, the Daylight curve and where the location comes from
    runDaylightTests()
    // Rotation
    runRotationTests()
    // Footprint: original desktop pictures and restore
    runFootprintTests()
    let summary = "\(checkCount - failedCheckCount)/\(checkCount) checks passed\n"
    FileHandle.standardError.write(Data(summary.utf8))
    #expect(checkCount > 0)
}
