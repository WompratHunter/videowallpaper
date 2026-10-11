import Foundation
import Library
import SharedKernel

// MARK: - Library service
// The Library as the coordinator sees it, with today's legacy `Library` class (Sources/App) as its adapter. A seam
// for the move only: ticket 06 replaces it with the Library context's own service, built on folder and analyser
// ports, and swaps `FakeLibrary` for fakes of those ports.

package protocol LibraryService: AnyObject {
    /// The Library's events, on the main queue.
    var onEvent: (LibraryEvent) -> Void { get set }
    /// The FlashOverride names, read each time eligibility is decided.
    var flashOverrides: () -> [String] { get set }
    /// Low Power Mode: no new Analysis starts while on.
    var isPowerSaving: Bool { get set }
    /// As of the last settle check or Analysis, so reading them on every tick lists nothing.
    var eligibleVideos: [EligibleVideo] { get }
    /// The folder's videos right now, settled or not.
    var videoNames: Set<String> { get }
    var slice: LibrarySlice { get }

    /// Loads the Analysis cache, seeds the settled videos, starts watching the folder and analysing. Once, at launch.
    func start()
    /// A still to show before the first Poster: the saved Poster of `video`, of another video that isn't Excluded,
    /// the desktop picture, or any saved Poster.
    func launchUnderlay(toPlay video: URL?, desktopPicture: URL?) -> PosterImage?
    /// Calls `use` on the main queue with the video's Poster; `use` returns false when the video is no longer wanted.
    func poster(for video: URL, use: @escaping (PosterImage) -> Bool)
}
