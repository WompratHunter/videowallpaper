import Foundation
import SharedKernel

// MARK: - Library events
// What the Library tells the rest of the app, in order, on the main actor. Each case has its single log rendering
// here; Platform's log sink writes it, so the log and a future UI read the same facts.

public enum LibraryEvent: Equatable {
    /// The eligible set changed after a settle check or an Analysis. Rotation hears it before Playback rebuilds.
    case eligibleSetChanged(eligible: [EligibleVideo], cause: EligibilityCause)
    /// A settle check changed the settled Videos (the only ones that may be analysed and played).
    case settled(videos: [VideoID])
    case analysed(VideoID, version: Version, report: AnalysisReport)
    /// Low Power Mode cancelled this Analysis; it runs again first once Low Power Mode is off.
    case analysisPaused(VideoID)
    /// Retried only once the file changes; until then the Video doesn't play.
    case analysisFailed(VideoID, reason: String)
    case analysisCacheUnreadable
    case analysisCacheNotSaved(reason: String)
    /// Over the flash limit: left out of the Rotation. Reported once per change of verdict.
    case excluded(VideoID, flashesPerSecond: Double)
    /// Over the flash limit but in FlashOverride, so it plays. Reported once per change of verdict.
    case overridden(VideoID, flashesPerSecond: Double)
    case posterNotSaved(fileName: String, reason: String)
    /// No screened video yet at launch: this still covers the window.
    case launchUnderlay(fileName: String)
    case noLaunchUnderlay
    case legacyPosterRemoved
    case legacyPosterNotRemoved(reason: String)
    case folderNotWatched(path: String)
}

/// What one Analysis measured, and how long it took.
public struct AnalysisReport: Equatable {
    public let meanLuminance: Double
    public let flashesPerSecond: Double
    public let posterSeconds: Double
    public let took: TimeInterval

    public init(meanLuminance: Double, flashesPerSecond: Double, posterSeconds: Double, took: TimeInterval) {
        self.meanLuminance = meanLuminance
        self.flashesPerSecond = flashesPerSecond
        self.posterSeconds = posterSeconds
        self.took = took
    }
}

/// What changed the eligible set; it is also the log line's cause.
public enum EligibilityCause: String, Equatable {
    case analysis
    case folderChange = "folder-change"
}

extension LibraryEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {
        case let .eligibleSetChanged(eligible, cause):
            return LogLine(cause: cause.rawValue, message: "eligible videos=\(eligible.count)")
        case .settled(let videos):
            return LogLine(cause: "folder-change", message: "settled videos=\(videos.count)")
        case let .excluded(video, rate):
            let limit = Int(FlashVerdict.limitPerSecond)
            return LogLine(
                cause: "flash", message: "excluded video=\(video) flashes=\(Self.rate(rate))/s (limit \(limit)/s)")
        case let .overridden(video, rate):
            return LogLine(
                cause: "flash",
                message: "override video=\(video) flashes=\(Self.rate(rate))/s plays (in FlashOverride)")
        case let .posterNotSaved(fileName, reason):
            return LogLine(cause: "poster", message: "cannot save \(fileName): \(reason)")
        default:
            return analysisLine ?? launchLine
        }
    }

    private var analysisLine: LogLine? {
        let message: String
        switch self {
        case let .analysed(video, _, report):
            message = String(
                format: "video=%@ luminance=%.3f flashes=%.1f/s poster=%.2fs took=%.1fs", video.fileName,
                report.meanLuminance, report.flashesPerSecond, report.posterSeconds, report.took)
        case .analysisPaused(let video): message = "video=\(video) paused for Low Power Mode"
        case let .analysisFailed(video, reason): message = "video=\(video) failed: \(reason); it will not play"
        case .analysisCacheUnreadable:
            message = "cache unreadable or from another version; videos will be analysed again"
        case .analysisCacheNotSaved(let reason): message = "cannot save cache: \(reason)"
        default: return nil
        }
        return LogLine(cause: "analysis", message: message)
    }

    private var launchLine: LogLine? {
        let message: String
        switch self {
        case .launchUnderlay(let fileName): message = "no screened video yet; underlay=\(fileName)"
        case .noLaunchUnderlay: message = "no Poster or desktop picture to show under the video"
        case .legacyPosterRemoved: message = "removed legacy Poster from the Wallpaper folder"
        case .legacyPosterNotRemoved(let reason): message = "cannot remove legacy Poster: \(reason)"
        case .folderNotWatched(let path): message = "cannot watch \(path): folder changes will not be seen"
        default: return nil
        }
        return LogLine(cause: "launch", message: message)
    }

    private static func rate(_ flashesPerSecond: Double) -> String {
        String(format: "%.1f", flashesPerSecond)
    }
}
