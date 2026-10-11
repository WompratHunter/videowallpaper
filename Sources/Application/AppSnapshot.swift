import Daylight
import Desktop
import Library
import Playback
import Presence
import Rotation

// MARK: - App snapshot
// Everything worth showing, as one immutable value joined from the contexts' published state: one slice per context
// (declared in the context) plus Preferences. The coordinator replaces it whenever it changes and tells observers,
// so a future UI redraws from a single value without polling.

public struct AppSnapshot: Equatable {
    public var library: LibrarySlice
    public var rotation: RotationSlice
    public var playback: PlaybackSlice
    public var presence: PresenceSlice
    public var daylight: DaylightSlice
    public var desktop: DesktopSlice
    public var preferences: Preferences

    public init(
        library: LibrarySlice = LibrarySlice(),
        rotation: RotationSlice = RotationSlice(),
        playback: PlaybackSlice = PlaybackSlice(),
        presence: PresenceSlice = PresenceSlice(),
        daylight: DaylightSlice = DaylightSlice(),
        desktop: DesktopSlice = DesktopSlice(),
        preferences: Preferences = Preferences()
    ) {
        self.library = library
        self.rotation = rotation
        self.playback = playback
        self.presence = presence
        self.daylight = daylight
        self.desktop = desktop
        self.preferences = preferences
    }
}
