import Foundation
import SharedKernel

// MARK: - Rotation slice
// The Rotation's part of the app snapshot: the Current video, where every eligible Video stands in the Pass, Dwell so
// far with the minimum the next switch needs, and why the last switch happened.

public struct RotationSlice: Equatable, Sendable {
    /// The video the Live wallpaper is showing (or will, once Low Power Mode ends).
    public var current: VideoID?
    /// Every eligible Video as of the last decision, with its place in the Rotation.
    public var statuses: [VideoID: RotationStatus]
    /// Awake, unlocked time the Current video has been showing, as of the last decision.
    public var dwell: TimeInterval
    /// The Dwell the next switch needs at the Presence of the last decision; nil before the first decision.
    public var nextMinimumDwell: TimeInterval?
    /// Why the Current video was chosen; nil before the first switch.
    public var lastSwitch: SwitchReason?

    public init(
        current: VideoID? = nil,
        statuses: [VideoID: RotationStatus] = [:],
        dwell: TimeInterval = 0,
        nextMinimumDwell: TimeInterval? = nil,
        lastSwitch: SwitchReason? = nil
    ) {
        self.current = current
        self.statuses = statuses
        self.dwell = dwell
        self.nextMinimumDwell = nextMinimumDwell
        self.lastSwitch = lastSwitch
    }
}

/// Where an eligible Video stands in the Rotation.
public enum RotationStatus: Equatable, Sendable {
    case current
    /// Newly added: plays at the next allowed switch, in queue order (0 first).
    case queuedAsNew(position: Int)
    case playedThisPass
    /// Still to play this Pass.
    case unplayed
}

extension RotationState {
    /// Each eligible Video's status; the Current video is always played this Pass, so `current` wins.
    var statuses: [VideoID: RotationStatus] {
        var statuses: [VideoID: RotationStatus] = [:]
        for name in lastEligible {
            let id = VideoID(name)
            if name == current?.name {
                statuses[id] = .current
            } else if let position = pendingNew.firstIndex(of: name) {
                statuses[id] = .queuedAsNew(position: position)
            } else {
                statuses[id] = played.contains(name) ? .playedThisPass : .unplayed
            }
        }
        return statuses
    }
}
