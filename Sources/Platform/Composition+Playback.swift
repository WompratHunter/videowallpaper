import App
import Application

// MARK: - Playback adapters

extension Composition {
    static func playback() -> PlaybackService {
        let player = Player()
        return PlaybackService(player: player, windows: WallpaperWindows(player: player), power: ProcessInfoPower())
    }
}
