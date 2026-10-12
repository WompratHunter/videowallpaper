import CoreGraphics
import Foundation

// MARK: - Library ports
// What the Library needs from the outside, each with today's behaviour as its adapter (in this target) and a fake in
// test support: the Wallpaper folder, the analyser, where Analysis results and Posters are kept, and the settle
// check's timer. The folder is handed in, never read from a global, so a security-scoped bookmark adapter can replace
// the fixed path later.

/// The Wallpaper folder: where it is, what it holds and when it changes. Today's adapter is `FileWallpaperFolder`.
@MainActor
public protocol WallpaperFolderAccess: AnyObject {
    /// The resolved folder; a Video's path in it names its Analysis and Poster.
    var location: URL { get }
    /// Creates the folder if it is missing.
    func create()
    /// Every entry in the folder (videos or not) with its size and modification date.
    func list() -> [String: VideoFile]
    /// One entry's size and modification date, nil when it is gone.
    func file(named name: String) -> VideoFile?
    /// Calls `onChange` on the main actor whenever the folder's entries change. False when it can't be watched.
    func watch(_ onChange: @escaping @MainActor () -> Void) -> Bool
    /// Removes the Poster earlier versions wrote into the folder: true when there was one.
    func removeLegacyPoster() throws -> Bool
}

/// Measures a Version and takes its Poster frame. Called off the main actor; each call returns plain values and throws
/// `CancellationError` soon after its task is cancelled. Today's adapter is `AVFoundationAnalyser`.
public protocol VideoAnalyser: Sendable {
    /// Mean luminance, the worst flash rate and the Poster time, from every frame.
    func measure(_ video: URL) async throws -> FrameMeasurement
    /// The frame at `seconds`, full size up to 4K: exactly that frame, or the nearest one that decodes quickly.
    func frame(of video: URL, at seconds: Double, exact: Bool) async throws -> CGImage
}

/// Where the Library keeps its own data: the Analysis cache and the Posters, never in the Wallpaper folder. Called off
/// the main actor too (a 4K JPEG takes long enough to decode to stall it). Today's adapter is `FileLibraryStore`.
public protocol LibraryStore: Sendable {
    /// The stored Analysis cache, nil when there is none.
    func loadAnalysisCache() -> Data?
    func saveAnalysisCache(_ data: Data) throws
    /// The file names in the Poster folder.
    func posterNames() -> [String]
    /// Where the Poster of that name is kept: the file that becomes the desktop picture.
    func posterFile(named name: String) -> URL
    func savePoster(_ image: CGImage, named name: String) throws
    func removePoster(named name: String)
    /// Decodes a still: a saved Poster or the desktop picture. Nil when it is missing or unreadable. Blocks while it
    /// decodes: the launch underlay waits for it, every other Poster is read off the main actor.
    func loadImage(at file: URL) -> CGImage?
}

/// The settle check's clock: the time a launch snapshot is compared with, and its re-checks. Today's adapter is
/// `MainQueueTimer`.
@MainActor
public protocol LibraryTimer: AnyObject {
    var now: Date { get }
    /// Calls `work` once, on the main actor, after `seconds`.
    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void)
}
