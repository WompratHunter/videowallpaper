import Application
import Foundation

// MARK: - UserDefaults settings
// The settings port's adapter: the app's standard defaults domain, under the keys it has always used, so
// `defaults write com.evanscott.videowallpaper Mode dark` (or `FlashOverride -array …`) still works. Only Mode and
// FlashOverride are stored; the reserved Preferences fields gain keys with the commands that set them.

final class UserDefaultsSettings: SettingsPort {
    private enum Key {
        static let mode = "Mode"
        static let flashOverride = "FlashOverride"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Preferences {
        Preferences(
            modeSetting: defaults.string(forKey: Key.mode),
            flashOverrides: defaults.stringArray(forKey: Key.flashOverride) ?? [])
    }

    func save(_ preferences: Preferences) {
        if let mode = preferences.modeSetting {
            defaults.set(mode, forKey: Key.mode)
        } else {
            defaults.removeObject(forKey: Key.mode)
        }
        if preferences.flashOverrides.isEmpty {
            defaults.removeObject(forKey: Key.flashOverride)
        } else {
            defaults.set(preferences.flashOverrides, forKey: Key.flashOverride)
        }
    }
}
