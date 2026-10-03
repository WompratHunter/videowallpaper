import Foundation

// MARK: - Visibility tests

func runVisibilityTests() {
    runOcclusionTests()
}

private func runOcclusionTests() {
    check(isEveryWindowOccluded(visibility: [false, false, false]), "every window covered")
    check(!isEveryWindowOccluded(visibility: [false, true, false]), "one visible display keeps playing")
    check(!isEveryWindowOccluded(visibility: []), "no windows is not occluded")
}
