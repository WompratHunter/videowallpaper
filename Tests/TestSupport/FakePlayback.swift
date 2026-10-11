import Application
import Core
import Foundation
import SharedKernel

// MARK: - Fake Playback
// Stands in for the player, windows and power state until ticket 07 replaces them with fakes of Playback's ports.
// Records what it was asked to play.

package final class FakePlayer: PlayerService {
    package var videoProvider: () -> URL? = { nil }
    package var onVideoChange: (URL) -> Void = { _ in }
    package private(set) var video: URL?
    /// Every video the player was told to show, by a start, a switch or a folder change, in order.
    package private(set) var played: [URL] = []

    package init() {}

    package func start() {
        show(videoProvider())
    }

    package func play(_ url: URL, fade: TimeInterval) {
        show(url)
    }

    package func setPoster(_ poster: PosterImage) {}

    package func folderChanged(toPlay: URL?, fade: TimeInterval) {
        show(toPlay)
    }

    package func apply(_ event: PlaybackGateEvent) {}

    package func verifyPlayback(cause: String) {}

    package func resetBackoff(on event: RecoveryBackoff.ResetEvent) {}

    package func healthTick() {}

    private func show(_ url: URL?) {
        guard let url, url != video else { return }
        video = url
        played.append(url)
        onVideoChange(url)
    }
}

package final class FakeWindows: WallpaperWindowsService {
    package var onOcclusionChange: (Bool) -> Void = { _ in }

    package init() {}

    package func rebuild() {}

    package func reassert() {}
}

package final class FakePower: PowerPort {
    package var isLowPowerModeEnabled: Bool

    package init(isLowPowerModeEnabled: Bool = false) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }
}
