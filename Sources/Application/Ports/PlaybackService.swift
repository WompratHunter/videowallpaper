import Core
import Foundation
import Playback
import SharedKernel

// MARK: - Playback service
// Playback as the coordinator sees it: the shared player, the windows hosting its layers, and the power state, with
// today's `Player` and `WallpaperWindows` (Sources/App) and Platform's `ProcessInfoPower` as adapters. A seam for the
// move only: ticket 07 replaces it with the Playback context's own service, built on player/windows, power and
// screen/session ports, and swaps these fakes for fakes of those ports.

package protocol PlayerService: AnyObject {
    /// Picks the video to play when a rebuild runs (the Rotation's Current video), so a deleted file is replaced.
    var videoProvider: () -> URL? { get set }
    /// Called when the player switches to a different video, so its Poster follows.
    var onVideoChange: (URL) -> Void { get set }
    var video: URL? { get }

    func start()
    /// Switches with a crossfade of `fade` seconds; zero, or a player nobody can see, means a cut.
    func play(_ url: URL, fade: TimeInterval)
    func setPoster(_ poster: PosterImage)
    func folderChanged(toPlay: URL?, fade: TimeInterval)
    func apply(_ event: PlaybackGateEvent)
    /// Samples playback now and a moment later, logs the state, and rebuilds only if not actually playing.
    func verifyPlayback(cause: String)
    func resetBackoff(on event: RecoveryBackoff.ResetEvent)
    func healthTick()
}

package protocol WallpaperWindowsService: AnyObject {
    /// Whether every window is covered by opaque windows, on each build and occlusion change.
    var onOcclusionChange: (Bool) -> Void { get set }
    /// One window per connected screen.
    func rebuild()
    /// The window level and order can be lost across wake and Space switches.
    func reassert()
}

package protocol PowerPort: AnyObject {
    var isLowPowerModeEnabled: Bool { get }
}

package struct PlaybackService {
    package let player: PlayerService
    package let windows: WallpaperWindowsService
    package let power: PowerPort

    package init(player: PlayerService, windows: WallpaperWindowsService, power: PowerPort) {
        self.player = player
        self.windows = windows
        self.power = power
    }

    package var slice: PlaybackSlice { PlaybackSlice() }
}
