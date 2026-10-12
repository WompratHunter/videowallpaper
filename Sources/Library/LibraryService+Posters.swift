import CoreGraphics
import Foundation
import SharedKernel

// MARK: - Posters for the window underlay, Mission Control and the Lock screen
// Kept in the store, one per Version (see PosterFiles.swift), never in the Wallpaper folder.

extension LibraryService {
    /// The launch underlay, read synchronously so the window is never empty while the player starts or while the
    /// first Analysis runs: the saved Poster of the video to play, else of another Video that isn't Excluded, else
    /// the desktop picture, else any saved Poster (see `underlayCandidates`).
    public func launchUnderlay(toPlay video: URL?, desktopPicture: URL?) -> PosterImage? {
        let present = listVideos()
        let candidates = underlayCandidates(
            toPlay: video.flatMap { posterName(of: $0.lastPathComponent, file: present[$0.lastPathComponent]) },
            waiting: videosNotExcluded(present: present).compactMap { posterName(of: $0, file: present[$0]) },
            saved: store.posterNames())
        for candidate in candidates {
            let file: URL?
            let isPoster: Bool
            switch candidate {
            case .poster(let name): (file, isPoster) = (store.posterFile(named: name), true)
            case .desktopPicture: (file, isPoster) = (desktopPicture, false)
            }
            guard let file, let image = store.loadImage(at: file) else { continue }
            if video == nil { emit(.launchUnderlay(fileName: file.lastPathComponent)) }
            // A Poster's file is what becomes the desktop picture; the desktop picture itself is not ours to set.
            return PosterImage(image: image, file: isPoster ? file : nil)
        }
        emit(.noLaunchUnderlay)
        return nil
    }

    /// Reuses the Version's saved Poster (normally saved by its Analysis), or exports and saves one, then calls `use` on
    /// the main actor. `use` returns false when the video is no longer wanted; a used Poster prunes the stale ones.
    /// Decoding a 4K JPEG takes long enough to stall the main thread, so the saved Poster is read off it.
    public func poster(for video: URL, use: @escaping (PosterImage) -> Bool) {
        let name = video.lastPathComponent
        guard let file = folder.file(named: name), let poster = posterName(of: name, file: file) else { return }
        let saved = store.posterFile(named: poster)
        let store = store
        runPosterWork { [weak self] in
            guard let image = await Self.loadImage(saved, from: store) else {
                await self?.exportPoster(of: name, file: file, to: poster, use: use)
                return
            }
            guard let self, use(PosterImage(image: image, file: saved)) else { return }
            prunePosters(current: poster)
        }
    }

    /// Exports the Poster from the frame Analysis chose (the first frame if the Version has no Analysis yet), saves
    /// it and hands it to `use`, saved or not.
    private func exportPoster(
        of name: String, file: VideoFile, to poster: String, use: @escaping (PosterImage) -> Bool
    ) async {
        let seconds = analyses.analysis(of: name, file: file)?.posterSeconds ?? 0
        let video = folder.location.appendingPathComponent(name)
        guard let exported = await Self.export(video, at: seconds, to: poster, analyser: analyser, store: store)
        else { return }
        if let reason = exported.notSaved { emit(.posterNotSaved(fileName: poster, reason: reason)) }
        let isSaved = exported.notSaved == nil
        guard use(PosterImage(image: exported.image, file: isSaved ? store.posterFile(named: poster) : nil)), isSaved
        else { return }
        prunePosters(current: poster)
    }

    /// Posters of Versions no longer in the folder are deleted, so the store doesn't grow forever.
    private func prunePosters(current: String) {
        // Named by `posterName`, like the Poster just saved, so a fresh Poster is never pruned.
        let keep = Set(listVideos().compactMap { posterName(of: $0.key, file: $0.value) })
        for name in stalePosters(in: store.posterNames(), keeping: keep, current: current) {
            store.removePoster(named: name)
        }
    }

    /// The Poster's file name for this Version: it changes when the file is replaced, so a stale Poster is never shown.
    private func posterName(of name: String, file: VideoFile?) -> String? {
        file.map { posterFileName(forVideoAt: folder.location.appendingPathComponent(name).path, file: $0) }
    }

    /// Runs `work` as a task the Library keeps until it ends.
    private func runPosterWork(_ work: @escaping @MainActor () async -> Void) {
        let id = nextPosterWork
        nextPosterWork += 1
        posterWork[id] = Task(priority: .utility) { [weak self] in
            await work()
            self?.posterWork[id] = nil
        }
    }
}

// MARK: - Poster work off the main actor

extension LibraryService {
    private nonisolated static func loadImage(_ file: URL, from store: LibraryStore) async -> CGImage? {
        store.loadImage(at: file)
    }

    /// The frame, and why it couldn't be saved if it couldn't. Nil when the frame can't be read.
    private nonisolated static func export(
        _ video: URL, at seconds: Double, to poster: String, analyser: VideoAnalyser, store: LibraryStore
    ) async -> (image: CGImage, notSaved: String?)? {
        guard let image = try? await analyser.frame(of: video, at: seconds, exact: false) else { return nil }
        do {
            try store.savePoster(image, named: poster)
            return (image, nil)
        } catch {
            return (image, error.localizedDescription)
        }
    }
}
