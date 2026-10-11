import Foundation
import SharedKernel

// MARK: - Visibility classification
// Whether anyone can see the Live wallpaper (see CONTEXT.md): its Presence. Unseen comes from
// notifications; Veiled from window-list bounds sampled only when a caller asks, so it needs no Screen Recording
// permission and costs nothing while no switch is due.

/// Each window's "visible" occlusion flag. Translucent windows (e.g. Ghostty) don't clear the flag, so only
/// opaque coverage of every display counts. No windows at all is not "covered".
package func isEveryWindowOccluded(visibility: [Bool]) -> Bool {
    !visibility.isEmpty && !visibility.contains(true)
}

package struct VisibilityInputs: Equatable {
    package var isEveryWindowOccluded = false
    package var areScreensAsleep = false
    package var isSessionInactive = false
    package var isLocked = false
    /// How long normal windows have covered every screen continuously, or nil if they don't (see `VeilTracker`).
    package var coveredFor: TimeInterval?
}

/// A notification-driven input change; the window-list coverage arrives separately, through `VeilTracker`.
package enum VisibilityEvent: Equatable {
    case everyWindowOccluded(Bool)
    case screensAsleep(Bool)
    case sessionInactive(Bool)
    case locked(Bool)
}

extension VisibilityInputs {
    package mutating func apply(_ event: VisibilityEvent) {
        switch event {
        case .everyWindowOccluded(let isOn): isEveryWindowOccluded = isOn
        case .screensAsleep(let isOn): areScreensAsleep = isOn
        case .sessionInactive(let isOn): isSessionInactive = isOn
        case .locked(let isOn): isLocked = isOn
        }
    }
}

package func classifyVisibility(_ inputs: VisibilityInputs) -> Presence {
    if inputs.isEveryWindowOccluded || inputs.areScreensAsleep || inputs.isSessionInactive || inputs.isLocked {
        return .unseen
    }
    if let coveredFor = inputs.coveredFor, coveredFor >= VeilTracker.requiredDuration { return .veiled }
    return .visible
}

// MARK: - Coverage

/// An axis-aligned rectangle in global screen coordinates. Core stays Foundation-only, where CGRect has no geometry.
package struct ScreenRect: Equatable {
    package let minX: Double
    package let minY: Double
    package let maxX: Double
    package let maxY: Double

    package init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        maxX = minX + width
        maxY = minY + height
    }

    package var area: Double { max(0, maxX - minX) * max(0, maxY - minY) }

    package func clipped(to other: ScreenRect) -> ScreenRect? {
        let left = max(minX, other.minX), right = min(maxX, other.maxX)
        let bottom = max(minY, other.minY), top = min(maxY, other.maxY)
        guard right > left, top > bottom else { return nil }
        return ScreenRect(minX: left, minY: bottom, width: right - left, height: top - bottom)
    }
}

/// One entry of the system window list, reduced to what is readable without Screen Recording permission.
package struct ListedWindow: Equatable {
    package let layer: Int
    package let alpha: Double
    /// The same coordinate space as the screens passed to `leastCoverage`.
    package let bounds: ScreenRect

    package init(layer: Int, alpha: Double, bounds: ScreenRect) {
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }
}

/// The coverage of the least-covered screen by on-screen normal-layer windows. Translucency can't be told apart
/// (Ghostty reports alpha 1), which is why this only ever yields Veiled, never Unseen.
package func leastCoverage(of windows: [ListedWindow], screens: [ScreenRect]) -> Double {
    let covering = windows.filter { $0.layer == 0 && $0.alpha > 0 }.map(\.bounds)
    return screens.map { coverageFraction(of: covering, over: $0) }.min() ?? 0
}

/// The fraction of `screen` covered by the union of `rects`; overlaps count once and parts off the screen not at
/// all. Sweeps the vertical strips between rect edges, merging the covered spans in each.
package func coverageFraction(of rects: [ScreenRect], over screen: ScreenRect) -> Double {
    guard screen.area > 0 else { return 0 }
    let clipped = rects.compactMap { $0.clipped(to: screen) }
    let edges = Set(clipped.flatMap { [$0.minX, $0.maxX] }).sorted()
    var covered = 0.0
    for (left, right) in zip(edges, edges.dropFirst()) {
        let spans = clipped.filter { $0.minX <= left && $0.maxX >= right }.map { Span($0.minY, $0.maxY) }
        covered += (right - left) * mergedLength(of: spans.sorted { $0.start < $1.start })
    }
    return covered / screen.area
}

private struct Span {
    let start: Double
    let end: Double

    init(_ start: Double, _ end: Double) {
        self.start = start
        self.end = end
    }
}

private func mergedLength(of sortedSpans: [Span]) -> Double {
    var total = 0.0
    var current: Span?
    for span in sortedSpans {
        if let open = current, span.start <= open.end {
            current = Span(open.start, max(open.end, span.end))
        } else {
            total += current.map { $0.end - $0.start } ?? 0
            current = span
        }
    }
    return total + (current.map { $0.end - $0.start } ?? 0)
}

// MARK: - Veil tracking

/// Whether coverage has stayed at or above the threshold continuously. Samples arrive only while a caller asks (on
/// the 5 s tick when a switch is due), so a gap longer than `maxSampleGap` restarts the clock: an unsampled
/// stretch can't prove the screen stayed covered.
package struct VeilTracker {
    package static let threshold = 0.95
    package static let requiredDuration: TimeInterval = 30
    /// The 5 s tick plus its 2 s tolerance, with room for one late tick.
    package static let maxSampleGap: TimeInterval = 12

    private var coveredSince: Date?
    private var lastSample: Date?

    package mutating func sample(coverage: Double, at now: Date) {
        let isContinuous = lastSample.map { now.timeIntervalSince($0) <= Self.maxSampleGap } ?? false
        if coverage < Self.threshold {
            coveredSince = nil
        } else if coveredSince == nil || !isContinuous {
            coveredSince = now
        }
        lastSample = now
    }

    package func coveredFor(at now: Date) -> TimeInterval? {
        guard let since = coveredSince, let last = lastSample, now.timeIntervalSince(last) <= Self.maxSampleGap else {
            return nil
        }
        return now.timeIntervalSince(since)
    }
}

// MARK: - Visibility tracking

/// The current state and what moves it: notification events, coverage samples and the expiry of the last sample.
/// Each step returns the new state only when it changed, so the app logs and reports exactly the changes.
package struct VisibilityTracker {
    package private(set) var state: Presence = .visible
    private var inputs = VisibilityInputs()
    private var veil = VeilTracker()

    package init() {}

    /// Veiled can't override Unseen, so the window list isn't worth reading then.
    package var needsCoverageSample: Bool { classifyVisibility(inputs) != .unseen }

    package mutating func apply(_ event: VisibilityEvent, at now: Date) -> Presence? {
        inputs.apply(event)
        return refresh(at: now)
    }

    package mutating func sample(coverage: Double, at now: Date) -> Presence? {
        veil.sample(coverage: coverage, at: now)
        return refresh(at: now)
    }

    /// Re-reads the coverage clock: once the last sample is older than `VeilTracker.maxSampleGap`, Veiled lapses.
    package mutating func refresh(at now: Date) -> Presence? {
        inputs.coveredFor = veil.coveredFor(at: now)
        let next = classifyVisibility(inputs)
        guard next != state else { return nil }
        state = next
        return next
    }
}
