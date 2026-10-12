import CoreGraphics
import Foundation
import Library
import os
import SharedKernel

// MARK: - Fake Library
// The real Library service on fakes of its ports: an in-memory Wallpaper folder (files with size and mtime, folder
// events and settle checks on demand), a scriptable analyser and an in-memory store. `FakeLibrary(eligible:pending:)`
// sets the folder up as a launch would find it.

@MainActor
package final class FakeLibrary {
    package let folder = FakeWallpaperFolder()
    package let analyser = FakeAnalyser()
    package let store = FakeLibraryStore()
    package let service: LibraryService

    /// `eligible`: in the folder, settled and analysed (in the Analysis cache) at launch. `pending`: in the folder and
    /// settled, their Analysis waiting until the analyser is scripted for them.
    package init(eligible: [EligibleVideo] = [], pending: [String] = []) {
        for video in eligible {
            folder.put(video.name, size: video.version.size, modified: video.version.modified)
            store.seedAnalysis(
                ofVideoAt: folder.location.appendingPathComponent(video.name).path, version: video.version,
                meanLuminance: video.meanLuminance)
        }
        for name in pending { folder.put(name) }
        service = LibraryService(folder: folder, analyser: analyser, store: store, timer: folder)
    }

    /// Whether the Library started (it watches the folder from then on).
    package var isStarted: Bool { folder.isWatched }

    /// Where the Library keeps the Poster of `video`'s Version (`FakeLibrary(eligible:)` puts it in the folder).
    nonisolated package static func posterFile(of video: EligibleVideo) -> URL {
        let path = FakeWallpaperFolder.defaultLocation
            .appendingPathComponent(video.name).path
        let file = VideoFile(size: video.version.size, modified: video.version.modified)
        return FakeLibraryStore.posterDirectory.appendingPathComponent(posterFileName(forVideoAt: path, file: file))
    }
}

// MARK: - Fake Wallpaper folder

/// The folder's files in memory. Each change is a folder event, as the directory watch reports it; the settle check's
/// timer runs only when a test passes the settle interval.
@MainActor
package final class FakeWallpaperFolder: WallpaperFolderAccess, LibraryTimer {
    nonisolated package static let defaultLocation = URL(fileURLWithPath: "/fake/LiveWallpaper", isDirectory: true)
    package let location = FakeWallpaperFolder.defaultLocation
    package private(set) var files: [String: VideoFile] = [:]
    package private(set) var isWatched = false
    package private(set) var now = Date(timeIntervalSince1970: 1_791_032_645)
    package var hasLegacyPoster = false
    private var onChange: (@MainActor () -> Void)?
    private var settleChecks: [@MainActor () -> Void] = []

    package init() {}

    /// A file already in the folder (no event), by default the Version `AppHarness.video` describes: written long
    /// before launch.
    package func put(_ name: String, size: Int64 = 1_000, modified: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        files[name] = VideoFile(size: size, modified: modified)
    }

    /// A file appears, grows or is replaced, written now.
    package func write(_ name: String, size: Int64) {
        files[name] = VideoFile(size: size, modified: now)
        onChange?()
    }

    package func remove(_ name: String) {
        files[name] = nil
        onChange?()
    }

    /// Same size and date under a new name, as Finder renames it.
    package func rename(_ name: String, to newName: String) {
        files[newName] = files.removeValue(forKey: name)
        onChange?()
    }

    /// Time passes for every settle check due (about 3 s): runs them, and any they schedule waits for the next call.
    package func passSettleInterval() {
        now = now.addingTimeInterval(3)
        let due = settleChecks
        settleChecks = []
        due.forEach { $0() }
    }

    // MARK: - WallpaperFolderAccess and LibraryTimer

    package func create() {}

    package func list() -> [String: VideoFile] { files }

    package func file(named name: String) -> VideoFile? { files[name] }

    package func watch(_ onChange: @escaping @MainActor () -> Void) -> Bool {
        self.onChange = onChange
        isWatched = true
        return true
    }

    package func removeLegacyPoster() throws -> Bool {
        defer { hasLegacyPoster = false }
        return hasLegacyPoster
    }

    package func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        settleChecks.append(work)
    }
}

// MARK: - Fake analyser

/// Answers each Video by its script: measured values, a failure, or (unscripted) waiting until scripted or cancelled.
package final class FakeAnalyser: VideoAnalyser {
    package enum Script: Sendable {
        case measures(FrameMeasurement)
        case fails
    }

    package struct Failure: Error, CustomStringConvertible {
        package var description: String { "scripted failure" }
    }

    private struct State {
        var scripts: [String: Script] = [:]
        var measured: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    package init() {}

    /// Every Video measured so far, by name, in order (a cancelled or repeated Analysis counts each time).
    package var measured: [String] { state.withLock { $0.measured } }

    package func script(_ name: String, _ script: Script) {
        state.withLock { $0.scripts[name] = script }
    }

    package func script(_ name: String, luminance: Double, flashesPerSecond: Double = 0) {
        script(name, .measures(
            FrameMeasurement(meanLuminance: luminance, flashesPerSecond: flashesPerSecond, posterSeconds: 1)))
    }

    package func isScripted(_ name: String) -> Bool {
        state.withLock { $0.scripts[name] != nil }
    }

    package func measure(_ video: URL) async throws -> FrameMeasurement {
        let name = video.lastPathComponent
        state.withLock { $0.measured.append(name) }
        while true {
            try Task.checkCancellation()
            let script = state.withLock { $0.scripts[name] }
            switch script {
            case .measures(let measurement): return measurement
            case .fails: throw Failure()
            case nil: try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
    }

    package func frame(of video: URL, at seconds: Double, exact: Bool) async throws -> CGImage {
        blankImage
    }
}

// MARK: - Fake store

/// The Analysis cache and Posters in memory. No desktop picture loads.
package final class FakeLibraryStore: LibraryStore {
    package static let posterDirectory = URL(fileURLWithPath: "/fake/posters", isDirectory: true)

    private struct State {
        var cache: Data?
        var posters: Set<String> = []
        var missingPictures: Set<String> = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    package init() {}

    /// Writes an Analysis into the stored cache, in the app's cache format, as an earlier launch would have.
    package func seedAnalysis(
        ofVideoAt path: String, version: Version, meanLuminance: Double, flashesPerSecond: Double = 0
    ) {
        state.withLock { state in
            let stored = state.cache.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            var videos = stored?["videos"] as? [String: Any] ?? [:]
            videos[path] = [
                "size": version.size, "modifiedMilliseconds": version.modifiedMilliseconds,
                "analysis": [
                    "meanLuminance": meanLuminance, "flashesPerSecond": flashesPerSecond, "posterSeconds": 1,
                    "poster": "poster-seeded.jpg"
                ] as [String: Any]
            ]
            state.cache = try? JSONSerialization.data(withJSONObject: ["version": 1, "videos": videos])
        }
    }

    /// The saved Posters' file names.
    package var posters: Set<String> { state.withLock { $0.posters } }

    /// Paths of pictures that can't be read, such as a desktop picture deleted since it was chosen.
    package var missingPictures: Set<String> {
        get { state.withLock { $0.missingPictures } }
        set { state.withLock { $0.missingPictures = newValue } }
    }

    package func loadAnalysisCache() -> Data? { state.withLock { $0.cache } }

    package func saveAnalysisCache(_ data: Data) throws {
        state.withLock { $0.cache = data }
    }

    package func posterNames() -> [String] { state.withLock { $0.posters.sorted() } }

    package func posterFile(named name: String) -> URL { Self.posterDirectory.appendingPathComponent(name) }

    package func savePoster(_ image: CGImage, named name: String) throws {
        state.withLock { _ = $0.posters.insert(name) }
    }

    package func removePoster(named name: String) {
        state.withLock { _ = $0.posters.remove(name) }
    }

    /// One of the store's own Posters loads once it is saved; any other picture (the desktop picture, a Poster an
    /// earlier version left) loads unless it is missing.
    package func loadImage(at file: URL) -> CGImage? {
        let name = file.lastPathComponent
        let isOwnPoster = file.deletingLastPathComponent().path == Self.posterDirectory.path && isPosterFileName(name)
        let loads = isOwnPoster ? posters.contains(name) : !missingPictures.contains(file.path)
        return loads ? blankImage : nil
    }
}

private let blankImage: CGImage = {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let image = context?.makeImage() else { fatalError("cannot draw a 1x1 image") }
    return image
}()
