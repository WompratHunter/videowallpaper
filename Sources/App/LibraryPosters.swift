import AppKit
import AVFoundation

// MARK: - Posters for the window underlay, Mission Control and the Lock screen
// Kept in Application Support, one per video (see PosterFiles.swift), never in the Wallpaper folder.

/// A video's Poster image, with its saved file when there is one (the file is what becomes the desktop picture).
struct PosterImage {
    let image: CGImage
    let file: URL?
}

extension Library {
    /// The launch underlay, read synchronously so the window is never empty while the player starts or while the
    /// first Analysis runs: the saved Poster of the video to play, else of another video that isn't Excluded, else
    /// the desktop picture, else any saved Poster (see `underlayCandidates`).
    func launchUnderlay(toPlay video: URL?, desktopPicture: URL?) -> CGImage? {
        let saved = (try? FileManager.default.contentsOfDirectory(atPath: AppFiles.posterDirectory.path)) ?? []
        let candidates = underlayCandidates(
            toPlay: video.flatMap(Self.posterURL)?.lastPathComponent,
            waiting: videosNotExcluded().compactMap { Self.posterURL(for: $0)?.lastPathComponent },
            saved: saved)
        for candidate in candidates {
            let url: URL?
            switch candidate {
            case .poster(let name): url = AppFiles.posterDirectory.appendingPathComponent(name)
            case .desktopPicture: url = desktopPicture
            }
            guard let url, let image = Self.loadImage(url) else { continue }
            if video == nil { Log.write("launch", "no screened video yet; underlay=\(url.lastPathComponent)") }
            return image
        }
        Log.write("launch", "no Poster or desktop picture to show under the video")
        return nil
    }

    /// Reuses the video's saved Poster (normally saved by its Analysis), or exports and saves one, then calls `use` on
    /// the main queue. `use` returns false when the video is no longer wanted; a used Poster prunes the stale ones.
    /// Decoding a 4K JPEG takes long enough to stall the main thread, so the saved Poster is read in the background.
    func poster(for video: URL, use: @escaping (PosterImage) -> Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let poster = Self.posterURL(for: video) else { return }
            guard let image = Self.loadImage(poster) else {
                DispatchQueue.main.async { [weak self] in self?.exportPoster(from: video, to: poster, use: use) }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard use(PosterImage(image: image, file: poster)) else { return }
                self?.pruneStalePosters(current: poster)
            }
        }
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func exportPoster(from video: URL, to poster: URL, use: @escaping (PosterImage) -> Bool) {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 3840, height: 2160)
        // The frame Analysis chose; the first frame if the video has no Analysis yet.
        let seconds = Self.videoSnapshot(of: directory)[video.lastPathComponent]
            .flatMap { analyses.analysis(of: video, file: $0) }?.posterSeconds ?? 0
        gen.generateCGImageAsynchronously(for: CMTime(seconds: seconds, preferredTimescale: 600)) { img, _, err in
            guard let img, err == nil else { return }
            let isSaved = Self.save(img, to: poster)
            DispatchQueue.main.async { [weak self] in
                guard use(PosterImage(image: img, file: isSaved ? poster : nil)), isSaved else { return }
                self?.pruneStalePosters(current: poster)
            }
        }
    }

    static func save(_ image: CGImage, to poster: URL) -> Bool {
        let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        do {
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.createDirectory(at: AppFiles.posterDirectory, withIntermediateDirectories: true)
            try data.write(to: poster, options: .atomic)
            return true
        } catch {
            Log.write("poster", "cannot save \(poster.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    /// Posters of videos no longer in the folder are deleted, so Application Support doesn't grow forever.
    private func pruneStalePosters(current: URL) {
        // Named by posterURL(for:), like the Poster just saved, so a fresh Poster is never pruned.
        let keep = Set(Self.videoSnapshot(of: directory).keys.compactMap {
            Self.posterURL(for: directory.appendingPathComponent($0))?.lastPathComponent
        })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: AppFiles.posterDirectory.path)) ?? []
        for name in stalePosters(in: names, keeping: keep, current: current.lastPathComponent) {
            try? FileManager.default.removeItem(at: AppFiles.posterDirectory.appendingPathComponent(name))
        }
    }

    /// Where a video's Poster is kept: its name changes when the file is replaced, so a stale Poster is never shown.
    private static func posterURL(for video: URL) -> URL? {
        guard let values = try? video.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let size = values.fileSize, let modified = values.contentModificationDate
        else { return nil }
        let file = VideoFile(size: Int64(size), modified: modified)
        return AppFiles.posterDirectory.appendingPathComponent(posterFileName(forVideoAt: video.path, file: file))
    }
}
