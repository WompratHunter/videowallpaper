import Application
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

    package func poster(for video: URL, use: @escaping (PosterImage) -> Bool) {}

    /// Analysis finished and the eligible set changed, as the real Library reports it.
    package func finishAnalysis(_ eligible: [EligibleVideo]) {
        eligibleVideos = eligible
        onEvent(.eligibleSetChanged(eligible: eligible, cause: .analysis))
    }
}
