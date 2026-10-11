import Foundation
import SharedKernel

// MARK: - Rotation events
// What the Rotation tells the rest of the app, in order, on the main actor. Each event's log line is its single
// rendering, written by Platform's log sink; the lines read exactly as the scheduler wrote them before.

public enum RotationEvent: Equatable, Sendable {
    /// A switch was decided, with what the decision read.
    case switchDecided(SwitchDecision)
    /// A switch is due but every allowed video is too far in brightness: it waits for an Unseen moment. Sent once per
    /// wait, not on every decision while it lasts.
    case waitingForUnseen(presence: Presence)
    /// The Mode in effect, from the `Mode` setting and the auto-appearance flag; sent whenever any of the three changes.
    case modeInEffect(mode: RotationMode, setting: String?, isAutoAppearance: Bool)
    /// A debug build's shortened Dwell (`VIDEOWALLPAPER_DWELL_SCALE`), announced once when the Rotation is connected.
    case debugDwellScale(Double)
}

public enum SwitchReason: String, Equatable, Sendable {
    case firstVideo = "first-video"
    case currentRemoved = "current-removed"
    case newVideo = "new-video"
    case modeChange = "mode-change"
    case offTarget = "off-target"
    case dwell
    case visibleFallback = "visible-fallback"
}

/// A switch the Rotation decided, and what it read to decide it.
public struct SwitchDecision: Equatable, Sendable {
    public let from: VideoID?
    public let to: VideoID
    public let reason: SwitchReason
    public let fade: TimeInterval
    /// Low Power Mode: the Rotation moved on, and the new Current video plays when Low Power Mode ends.
    public let isDeferred: Bool
    /// What asked for the decision: `launch`, `tick`, `visibility`, `folder-change` or `rebuild`.
    public let cause: String
    /// The mean-luminance difference from the previous video; nil for the first.
    public let deltaL: Double?
    public let presence: Presence
    public let mode: RotationMode
    /// Set while `dynamic` aims at Daylight.
    public let target: TargetBrightness?
    /// The Dwell the previous video had reached.
    public let dwell: TimeInterval

    public init(
        from: VideoID?,
        to: VideoID,
        reason: SwitchReason,
        fade: TimeInterval,
        isDeferred: Bool,
        cause: String,
        deltaL: Double?,
        presence: Presence,
        mode: RotationMode,
        target: TargetBrightness?,
        dwell: TimeInterval
    ) {
        self.from = from
        self.to = to
        self.reason = reason
        self.fade = fade
        self.isDeferred = isDeferred
        self.cause = cause
        self.deltaL = deltaL
        self.presence = presence
        self.mode = mode
        self.target = target
        self.dwell = dwell
    }
}

/// Where `dynamic` aimed a pick: Daylight is the Target brightness, and the new video's rank shows how close it landed.
public struct TargetBrightness: Equatable, Sendable {
    public let daylight: Double
    public let pickRank: Double
    /// Where Daylight came from (a fix, the cache or the time zone), never coordinates.
    public let daylightSource: String

    public init(daylight: Double, pickRank: Double, daylightSource: String) {
        self.daylight = daylight
        self.pickRank = pickRank
        self.daylightSource = daylightSource
    }
}

// MARK: - Log lines

extension RotationEvent {
    public var logLine: LogLine {
        LogLine(cause: "rotation", message: message)
    }

    private var message: String {
        switch self {
        case .switchDecided(let decision):
            return decision.message
        case .waitingForUnseen(let presence):
            return "switch due but no allowed video within ΔL \(RotationRules.brightnessBand): "
                + "waiting for Unseen (visibility=\(presence.rawValue))"
        case .modeInEffect(let mode, let setting, let isAuto):
            return "mode=\(mode.rawValue) setting=\(setting ?? "none") auto-appearance=\(isAuto ? "yes" : "no")"
        case .debugDwellScale(let scale):
            return "debug Dwell scale=\(scale)"
        }
    }
}

extension SwitchDecision {
    fileprivate var message: String {
        let deltaL = deltaL.map { String(format: "%.3f", $0) } ?? "n/a"
        let daylight = target.map { target in
            String(format: "daylight=%.2f target=%.2f to-rank=%.2f daylight-source=%@ ",
                   target.daylight, target.daylight, target.pickRank, target.daylightSource)
        } ?? ""
        return "switch reason=\(reason.rawValue) on=\(cause) "
            + "from=\(from?.fileName ?? "none") to=\(to.fileName) ΔL=\(deltaL) fade=\(Int(fade))s "
            + "visibility=\(presence.rawValue) mode=\(mode.rawValue) " + daylight
            + "dwell=\(Int(dwell / 60))m"
            + (isDeferred ? " (Low Power Mode: plays when it ends)" : "")
    }
}
