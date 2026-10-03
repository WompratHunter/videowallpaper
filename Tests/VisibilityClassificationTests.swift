import Foundation

// MARK: - Visibility classification tests

func runVisibilityClassificationTests() {
    runOcclusionTests()
    runClassificationTests()
    runCoverageTests()
    runCoveringWindowTests()
    runVeilTrackerTests()
    runAllowedTransitionTests()
}

private func runOcclusionTests() {
    check(isEveryWindowOccluded(visibility: [false, false, false]), "every window covered")
    check(!isEveryWindowOccluded(visibility: [false, true, false]), "one visible display keeps playing")
    check(!isEveryWindowOccluded(visibility: []), "no windows is not occluded")
}

private func runClassificationTests() {
    checkEqual(classifyVisibility(VisibilityInputs()), .visible)
    checkEqual(classifyVisibility(VisibilityInputs(isEveryWindowOccluded: true)), .unseen)
    checkEqual(classifyVisibility(VisibilityInputs(areScreensAsleep: true)), .unseen)
    checkEqual(classifyVisibility(VisibilityInputs(isSessionInactive: true)), .unseen)
    checkEqual(classifyVisibility(VisibilityInputs(isLocked: true)), .unseen)
    checkEqual(classifyVisibility(VisibilityInputs(coveredFor: 30)), .veiled)
    checkEqual(classifyVisibility(VisibilityInputs(coveredFor: 29.9)), .visible)
    // Unseen wins: a locked screen behind a maximized window is still nobody watching.
    checkEqual(classifyVisibility(VisibilityInputs(isLocked: true, coveredFor: 60)), .unseen)

    // Unlock alone doesn't clear Unseen while the screens are still asleep.
    var inputs = VisibilityInputs()
    inputs.apply(.screensAsleep(true))
    inputs.apply(.locked(true))
    inputs.apply(.locked(false))
    checkEqual(classifyVisibility(inputs), .unseen)
    inputs.apply(.screensAsleep(false))
    checkEqual(classifyVisibility(inputs), .visible)
    inputs.apply(.sessionInactive(true))
    checkEqual(classifyVisibility(inputs), .unseen)
    inputs.apply(.sessionInactive(false))
    inputs.apply(.everyWindowOccluded(true))
    checkEqual(classifyVisibility(inputs), .unseen)
}

private func runCoverageTests() {
    let screen = Rect(minX: 0, minY: 0, width: 100, height: 100)
    checkEqual(coverageFraction(of: [], over: screen), 0)
    checkEqual(coverageFraction(of: [screen], over: screen), 1)
    checkEqual(coverageFraction(of: [Rect(minX: 0, minY: 0, width: 50, height: 100)], over: screen), 0.5)
    // Overlap is counted once.
    let left = Rect(minX: 0, minY: 0, width: 60, height: 100)
    let right = Rect(minX: 40, minY: 0, width: 60, height: 100)
    checkEqual(coverageFraction(of: [left, right], over: screen), 1)
    let stacked = [Rect(minX: 0, minY: 0, width: 50, height: 50), Rect(minX: 0, minY: 0, width: 50, height: 50)]
    checkEqual(coverageFraction(of: stacked, over: screen), 0.25)
    // Parts off the screen don't count.
    checkEqual(coverageFraction(of: [Rect(minX: -50, minY: 0, width: 100, height: 100)], over: screen), 0.5)
    checkEqual(coverageFraction(of: [Rect(minX: 200, minY: 0, width: 100, height: 100)], over: screen), 0)
    // An L-shape from two windows: 100x10 strip plus 10x90 column.
    let lShape = [Rect(minX: 0, minY: 0, width: 100, height: 10), Rect(minX: 0, minY: 0, width: 10, height: 100)]
    checkEqual(coverageFraction(of: lShape, over: screen), 0.19)
    // A maximized window below a 3% menu bar.
    checkEqual(coverageFraction(of: [Rect(minX: 0, minY: 3, width: 100, height: 97)], over: screen), 0.97)
    // Screens elsewhere in global coordinates.
    let second = Rect(minX: 100, minY: 0, width: 100, height: 100)
    checkEqual(coverageFraction(of: [Rect(minX: 100, minY: 0, width: 100, height: 50)], over: second), 0.5)
    checkEqual(coverageFraction(of: [screen], over: Rect(minX: 0, minY: 0, width: 0, height: 0)), 0)
}

private func runCoveringWindowTests() {
    let screen = Rect(minX: 0, minY: 0, width: 100, height: 100)
    let full = Rect(minX: 0, minY: 0, width: 100, height: 100)
    checkEqual(leastCoverage(of: [ListedWindow(layer: 0, alpha: 1, bounds: full)], screens: [screen]), 1)
    // Panels, menus and the Dock are not normal-layer windows.
    checkEqual(leastCoverage(of: [ListedWindow(layer: 25, alpha: 1, bounds: full)], screens: [screen]), 0)
    // A fully transparent window draws nothing.
    checkEqual(leastCoverage(of: [ListedWindow(layer: 0, alpha: 0, bounds: full)], screens: [screen]), 0)
    // Every screen must be covered: the least-covered one decides.
    let second = Rect(minX: 100, minY: 0, width: 100, height: 100)
    checkEqual(leastCoverage(of: [ListedWindow(layer: 0, alpha: 1, bounds: full)], screens: [screen, second]), 0)
    checkEqual(leastCoverage(of: [], screens: []), 0)
}

private func runVeilTrackerTests() {
    let start = Date(timeIntervalSince1970: 1_000)
    var tracker = VeilTracker()
    checkEqual(tracker.coveredFor(at: start), nil)

    tracker.sample(coverage: 0.97, at: start)
    checkEqual(tracker.coveredFor(at: start), 0)
    tracker.sample(coverage: 0.96, at: start + 5)
    tracker.sample(coverage: 0.99, at: start + 10)
    checkEqual(tracker.coveredFor(at: start + 10), 10)

    // Dropping below 95% restarts the clock.
    tracker.sample(coverage: 0.94, at: start + 15)
    checkEqual(tracker.coveredFor(at: start + 15), nil)
    for offset in stride(from: 20.0, through: 50, by: 5) { tracker.sample(coverage: 1, at: start + offset) }
    checkEqual(tracker.coveredFor(at: start + 50), 30)
    checkEqual(classifyVisibility(VisibilityInputs(coveredFor: tracker.coveredFor(at: start + 50))), .veiled)

    // Samples too far apart can't prove the coverage was continuous.
    var gappy = VeilTracker()
    gappy.sample(coverage: 1, at: start)
    gappy.sample(coverage: 1, at: start + 40)
    checkEqual(gappy.coveredFor(at: start + 40), 0)
    // A stale last sample says nothing about now.
    checkEqual(gappy.coveredFor(at: start + 40 + VeilTracker.maxSampleGap + 1), nil)

    var reset = VeilTracker()
    reset.sample(coverage: 1, at: start)
    reset.reset()
    checkEqual(reset.coveredFor(at: start), nil)
}

private func runAllowedTransitionTests() {
    let quick = AllowedTransition(crossfade: 5, minimumDwell: 20 * 60, allowsBrightnessJump: false)
    let quickWithJump = AllowedTransition(crossfade: 5, minimumDwell: 20 * 60, allowsBrightnessJump: true)
    let fallback = AllowedTransition(crossfade: 20, minimumDwell: 60 * 60, allowsBrightnessJump: false)
    // A big brightness jump only when nobody watches; Veiled is still seen through the glass.
    checkEqual(allowedTransition(for: .unseen), quickWithJump)
    checkEqual(allowedTransition(for: .veiled), quick)
    // Visible only via the slow fallback after an hour.
    checkEqual(allowedTransition(for: .visible), fallback)
}
