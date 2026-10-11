@testable import Rotation
import Testing

// MARK: - Mode setting tests
// Native swift-testing: whatever the appearance, a stored Mode is honoured in any letter case, as typed with
// `defaults write`.

@Test(arguments: RotationMode.allCases, [false, true])
func storedModeWinsInAnyCase(mode: RotationMode, isAutoAppearance: Bool) {
    #expect(rotationMode(setting: mode.rawValue.uppercased(), isAutoAppearance: isAutoAppearance) == mode)
    #expect(rotationMode(setting: mode.rawValue, isAutoAppearance: isAutoAppearance) == mode)
}
