import Daylight
import Desktop
import Library
import Playback
import Presence
import Rotation
import SharedKernel

// MARK: - App events
// Everything that happens, as one typed stream: one case per context, wrapping that context's own events (declared
// in the context), plus the Application layer's own. Delivered in order on the main actor to every subscriber; the
// log is one subscriber (Platform's log sink) and a future UI another, so both read the same facts (ADR 0002).

public enum AppEvent: Equatable {
    case library(LibraryEvent)
    case rotation(RotationEvent)
    case playback(PlaybackEvent)
    case presence(PresenceEvent)
    case daylight(DaylightEvent)
    case desktop(DesktopEvent)
    case application(ApplicationEvent)

    /// The event's single log rendering, owned by the context that declares it; nil for events that aren't logged.
    public var logLine: LogLine? {
        switch self {
        case .library(let event): return event.logLine
        case .rotation(let event): return event.logLine
        case .playback(let event): return event.logLine
        case .presence(let event): return event.logLine
        case .daylight(let event): return event.logLine
        case .desktop(let event): return event.logLine
        case .application(let event): return event.logLine
        }
    }
}
