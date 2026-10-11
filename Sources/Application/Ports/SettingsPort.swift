// MARK: - Settings port
// Where Preferences are kept. Today's adapter is Platform's `UserDefaultsSettings` (the standard domain, with the
// existing keys so `defaults write` still works); tests use `FakeSettings`. Loaded at decision time, so an external
// change is picked up without a restart.

package protocol SettingsPort: AnyObject {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}
