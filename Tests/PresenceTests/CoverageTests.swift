import Foundation
@testable import Presence
import Testing

// MARK: - Coverage tests

struct CoverageTests {
    private let screen = ScreenRect(minX: 0, minY: 0, width: 100, height: 100)

    @Test func fractionOfOneScreen() {
        #expect(coverageFraction(of: [], over: screen) == 0)
        #expect(coverageFraction(of: [screen], over: screen) == 1)
        #expect(coverageFraction(of: [ScreenRect(minX: 0, minY: 0, width: 50, height: 100)], over: screen) == 0.5)
        // A maximized window below a 3% menu bar.
        #expect(coverageFraction(of: [ScreenRect(minX: 0, minY: 3, width: 100, height: 97)], over: screen) == 0.97)
        #expect(coverageFraction(of: [screen], over: ScreenRect(minX: 0, minY: 0, width: 0, height: 0)) == 0)
    }

    @Test func overlapIsCountedOnce() {
        let left = ScreenRect(minX: 0, minY: 0, width: 60, height: 100)
        let right = ScreenRect(minX: 40, minY: 0, width: 60, height: 100)
        #expect(coverageFraction(of: [left, right], over: screen) == 1)
        let quarter = ScreenRect(minX: 0, minY: 0, width: 50, height: 50)
        #expect(coverageFraction(of: [quarter, quarter], over: screen) == 0.25)
        // An L-shape from two windows: 100x10 strip plus 10x90 column.
        let strip = ScreenRect(minX: 0, minY: 0, width: 100, height: 10)
        let column = ScreenRect(minX: 0, minY: 0, width: 10, height: 100)
        #expect(coverageFraction(of: [strip, column], over: screen) == 0.19)
    }

    @Test func partsOffTheScreenDontCount() {
        #expect(coverageFraction(of: [ScreenRect(minX: -50, minY: 0, width: 100, height: 100)], over: screen) == 0.5)
        #expect(coverageFraction(of: [ScreenRect(minX: 200, minY: 0, width: 100, height: 100)], over: screen) == 0)
        // Screens elsewhere in global coordinates.
        let second = ScreenRect(minX: 100, minY: 0, width: 100, height: 100)
        #expect(coverageFraction(of: [ScreenRect(minX: 100, minY: 0, width: 100, height: 50)], over: second) == 0.5)
    }

    @Test func onlyNormalVisibleWindowsCoverAndTheLeastCoveredScreenDecides() {
        let full = ListedWindow(layer: 0, alpha: 1, bounds: screen)
        #expect(leastCoverage(of: [full], screens: [screen]) == 1)
        // Panels, menus and the Dock are not normal-layer windows.
        #expect(leastCoverage(of: [ListedWindow(layer: 25, alpha: 1, bounds: screen)], screens: [screen]) == 0)
        // A fully transparent window draws nothing.
        #expect(leastCoverage(of: [ListedWindow(layer: 0, alpha: 0, bounds: screen)], screens: [screen]) == 0)
        // Every screen must be covered.
        let second = ScreenRect(minX: 100, minY: 0, width: 100, height: 100)
        #expect(leastCoverage(of: [full], screens: [screen, second]) == 0)
        #expect(leastCoverage(of: [], screens: []) == 0)
    }
}

// MARK: - Veil tracker tests

struct VeilTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func coverageHeldAboveTheThresholdCountsUp() {
        var tracker = VeilTracker()
        #expect(tracker.coveredFor(at: start) == nil)
        tracker.sample(coverage: 0.97, at: start)
        #expect(tracker.coveredFor(at: start) == 0)
        tracker.sample(coverage: 0.96, at: start + 5)
        tracker.sample(coverage: 0.99, at: start + 10)
        #expect(tracker.coveredFor(at: start + 10) == 10)

        // Dropping below 95% restarts the clock.
        tracker.sample(coverage: 0.94, at: start + 15)
        #expect(tracker.coveredFor(at: start + 15) == nil)
        for offset in stride(from: 20.0, through: 50, by: 5) { tracker.sample(coverage: 1, at: start + offset) }
        #expect(tracker.coveredFor(at: start + 50) == 30)
        #expect(classifyPresence(PresenceInputs(coveredFor: tracker.coveredFor(at: start + 50))) == .veiled)
    }

    @Test func gapsBetweenSamplesProveNothing() {
        var gappy = VeilTracker()
        gappy.sample(coverage: 1, at: start)
        gappy.sample(coverage: 1, at: start + 40)
        #expect(gappy.coveredFor(at: start + 40) == 0)
        // A stale last sample says nothing about now.
        #expect(gappy.coveredFor(at: start + 40 + VeilTracker.maxSampleGap + 1) == nil)
    }
}
