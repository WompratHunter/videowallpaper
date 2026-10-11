import Foundation

// MARK: - Preferences
// The user's settings as one typed value, loaded and saved through the settings port. Only Mode and FlashOverride are
// stored today; the other fields are reserved for the commands that will set them, and until then always read as
// their default.

public struct Preferences: Equatable {
    /// The raw `Mode` setting: missing or unknown falls back by the auto-appearance flag (see `rotationMode`).
    public var modeSetting: String?
    /// The `FlashOverride` file names: Videos that play even though Analysis Excluded them.
    public var flashOverrides: [String]
    /// Reserved for Enable / Disable (ticket 10).
    public var isEnabled: Bool
    /// Reserved for Choose Wallpaper folder (ticket 11): nil is the default folder.
    public var wallpaperFolder: URL?
    /// Read from the launch-at-login port (Set Launch at login), never from the settings store.
    public var launchesAtLogin: Bool

    public init(
        modeSetting: String? = nil,
        flashOverrides: [String] = [],
        isEnabled: Bool = true,
        wallpaperFolder: URL? = nil,
        launchesAtLogin: Bool = true
    ) {
        self.modeSetting = modeSetting
        self.flashOverrides = flashOverrides
        self.isEnabled = isEnabled
        self.wallpaperFolder = wallpaperFolder
        self.launchesAtLogin = launchesAtLogin
    }
}
