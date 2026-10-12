import Foundation
import SharedKernel

// MARK: - Playback slice
// Playback's part of the app snapshot: what the Live wallpaper is doing on purpose (the Playback state), whether
// Recovery is under way, the video on screen and whether every window is covered.

public struct PlaybackSlice: Equatable {
    public var state: PlaybackState
    public var recovery: RecoveryState
    /// The video the player holds; nil while only the Poster shows (before the first video, or Low Power Mode).
    public var video: VideoID?
    public var isEveryWindowOccluded: Bool

    public init(
        state: PlaybackState = .playing,
        recovery: RecoveryState = .idle,
        video: VideoID? = nil,
        isEveryWindowOccluded: Bool = false
    ) {
        self.state = state
        self.recovery = recovery
        self.video = video
        self.isEveryWindowOccluded = isEveryWindowOccluded
    }
}

/// Whether playback is failing against its intent, and what Recovery is doing about it.
public enum RecoveryState: Equatable, Sendable {
    /// No Recovery under way.
    case idle
    /// The player was dropped and is rebuilt `in` seconds after it was scheduled.
    case rebuilding(in: TimeInterval)
    /// Every attempt of the backoff was used: resting on the Poster until wake, unlock or a folder change.
    case resting
    /// No eligible video: resting on the Poster until one is added.
    case waitingForVideo
}
