// MARK: - Test runner entry point
// Each area's suite is registered here; the runner exits non-zero if any check failed. Every area has a suite
// (some still empty), so a ticket adds checks to its own file without editing this one.

// Shared
runLogTests()
// Player: Recovery, the playback gate and the wake/unlock state line
runRecoveryTests()
runPlaybackGateTests()
runPlayerStateReportTests()
// Library: Wallpaper folder, settle, Poster files
runWallpaperFolderTests()
runPosterFilesTests()
runFlashTests()
// Visibility
runVisibilityClassificationTests()
// Rotation
runRotationTests()
// Footprint: original desktop pictures and restore
runFootprintTests()
finishTests()
