import Foundation

// MARK: - Wallpaper folder adapter
// Today's folder access: a fixed path (or the debug override Platform resolves), listed with FileManager and watched
// with an `O_EVTONLY` dispatch source. The directory watch fires when entries change, not while a file grows; the
// settle check covers that.

@MainActor
public final class FileWallpaperFolder: WallpaperFolderAccess {
    public let location: URL
    /// Written into the Wallpaper folder by versions before Posters moved to Application Support.
    private let legacyPoster: URL
    private var folderWatch: DispatchSourceFileSystemObject?

    public init(location: URL, legacyPoster: URL) {
        self.location = location
        self.legacyPoster = legacyPoster
    }

    deinit {
        folderWatch?.cancel()
    }

    public func create() {
        try? FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
    }

    public func list() -> [String: VideoFile] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: location, includingPropertiesForKeys: Array(Self.keys))) ?? []
        var entries: [String: VideoFile] = [:]
        for item in items {
            let values = try? item.resourceValues(forKeys: Self.keys)
            entries[item.lastPathComponent] = VideoFile(
                size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast)
        }
        return entries
    }

    public func file(named name: String) -> VideoFile? {
        guard let values = try? location.appendingPathComponent(name).resourceValues(forKeys: Self.keys),
              let size = values.fileSize, let modified = values.contentModificationDate
        else { return nil }
        return VideoFile(size: Int64(size), modified: modified)
    }

    public func watch(_ onChange: @escaping @MainActor () -> Void) -> Bool {
        let fd = open(location.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main)
        src.setEventHandler { MainActor.assumeIsolated { onChange() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        folderWatch = src
        return true
    }

    public func removeLegacyPoster() throws -> Bool {
        guard FileManager.default.fileExists(atPath: legacyPoster.path) else { return false }
        try FileManager.default.removeItem(at: legacyPoster)
        return true
    }

    private static let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
}

// MARK: - Settle timer adapter

@MainActor
public final class MainQueueTimer: LibraryTimer {
    public nonisolated init() {}

    public var now: Date { Date() }

    public func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
    }
}
