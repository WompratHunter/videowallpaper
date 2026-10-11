import Application
import CoreGraphics
import Foundation
import Library
import SharedKernel

// MARK: - Fake Library
// Stands in for the Library service until ticket 06 replaces it with fakes of the folder and analyser ports. Tests
// set what the folder holds and report Analysis finishing the way the real Library does.

package final class FakeLibrary: LibraryService {
    package var onEvent: (LibraryEvent) -> Void = { _ in }
    package var flashOverrides: () -> [String] = { [] }
    package var isPowerSaving = false
    package var eligibleVideos: [EligibleVideo]
    package var videoNames: Set<String>
    package private(set) var isStarted = false
    /// Poster requests not yet answered, oldest first; `deliverPoster(for:file:)` answers one as the real Library does.
    package private(set) var posterRequests: [(video: URL, use: (PosterImage) -> Bool)] = []

    /// `eligible`: settled and analysed at launch; `pending`: in the folder, still to be analysed.
    package init(eligible: [EligibleVideo] = [], pending: [String] = []) {
        eligibleVideos = eligible
        videoNames = Set(eligible.map(\.name) + pending)
    }

    package var slice: LibrarySlice { LibrarySlice(eligible: eligibleVideos) }

    package func start() {
        isStarted = true
    }

    package func launchUnderlay(toPlay video: URL?, desktopPicture: URL?) -> PosterImage? { nil }

    package func poster(for video: URL, use: @escaping (PosterImage) -> Bool) {
        posterRequests.append((video, use))
    }

    /// Answers the oldest request for `video` with a Poster saved at `file`: whether it was used, nil if none was asked.
    @discardableResult
    package func deliverPoster(for video: URL, file: URL) -> Bool? {
        guard let index = posterRequests.firstIndex(where: { $0.video == video }) else { return nil }
        let request = posterRequests.remove(at: index)
        return request.use(PosterImage(image: Self.blankImage, file: file))
    }

    private static let blankImage: CGImage = {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = context?.makeImage() else { fatalError("cannot draw a 1x1 image") }
        return image
    }()

    /// Analysis finished and the eligible set changed, as the real Library reports it.
    package func finishAnalysis(_ eligible: [EligibleVideo]) {
        eligibleVideos = eligible
        onEvent(.eligibleSetChanged(eligible: eligible, cause: .analysis))
    }
}
