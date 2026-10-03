import Foundation

// MARK: - Relative luminance
// An approximate screener for the WCAG 2.3.1 general flash threshold: luminance only, no red-flash test.

/// sRGB byte to linear light, precomputed because Analysis converts every pixel of every frame.
let srgbToLinear: [Double] = (0..<256).map { byte in
    let encoded = Double(byte) / 255
    return encoded <= 0.040_45 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
}

/// BT.709 (sRGB primaries) relative luminance, 0 (black) to 1 (white).
func relativeLuminance(red: UInt8, green: UInt8, blue: UInt8) -> Double {
    0.2126 * srgbToLinear[Int(red)] + 0.7152 * srgbToLinear[Int(green)] + 0.0722 * srgbToLinear[Int(blue)]
}

// MARK: - Flash regions
// WCAG's general flash threshold applies to any area of about a quarter of a 10-degree visual field, which at a
// normal viewing distance is a few percent of the screen. A 12x12 grid of cells, read as overlapping 2x2
// neighbourhoods (each 4/144, about 2.8% of the frame), catches a flash confined to a small part of the picture;
// the full frame is checked as well.

enum FlashGrid {
    static let size = 12
    /// The full frame plus one region per 2x2 neighbourhood.
    static let regionCount = 1 + (size - 1) * (size - 1)

    /// The mean luminance of each of the 12x12 cells (row-major) of a BGRA frame.
    static func cellLuminances(bgra: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int) -> [Double] {
        var sums = [Double](repeating: 0, count: size * size)
        var counts = [Int](repeating: 0, count: size * size)
        let columnCell = (0..<width).map { $0 * size / width }
        for row in 0..<height {
            let rowCell = row * size / height * size
            let start = row * bytesPerRow
            for column in 0..<width {
                let pixel = start + column * 4
                let cell = rowCell + columnCell[column]
                sums[cell] += relativeLuminance(red: bgra[pixel + 2], green: bgra[pixel + 1], blue: bgra[pixel])
                counts[cell] += 1
            }
        }
        return zip(sums, counts).map { $1 > 0 ? $0 / Double($1) : 0 }
    }

    /// The full frame's mean luminance first, then each overlapping 2x2 neighbourhood's.
    static func regions(cells: [Double]) -> [Double] {
        var regions = [cells.reduce(0, +) / Double(cells.count)]
        for row in 0..<(size - 1) {
            for column in 0..<(size - 1) {
                let top = row * size + column
                regions.append((cells[top] + cells[top + 1] + cells[top + size] + cells[top + size + 1]) / 4)
            }
        }
        return regions
    }
}

// MARK: - Transitions
// A flash is a pair of opposing changes in relative luminance of at least 0.10, where the darker state is below
// 0.80. A change is measured from the last extreme, not from the previous frame, so a fade spread over many frames
// still counts once, while a slow drift that never reverses within a second never makes a pair.

struct TransitionDetector {
    static let minimumChange = 0.10
    static let darkerStateLimit = 0.80
    /// Tolerates rounding in luminance that is exactly 0.10 apart.
    private static let epsilon = 1e-9

    private enum Direction { case none, rising, falling }

    private var direction = Direction.none
    /// Before the first transition, the darkest and brightest values so far; after it, `extreme` is the brightest
    /// value since a rise (or the darkest since a fall), from which the opposing change is measured.
    private var lowest = Double.infinity
    private var highest = -Double.infinity
    private var extreme = 0.0

    /// Adds the next frame's value; returns true when it completes a qualifying change.
    mutating func add(_ value: Double) -> Bool {
        switch direction {
        case .none:
            lowest = min(lowest, value)
            highest = max(highest, value)
            if Self.qualifies(darker: lowest, brighter: value) { return turn(.rising, at: value) }
            if Self.qualifies(darker: value, brighter: highest) { return turn(.falling, at: value) }
        case .rising:
            if value > extreme { extreme = value } else if Self.qualifies(darker: value, brighter: extreme) {
                return turn(.falling, at: value)
            }
        case .falling:
            if value < extreme { extreme = value } else if Self.qualifies(darker: extreme, brighter: value) {
                return turn(.rising, at: value)
            }
        }
        return false
    }

    private mutating func turn(_ next: Direction, at value: Double) -> Bool {
        direction = next
        extreme = value
        return true
    }

    private static func qualifies(darker: Double, brighter: Double) -> Bool {
        brighter - darker >= minimumChange - epsilon && darker < darkerStateLimit
    }
}

// MARK: - Screener
// Fed every frame of a video in order; keeps one detector per region and the transitions of the last second.

/// The measurements Analysis takes from a video's frames.
struct FrameMeasurement: Equatable {
    /// Mean relative luminance over every frame.
    let meanLuminance: Double
    /// The most flashes in any 1 s window, in any region.
    let flashesPerSecond: Int
    /// Where the Poster comes from: the frame closest to the mean luminance.
    let posterSeconds: Double
}

struct FlashScreener {
    private static let window = 1.0
    private static let epsilon = 1e-6

    private var detectors = [TransitionDetector](repeating: TransitionDetector(), count: FlashGrid.regionCount)
    /// Per region, the times of the transitions still inside the window.
    private var recent = [[Double]](repeating: [], count: FlashGrid.regionCount)
    private var mostTransitions = 0
    private var frameLuminances: [Double] = []
    private var frameTimes: [Double] = []

    /// Adds one frame's region luminances (see `FlashGrid.regions`), at its presentation time in seconds.
    mutating func add(regions: [Double], at seconds: Double) {
        frameLuminances.append(regions[0])
        frameTimes.append(seconds)
        for index in regions.indices where detectors[index].add(regions[index]) {
            recent[index].append(seconds)
            recent[index].removeAll { seconds - $0 >= Self.window - Self.epsilon }
            mostTransitions = max(mostTransitions, recent[index].count)
        }
    }

    /// Nil when no frame was added.
    var measurement: FrameMeasurement? {
        guard let poster = posterFrameIndex(luminances: frameLuminances) else { return nil }
        return FrameMeasurement(
            meanLuminance: frameLuminances.reduce(0, +) / Double(frameLuminances.count),
            flashesPerSecond: mostTransitions / 2,
            posterSeconds: frameTimes[poster])
    }
}

// MARK: - Poster frame

/// The frame closest to the mean luminance (the earliest on a tie), so the Poster represents the video rather than a
/// dark intro or a bright flash.
func posterFrameIndex(luminances: [Double]) -> Int? {
    guard !luminances.isEmpty else { return nil }
    let mean = luminances.reduce(0, +) / Double(luminances.count)
    return luminances.indices.min { (abs(luminances[$0] - mean), $0) < (abs(luminances[$1] - mean), $1) }
}

// MARK: - Flash verdict

enum FlashVerdict: Equatable {
    case eligible
    case excluded
    /// Over the limit but listed in `FlashOverride` by file name, so it plays.
    case overridden

    static let limitPerSecond = 3

    var isPlayable: Bool { self != .excluded }
}

func flashVerdict(flashesPerSecond: Int, fileName: String, overrides: [String]) -> FlashVerdict {
    guard flashesPerSecond > FlashVerdict.limitPerSecond else { return .eligible }
    return overrides.contains(fileName) ? .overridden : .excluded
}
