import Testing

// MARK: - Playback legacy suites
// Recovery, the playback gate, the wake/unlock state line and the crossfade.

extension LegacySuites {
    @Test func playback() {
        Self.run("Playback") {
            runRecoveryTests()
            runPlaybackGateTests()
            runPlayerStateReportTests()
            runCrossfadeTests()
        }
    }
}
