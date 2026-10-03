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
    /// The video's saved Poster, read synchronously so the underlay isn't empty while the player starts.
    func savedPoster(for video: URL) -> CGImage? {
        posterURL(for: video).flatMap(Self.loadImage)
    }

    /// Reuses the video's saved Poster, or exports and saves one, then calls `use` on the main queue. `use` returns
    /// false when the video is no longer wanted; a freshly saved Poster that was used prunes the stale ones.
    /// Decoding a 4K JPEG takes long enough to stall the main thread, so the saved Poster is read in the background.
    func poster(for video: URL, use: @escaping (PosterImage) -> Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let poster = posterURL(for: video) else { return }
            guard let image = Self.loadImage(poster) else {
                DispatchQueue.main.async { [weak self] in self?.exportPoster(from: video, to: poster, use: use) }
                return
            }
            DispatchQueue.main.async { _ = use(PosterImage(image: image, file: poster)) }
        }
    }

    /// Earlier versions wrote the Poster into the Wallpaper folder; it now lives in Application Support.
    func removeLegacyPoster() {
        guard FileManager.default.fileExists(atPath: AppFiles.legacyPoster.path) else { return }
        do {
            try FileManager.default.removeItem(at: AppFiles.legacyPoster)
            Log.write("launch", "removed legacy Poster from the Wallpaper folder")
        } catch {
            Log.write("launch", "cannot remove legacy Poster: \(error.localizedDescription)")
        }
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func exportPoster(from video: URL, to poster: URL, use: @escaping (PosterImage) -> Bool) {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 3840, height: 2160)
        gen.generateCGImageAsynchronously(for: CMTime(seconds: 5, preferredTimescale: 600)) { img, _, err in
            guard let img, err == nil else { return }
            let isSaved = Self.save(img, to: poster)
            DispatchQueue.main.async { [weak self] in
                guard use(PosterImage(image: img, file: isSaved ? poster : nil)), isSaved else { return }
                self?.pruneStalePosters(current: poster)
            }
        }
    }

    private static func save(_ image: CGImage, to poster: URL) -> Bool {
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
        let keep = Set(videoSnapshot(of: directory).keys.compactMap {
            posterURL(for: directory.appendingPathComponent($0))?.lastPathComponent
        })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: AppFiles.posterDirectory.path)) ?? []
        for name in stalePosters(in: names, keeping: keep, current: current.lastPathComponent) {
            try? FileManager.default.removeItem(at: AppFiles.posterDirectory.appendingPathComponent(name))
        }
    }
}

/// Where a video's Poster is kept: its name changes when the file is replaced, so a stale Poster is never shown.
func posterURL(for video: URL) -> URL? {
    guard let values = try? video.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
          let size = values.fileSize, let modified = values.contentModificationDate
    else { return nil }
    let file = VideoFile(size: Int64(size), modified: modified)
    return AppFiles.posterDirectory.appendingPathComponent(posterFileName(forVideoAt: video.path, file: file))
}
