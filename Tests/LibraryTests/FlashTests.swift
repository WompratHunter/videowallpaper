import Foundation
@testable import Library
import Testing

// MARK: - Flash tests: luminance, flash counting, Poster frame, verdicts

@Test func relativeLuminanceFollowsSRGBAndBT709() {
    #expect(srgbToLinear.count == 256)
    #expect(srgbToLinear[0] == 0)
    #expect(srgbToLinear[255] == 1)
    #expect(abs(srgbToLinear[128] - 0.2158) < 0.0001, "sRGB 128 is about 21.6% linear: \(srgbToLinear[128])")
    #expect(abs(srgbToLinear[10] - 10.0 / 255 / 12.92) < 1e-12, "the linear toe below 0.04045")
    #expect(relativeLuminance(red: 255, green: 255, blue: 255) == 1)
    #expect(abs(relativeLuminance(red: 255, green: 0, blue: 0) - 0.2126) < 1e-12, "BT.709 red weight")
    #expect(abs(relativeLuminance(red: 0, green: 255, blue: 0) - 0.7152) < 1e-12, "BT.709 green weight")
    #expect(abs(relativeLuminance(red: 0, green: 0, blue: 255) - 0.0722) < 1e-12, "BT.709 blue weight")
}

@Test func theGridAveragesCellsAndNeighbourhoods() {
    // A 24x24 BGRA frame (row padding included): white in the top-left 2x2 pixels (cell 0), black elsewhere.
    let width = 24, height = 24, bytesPerRow = width * 4 + 8
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    for row in 0..<2 {
        for column in 0..<2 {
            for channel in 0..<3 { pixels[row * bytesPerRow + column * 4 + channel] = 255 }
        }
    }
    let cells = pixels.withUnsafeBytes {
        FlashGrid.cellLuminances(bgra: $0, width: width, height: height, bytesPerRow: bytesPerRow)
    }
    #expect(cells.count == 144)
    #expect(cells[0] == 1)
    #expect(cells[1...].max() == 0)
    let regions = FlashGrid.regions(cells: cells)
    #expect(regions.count == FlashGrid.regionCount)
    #expect(regions.count == 122)
    #expect(abs(regions[0] - 1.0 / 144) < 1e-12, "the full frame is the mean of every cell")
    #expect(regions[1] == 0.25)
    #expect(regions[2] == 0)
}

/// Flashes per second of a full-frame square wave between two luminance levels.
private func squareWaveRate(hertz: Double, fps: Double, low: Double = 0.05, high: Double = 0.6, seconds: Double = 4)
    -> Double {
    var screener = FlashScreener()
    for frame in 0..<Int(seconds * fps) {
        let time = Double(frame) / fps
        let value = (time * hertz * 2).truncatingRemainder(dividingBy: 2) < 1 ? low : high
        screener.add(regions: [Double](repeating: value, count: FlashGrid.regionCount), at: time)
    }
    return screener.measurement?.flashesPerSecond ?? -1
}

@Test func squareWavesCountAsTheirFrequency() {
    for fps in [24.0, 25, 30, 60] {
        for hertz in [2.0, 3, 4, 6] {
            let rate = squareWaveRate(hertz: hertz, fps: fps)
            #expect(rate == hertz)
            let verdict = flashVerdict(flashesPerSecond: rate, fileName: "wave.mp4", overrides: [])
            #expect(verdict == (hertz <= 3 ? .withinLimit : .excluded))
        }
    }
    // Changes under 0.10 are not flashes.
    #expect(squareWaveRate(hertz: 6, fps: 30, low: 0.30, high: 0.39) == 0)
    // A change of exactly 0.10 is.
    #expect(squareWaveRate(hertz: 6, fps: 30, low: 0.30, high: 0.40) == 6)
    // Both states at or above 0.80 are too bright to count (the darker state must be below 0.80).
    #expect(squareWaveRate(hertz: 6, fps: 30, low: 0.80, high: 1.0) == 0)
    #expect(squareWaveRate(hertz: 6, fps: 30, low: 0.79, high: 1.0) == 6)
    // 3.5 Hz has 7 transitions in some second: over the limit, though only 3 flashes are complete.
    for fps in [24.0, 30, 60] {
        let rate = squareWaveRate(hertz: 3.5, fps: fps)
        #expect(flashVerdict(flashesPerSecond: rate, fileName: "", overrides: []) == .excluded)
    }
}

@Test func slowChangesAreNotFlashes() {
    // A drift from dark to bright over 10 s and back makes two transitions far apart: never a pair, so at most
    // the half flash a single change counts for.
    var drift = FlashScreener()
    for frame in 0..<600 {
        let time = Double(frame) / 30
        let value = 0.05 + 0.5 * (time < 10 ? time / 10 : (20 - time) / 10)
        drift.add(regions: [Double](repeating: value, count: FlashGrid.regionCount), at: time)
    }
    #expect(drift.measurement?.flashesPerSecond == 0.5)
    // A slow 0.5 Hz pulse: one transition per second at most, so no pair within any second.
    #expect(squareWaveRate(hertz: 0.5, fps: 30) == 0.5)
    // Rain-like noise with an occasional lightning flash once every 2 s stays well under the limit.
    var rain = FlashScreener()
    var seed: UInt64 = 42
    for frame in 0..<1_800 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let noise = Double(seed >> 40) / Double(1 << 24) * 0.02
        let isLightning = frame % 60 < 3
        rain.add(regions: [Double](repeating: (isLightning ? 0.45 : 0.15) + noise, count: FlashGrid.regionCount),
                 at: Double(frame) / 30)
    }
    #expect(rain.measurement?.flashesPerSecond == 1)
    #expect(rain.measurement.map { $0.meanLuminance < 0.2 } ?? false, "rain is dark overall")
}

@Test func aSmallRegionFlashIsCaught() {
    // A 6 Hz flash confined to one 2x2 neighbourhood (2.8% of the frame) barely moves the full frame,
    // but its region catches it.
    var screener = FlashScreener()
    for frame in 0..<120 {
        let time = Double(frame) / 30
        var cells = [Double](repeating: 0.1, count: 144)
        let value = frame / 5 % 2 == 0 ? 0.05 : 0.7
        for cell in [50, 51, 62, 63] { cells[cell] = value }
        let regions = FlashGrid.regions(cells: cells)
        screener.add(regions: regions, at: time)
    }
    #expect(screener.measurement?.flashesPerSecond == 3)
    var fast = FlashScreener()
    for frame in 0..<120 {
        var cells = [Double](repeating: 0.1, count: 144)
        let value = frame / 2 % 2 == 0 ? 0.05 : 0.7
        for cell in [50, 51, 62, 63] { cells[cell] = value }
        fast.add(regions: FlashGrid.regions(cells: cells), at: Double(frame) / 24)
    }
    #expect(fast.measurement?.flashesPerSecond == 6)
}

@Test func thePosterFrameIsClosestToTheMean() {
    #expect(posterFrameIndex(luminances: []) == nil)
    #expect(posterFrameIndex(luminances: [0.4]) == 0)
    // A dark intro then a steady scene: the Poster comes from the scene, not frame 0.
    #expect(posterFrameIndex(luminances: [0.0, 0.0, 0.3, 0.34, 0.31, 0.9]) == 4)
    // Ties go to the earliest frame.
    #expect(posterFrameIndex(luminances: [0.25, 0.75, 0.25, 0.75]) == 0)
    var screener = FlashScreener()
    for (index, value) in [0.0, 0.0, 0.3, 0.34, 0.31, 0.9].enumerated() {
        screener.add(regions: [Double](repeating: value, count: FlashGrid.regionCount), at: Double(index) * 0.5)
    }
    #expect(screener.measurement?.posterSeconds == 2.0)
    #expect(abs((screener.measurement?.meanLuminance ?? 0) - 1.85 / 6) < 1e-12, "mean over every frame")
    #expect(FlashScreener().measurement == nil)
}

@Test func verdictsAndWhatIsReported() {
    #expect(flashVerdict(flashesPerSecond: 0, fileName: "a.mp4", overrides: []) == .withinLimit)
    #expect(flashVerdict(flashesPerSecond: 3, fileName: "a.mp4", overrides: []) == .withinLimit)
    #expect(flashVerdict(flashesPerSecond: 4, fileName: "a.mp4", overrides: []) == .excluded)
    #expect(flashVerdict(flashesPerSecond: 4, fileName: "a.mp4", overrides: ["a.mp4"]) == .overridden)
    #expect(flashVerdict(flashesPerSecond: 9, fileName: "a.mp4", overrides: ["b.mp4", "A.mp4"]) == .excluded)
    #expect(flashVerdict(flashesPerSecond: 2, fileName: "a.mp4", overrides: ["a.mp4"]) == .withinLimit)
    #expect(flashVerdict(flashesPerSecond: 3.5, fileName: "a.mp4", overrides: []) == .excluded)
    // Logged once per change; videos within the limit aren't logged.
    let current: [String: FlashVerdict] = ["a.mp4": .excluded, "b.mp4": .overridden, "c.mp4": .withinLimit]
    #expect(verdictsToLog(previous: [:], current: current) == ["a.mp4", "b.mp4"])
    #expect(verdictsToLog(previous: ["a.mp4": .excluded, "b.mp4": .overridden], current: current).isEmpty)
    #expect(verdictsToLog(previous: ["a.mp4": .excluded, "b.mp4": .excluded], current: current) == ["b.mp4"])
    #expect(FlashVerdict.overridden.isPlayable && FlashVerdict.withinLimit.isPlayable, "overridden and eligible play")
    #expect(!FlashVerdict.excluded.isPlayable, "Excluded doesn't play")
}
