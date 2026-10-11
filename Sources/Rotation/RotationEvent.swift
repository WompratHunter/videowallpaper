import Foundation
import SharedKernel

// MARK: - Rotation events
// What the Rotation tells the rest of the app, in order, on the main actor. A case logs only once its line has moved
// here from the scheduler (ticket 08); until then `logLine` is nil and the scheduler still writes the line.

public enum RotationEvent: Equatable {
    /// A switch was decided. `isDeferred`: Low Power Mode, so it plays when Low Power Mode ends.
    case switchDecided(from: VideoID?, to: VideoID, reason: SwitchReason, fade: TimeInterval, isDeferred: Bool)
}

public enum SwitchReason: String, Equatable {
    case firstVideo = "first-video"
    case currentRemoved = "current-removed"
    case newVideo = "new-video"
    case modeChange = "mode-change"
    case offTarget = "off-target"
    case dwell
    case visibleFallback = "visible-fallback"
}

extension RotationEvent {
    /// Nil for events that aren't logged (yet).
    public var logLine: LogLine? {
        switch self {
        case .switchDecided:
            return nil
        }
    }
}
