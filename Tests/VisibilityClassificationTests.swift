import Foundation

// MARK: - Visibility classification tests

func runVisibilityClassificationTests() {
    runOcclusionTests()
}

private func runOcclusionTests() {
    check(isEveryWindowOccluded(visibility: [false, false, false]), "every window covered")
    check(!isEveryWindowOccluded(visibility: [false, true, false]), "one visible display keeps playing")
    check(!isEveryWindowOccluded(visibility: []), "no windows is not occluded")
}
