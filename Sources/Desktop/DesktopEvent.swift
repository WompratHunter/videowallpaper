import Foundation
import SharedKernel

// MARK: - Desktop events
// What Desktop tells the rest of the app, in order, on the main actor. Each case has its single log rendering in
// `logLine`, reading as the line the app wrote before Desktop published events.

public enum DesktopEvent: Equatable, Sendable {
    /// The user's own pictures were recorded; `screens` lists every screen in the record, sorted.
    case originalsRecorded(screens: [String])
    case originalsNotRecorded(reason: String)
    /// The record exists but can't be decoded, so it is left as it is.
    case originalsUnreadable(location: String)
    /// The Poster became the desktop picture on these screens.
    case posterSet(URL, screens: [String])
    case posterNotSet(screen: String, reason: String)
    case restored(screen: String, picture: String)
    case restoreFailed(screen: String, reason: String)
    /// No screen shows a Poster that can be replaced.
    case nothingToRestore
}

extension DesktopEvent {
    /// Nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {
        case .originalsRecorded(let screens):
            return LogLine(cause: "desktop-picture", message: "recorded originals for screens=\(screens)")
        case .originalsNotRecorded(let reason):
            return LogLine(cause: "desktop-picture", message: "cannot record originals: \(reason)")
        case .originalsUnreadable(let location):
            return LogLine(cause: "desktop-picture", message: "cannot read \(location)")
        case .posterSet:
            return nil
        case let .posterNotSet(screen, reason):
            return LogLine(cause: "desktop-picture", message: "cannot set Poster on \(screen): \(reason)")
        case let .restored(screen, picture):
            return LogLine(cause: "restore", message: "screen=\(screen) picture=\(picture)")
        case let .restoreFailed(screen, reason):
            return LogLine(cause: "restore", message: "screen=\(screen) failed: \(reason)")
        case .nothingToRestore:
            return LogLine(cause: "restore", message: "no screen shows a Poster; nothing to restore")
        }
    }
}
