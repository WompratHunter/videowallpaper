import Rotation

// MARK: - Fake Rotation ports
// The Rotation is pure but for the auto-appearance flag; tests set it.

package final class FakeAutoAppearance: AutoAppearancePort {
    package var isAutoAppearance: Bool

    package init(isAutoAppearance: Bool = false) {
        self.isAutoAppearance = isAutoAppearance
    }
}
