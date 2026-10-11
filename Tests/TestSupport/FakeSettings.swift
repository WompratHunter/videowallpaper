import Application

// MARK: - Fake settings
// An in-memory settings store. Edit `stored` to stand for an external `defaults write`; a simulated relaunch builds a
// new coordinator on the same fake.

package final class FakeSettings: SettingsPort {
    package var stored: Preferences

    package init(_ stored: Preferences = Preferences()) {
        self.stored = stored
    }

    package func load() -> Preferences { stored }

    package func save(_ preferences: Preferences) {
        stored = preferences
    }
}
