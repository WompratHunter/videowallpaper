import Foundation
import SharedKernel

// MARK: - Playback events
// What Playback tells the rest of the app, in order, on the main actor. Each case has its single log rendering in
// `logLine`, reading as the player, crossfader, windows and app delegate wrote it before; Platform's log sink writes
// it, so the log and a future UI read the same facts.

public enum PlaybackEvent: Equatable {
    /// Recovery, a build at launch or on leaving Low Power Mode, or a hold on the Poster.
    case recovery(RecoveryEvent)
    case crossfade(CrossfadeStep)
    /// A Playback input changed the Playback state; `action` is what the player did about it.
    case stateChanged(input: PlaybackInput, action: PlaybackGateAction, state: PlaybackState, video: VideoID?)
    /// The windows were built, or one's occlusion changed. The coordinator forwards it to the gate and to Presence.
    case occlusionChanged(OcclusionChange, isEveryWindowOccluded: Bool)
    /// A different video is now on screen (after a cut, a rebuild or a crossfade). Not logged: the step that led to
    /// it is.
    case videoShown(VideoID)
    /// A diagnostic sampled a second after launch, wake, unlock or session activation.
    case playerStateReported(cause: String, video: VideoID?, report: PlayerStateReport)
    case screensAsleep
    case lowPowerModeChanged(isOn: Bool)
}

public enum RecoveryEvent: Equatable {
    /// The player was dropped (the Poster shows) and is rebuilt after `delay` seconds.
    case scheduled(cause: RecoveryCause, video: VideoID?, position: Double, delay: TimeInterval, detail: String)
    /// Every attempt of the backoff was used: resting on the Poster until wake, unlock or a folder change.
    case resting(cause: RecoveryCause, video: VideoID?, attempts: Int, detail: String)
    /// No eligible video: resting on the Poster until one is added. Not a failure.
    case restingWithoutVideo(video: VideoID?, detail: String)
    /// A player was built for `video`, resuming at `at` seconds.
    case built(cause: BuildCause, video: VideoID, at: Double)
    /// Low Power Mode: no player is built; leaving it builds one.
    case heldForPower(cause: BuildCause)
    /// The folder changed in Low Power Mode: the Current video loads when it ends.
    case folderChangeHeldForPower
}

/// What led to building a player; it is also the log line's cause.
public enum BuildCause: String, Equatable, Sendable {
    case launch
    case recovery
    case power
}

public enum CrossfadeStep: Equatable {
    case cut(VideoID)
    case loading(VideoID)
    case fading(VideoID?, duration: TimeInterval)
    case done(VideoID)
    case droppedIncoming(VideoID?)
    /// Failed or never ready: the Current video carries on.
    case abandoned(VideoID)
    /// A broken invariant: asked to promote a video that wasn't loading, so it cuts instead.
    case promotedWithoutIncoming(VideoID)
}

public enum OcclusionChange: Equatable, Sendable {
    /// One window per screen was built.
    case windowsBuilt(count: Int)
    /// The window on screen `index` became visible or covered.
    case screen(index: Int, isVisible: Bool)
}

// MARK: - Log lines

extension PlaybackEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {
        case .recovery(let event):
            return event.logLine
        case .crossfade(let step):
            return LogLine(cause: "crossfade", message: step.logMessage)
        case let .stateChanged(input, action, state, video):
            return LogLine(
                cause: "playback",
                message: "event=\(input.logName) action=\(action.logName) mode=\(state.logName) video=\(name(video))")
        case let .occlusionChanged(change, isEveryWindowOccluded):
            return LogLine(
                cause: "occlusion", message: "\(change.logName) all-occluded=\(yesNo(isEveryWindowOccluded))")
        case .videoShown:
            return nil
        case let .playerStateReported(cause, video, report):
            return LogLine(cause: cause, message: "video=\(name(video)) \(report)")
        case .screensAsleep:
            return LogLine(cause: "screens-sleep", message: "pausing shared player")
        case .lowPowerModeChanged(let isOn):
            return LogLine(cause: "power", message: "low-power=\(isOn ? "on" : "off")")
        }
    }
}

extension RecoveryEvent {
    var logLine: LogLine {
        switch self {
        case let .scheduled(cause, video, position, delay, detail):
            return LogLine(
                cause: "recovery",
                message: "cause=\(cause.rawValue) video=\(name(video)) position=\(seconds(position)) "
                    + "rebuild-in=\(Int(delay))s \(detail)")
        case let .resting(cause, video, attempts, detail):
            return LogLine(
                cause: "recovery",
                message: "cause=\(cause.rawValue) video=\(name(video)) resting on Poster after \(attempts) attempts "
                    + detail)
        case let .restingWithoutVideo(video, detail):
            return LogLine(
                cause: "recovery",
                message: "cause=no-video video=\(name(video)) resting on Poster until a video is added \(detail)")
        case let .built(cause, video, at):
            let verb = cause == .launch ? "playing" : "rebuilding"
            return LogLine(cause: cause.rawValue, message: "\(verb) video=\(video) at=\(seconds(at))")
        case .heldForPower(let cause):
            return LogLine(cause: cause.rawValue, message: "Low Power Mode: holding on the Poster")
        case .folderChangeHeldForPower:
            return LogLine(cause: "folder-change", message: "Low Power Mode: the Current video loads when it ends")
        }
    }
}

extension CrossfadeStep {
    var logMessage: String {
        switch self {
        case .cut(let video): return "cut video=\(video)"
        case .loading(let video): return "loading video=\(video)"
        case let .fading(video, duration): return "fading video=\(name(video)) over=\(Int(duration))s"
        case .done(let video): return "done video=\(video)"
        case .droppedIncoming(let video): return "dropped incoming video=\(name(video))"
        case .abandoned(let video): return "abandoned video=\(video): failed or not ready; keeping the Current video"
        case .promotedWithoutIncoming(let video): return "promote without incoming video=\(video); cutting"
        }
    }
}

// MARK: - Log names
// Spelled out rather than taken from the case names, so a rename (as `mode` became Playback state) can't change the
// log.

extension PlaybackInput {
    var logName: String {
        switch self {
        case .lowPower(let isOn): return "lowPower(\(isOn))"
        case .screensAsleep(let isOn): return "screensAsleep(\(isOn))"
        case .allWindowsOccluded(let isOn): return "allWindowsOccluded(\(isOn))"
        }
    }
}

extension PlaybackGateAction {
    var logName: String {
        switch self {
        case .none: return "none"
        case .pause: return "pause"
        case .resume: return "resume"
        case .tearDown: return "tearDown"
        case .rebuild: return "rebuild"
        }
    }
}

extension PlaybackState {
    var logName: String {
        switch self {
        case .playing: return "playing"
        case .paused: return "paused"
        case .posterOnly: return "posterOnly"
        }
    }
}

extension OcclusionChange {
    var logName: String {
        switch self {
        case .windowsBuilt(let count): return "windows=\(count)"
        case let .screen(index, isVisible): return "screen=\(index) visible=\(yesNo(isVisible))"
        }
    }
}

private func name(_ video: VideoID?) -> String { video?.fileName ?? "none" }

private func seconds(_ value: Double) -> String { String(format: "%.1f", value) }

private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
