import AVFoundation

// MARK: - Analyser smoke test
// Runs the real analyser end to end on generated 2 s clips with a known flash rate. With file arguments it instead
// measures those videos (read only), which is how a real video is checked: `.build/smoke video.mp4 …`.

@main
enum AnalyserSmoke {
    private static let fps: Int32 = 30

    static func main() async {
        let files = CommandLine.arguments.dropFirst()
        if !files.isEmpty {
            await measure(files.map { URL(fileURLWithPath: $0) })
            return
        }
        var failures = 0
        // Full-frame flashing at 3 Hz is at the limit; 5 Hz is over it. Both divide 30 fps into whole half-periods.
        for (hertz, expected) in [(3, FlashVerdict.withinLimit), (5, .excluded)] {
            let clip = FileManager.default.temporaryDirectory
                .appendingPathComponent("videowallpaper-smoke-\(hertz)hz-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: clip) }
            do {
                try await writeClip(to: clip, hertz: hertz)
                let measured = try await LibraryAnalyser.measure(clip)
                let verdict = flashVerdict(flashesPerSecond: measured.flashesPerSecond, fileName: "", overrides: [])
                let isExpected = measured.flashesPerSecond == Double(hertz) && verdict == expected
                if !isExpected { failures += 1 }
                report("\(isExpected ? "ok" : "FAIL") \(hertz) Hz clip: \(describe(measured)) verdict=\(verdict)")
            } catch {
                failures += 1
                report("FAIL \(hertz) Hz clip: \(error)")
            }
        }
        exit(failures == 0 ? 0 : 1)
    }

    private static func measure(_ videos: [URL]) async {
        for video in videos {
            let start = Date()
            do {
                let measured = try await LibraryAnalyser.measure(video)
                let took = String(format: "%.1f", Date().timeIntervalSince(start))
                report("\(video.lastPathComponent): \(describe(measured)) took=\(took)s")
            } catch {
                report("\(video.lastPathComponent): \(error)")
            }
        }
    }

    private static func describe(_ measured: FrameMeasurement) -> String {
        String(
            format: "luminance=%.3f flashes=%.1f/s poster=%.2fs",
            measured.meanLuminance, measured.flashesPerSecond, measured.posterSeconds)
    }

    private static func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    // MARK: - Clip generation

    /// A 2 s, 30 fps H.264 clip alternating between dark and mid grey `hertz` times a second.
    private static func writeClip(to url: URL, hertz: Int) async throws {
        let size = (width: 320, height: 180)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let halfPeriod = Int(fps) / (2 * hertz)
        for frame in 0..<(2 * Int(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            let grey: UInt8 = frame / halfPeriod % 2 == 0 ? 40 : 200
            guard let pool = adaptor.pixelBufferPool, let buffer = filledBuffer(pool: pool, grey: grey) else {
                throw CocoaError(.fileWriteUnknown)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func filledBuffer(pool: CVPixelBufferPool, grey: UInt8) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        memset(base, Int32(grey), CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        return buffer
    }
}
