import AVFoundation

// MARK: - Analyser adapter
// Decodes every frame of a video at reduced resolution and feeds it to the FlashScreener. AVFoundation only (no
// AppKit); public, so the smoke runner checks the same analyser the app uses.

public struct AVFoundationAnalyser: VideoAnalyser {
    /// Small enough to decode cheaply; each of the 12x12 cells is still 16x9 pixels. The decoder scales to it.
    private static let width = 192
    private static let height = 108

    enum Failure: Error {
        case noVideoTrack
        case unreadable(String)
    }

    public init() {}

    /// Blocks while it decodes, so call it off the main actor; a 20 s 4K60 clip takes a few seconds.
    public func measure(_ video: URL) async throws -> FrameMeasurement {
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noVideoTrack }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw Failure.unreadable(reader.error?.localizedDescription ?? "cannot start reading")
        }
        var screener = FlashScreener()
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            guard let cells = Self.cellLuminances(of: sample) else { continue }
            screener.add(
                regions: FlashGrid.regions(cells: cells),
                at: CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        if reader.status == .failed {
            throw Failure.unreadable(reader.error?.localizedDescription ?? "decoding failed")
        }
        guard let measurement = screener.measurement else { throw Failure.unreadable("no frames") }
        return measurement
    }

    /// Exact for Analysis, so the Poster is the frame it chose rather than the nearest keyframe.
    public func frame(of video: URL, at seconds: Double, exact: Bool) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 3840, height: 2160)
        if exact {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        }
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private static func cellLuminances(of sample: CMSampleBuffer) -> [Double]? {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let frameHeight = CVPixelBufferGetHeight(buffer)
        return FlashGrid.cellLuminances(
            bgra: UnsafeRawBufferPointer(start: base, count: bytesPerRow * frameHeight),
            width: CVPixelBufferGetWidth(buffer), height: frameHeight, bytesPerRow: bytesPerRow)
    }
}
