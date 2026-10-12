import Playback

// MARK: - Playback adapters

extension Composition {
    static func playback() -> PlaybackService {
        let player = SharedPlayer()
        return PlaybackService(
            player: player,
            windows: WallpaperWindows(player: player),
            power: ProcessInfoPower(),
            screens: WorkspaceScreenSession(),
            clock: DispatchPlaybackClock())
    }
}
