import AppKit

// MARK: - Library
// The Wallpaper folder's videos: watched for changes, settled before use, and the pick of what to play.
// Its Posters (saved, exported and pruned) are in LibraryPosters.swift.

final class Library {
    /// Called on the main queue when the set of settled videos changes, with the video to play now.
    var onChange: (URL?) -> Void = { _ in }

    let directory: URL
    private var folderWatch: DispatchSourceFileSystemObject?
    private var settler = FolderSettler(launch: [:], now: Date())

    init(directory: URL) {
        self.directory = directory
    }

    deinit {
        folderWatch?.cancel()
    }

    /// Removes the legacy Poster, then seeds the settled videos and starts watching the folder. Call once at launch,
    /// before the first `videoToPlay()`.
    func start() {
        removeLegacyPoster()
        startFolderWatch()
    }

    /// "Newest video wins" among settled videos. Existence is re-checked so a rebuild in the gap before the next
    /// settle check skips a just-deleted file.
    func videoToPlay() -> URL? {
        let present = settler.ready.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.key).path)
        }
        return newestVideo(in: present).map { directory.appendingPathComponent($0) }
    }
}

// MARK: - Folder listing

extension Library {
    /// The folder's videos with size and modification date, for the settle check.
    static func videoSnapshot(of dir: URL) -> [String: VideoFile] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Array(keys))) ?? []
        var entries: [String: VideoFile] = [:]
        for item in items {
            let values = try? item.resourceValues(forKeys: keys)
            entries[item.lastPathComponent] = VideoFile(
                size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast)
        }
        return videoListing(of: entries)
    }
}

// MARK: - Folder watching

extension Library {
    /// Earlier versions wrote the Poster into the Wallpaper folder; it now lives in Application Support.
    private func removeLegacyPoster() {
        guard FileManager.default.fileExists(atPath: AppFiles.legacyPoster.path) else { return }
        do {
            try FileManager.default.removeItem(at: AppFiles.legacyPoster)
            Log.write("launch", "removed legacy Poster from the Wallpaper folder")
        } catch {
            Log.write("launch", "cannot remove legacy Poster: \(error.localizedDescription)")
        }
    }

    private func startFolderWatch() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Seeded before the watch so videos still play if it can't be opened; a copy still running at launch
        // waits for the first check like any other.
        settler = FolderSettler(launch: Self.videoSnapshot(of: directory), now: Date())
        scheduleSettleCheck()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.write("launch", "cannot watch \(directory.path): folder changes will not be seen")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main)
        src.setEventHandler { [weak self] in self?.folderChanged() }
        src.setCancelHandler { close(fd) }
        src.resume()
        folderWatch = src
    }

    private func folderChanged() {
        guard settler.noteEvent(Self.videoSnapshot(of: directory)) else { return }
        scheduleSettleCheck()
    }

    private func scheduleSettleCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + FolderSettler.checkInterval) { [weak self] in
            self?.settleCheck()
        }
    }

    /// Only settled videos reach the player, so a file still being copied is never loaded.
    private func settleCheck() {
        let outcome = settler.check(Self.videoSnapshot(of: directory))
        if outcome.needsAnotherCheck { scheduleSettleCheck() }
        guard outcome.isReadyChanged else { return }
        Log.write("folder-change", "settled videos=\(settler.ready.count)")
        onChange(videoToPlay())
    }
}
