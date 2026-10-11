import Foundation

// MARK: - Coverage
// How much of every screen normal windows cover, from the window list's bounds alone.

/// An axis-aligned rectangle in global screen coordinates. The domain stays Foundation-only, where CGRect has no
/// geometry.
public struct ScreenRect: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        maxX = minX + width
        maxY = minY + height
    }

    var area: Double { max(0, maxX - minX) * max(0, maxY - minY) }

    func clipped(to other: ScreenRect) -> ScreenRect? {
        let left = max(minX, other.minX), right = min(maxX, other.maxX)
        let bottom = max(minY, other.minY), top = min(maxY, other.maxY)
        guard right > left, top > bottom else { return nil }
        return ScreenRect(minX: left, minY: bottom, width: right - left, height: top - bottom)
    }
}

/// One entry of the system window list, reduced to what is readable without Screen Recording permission.
public struct ListedWindow: Equatable, Sendable {
    public let layer: Int
    public let alpha: Double
    /// The same coordinate space as the screens passed to `leastCoverage`.
    public let bounds: ScreenRect

    public init(layer: Int, alpha: Double, bounds: ScreenRect) {
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }
}

/// The coverage of the least-covered screen by on-screen normal-layer windows. Translucency can't be told apart
/// (Ghostty reports alpha 1), which is why this only ever yields Veiled, never Unseen.
func leastCoverage(of windows: [ListedWindow], screens: [ScreenRect]) -> Double {
    let covering = windows.filter { $0.layer == 0 && $0.alpha > 0 }.map(\.bounds)
    return screens.map { coverageFraction(of: covering, over: $0) }.min() ?? 0
}

/// The fraction of `screen` covered by the union of `rects`; overlaps count once and parts off the screen not at
/// all. Sweeps the vertical strips between rect edges, merging the covered spans in each.
func coverageFraction(of rects: [ScreenRect], over screen: ScreenRect) -> Double {
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

/// A coverage fraction as the log writes it.
func percent(_ fraction: Double) -> String {
    String(format: "%.1f%%", fraction * 100)
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
struct VeilTracker {
    static let threshold = 0.95
    static let requiredDuration: TimeInterval = 30
    /// The 5 s tick plus its 2 s tolerance, with room for one late tick.
    static let maxSampleGap: TimeInterval = 12

    private var coveredSince: Date?
    private var lastSample: Date?

    mutating func sample(coverage: Double, at now: Date) {
        let isContinuous = lastSample.map { now.timeIntervalSince($0) <= Self.maxSampleGap } ?? false
        if coverage < Self.threshold {
            coveredSince = nil
        } else if coveredSince == nil || !isContinuous {
            coveredSince = now
        }
        lastSample = now
    }

    func coveredFor(at now: Date) -> TimeInterval? {
        guard let since = coveredSince, let last = lastSample, now.timeIntervalSince(last) <= Self.maxSampleGap else {
            return nil
        }
        return now.timeIntervalSince(since)
    }
}
