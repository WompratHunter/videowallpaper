import Testing

// MARK: - Library legacy suites
// The Wallpaper folder and settle check, Poster files, flash screening and the Analysis cache.

extension LegacySuites {
    @Test func library() {
        Self.run("Library") {
            runWallpaperFolderTests()
            runPosterFilesTests()
            runFlashTests()
            runAnalysisCacheTests()
        }
    }
}
