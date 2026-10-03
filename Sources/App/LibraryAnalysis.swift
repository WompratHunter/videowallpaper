import Foundation

// MARK: - Analysis queue
// Every settled video is analysed once, in the background (utility QoS, one at a time, none in Low Power Mode):
// mean luminance, flash rate and a Poster from a representative frame. Results are cached in Application Support
// (see AnalysisCache.swift) and pruned on each folder scan.

/// Unchecked because its state is only touched on the main queue: the background job captures plain values and
/// hands its result back with `DispatchQueue.main.async`.
final class LibraryAnalysisQueue: @unchecked Sendable {
    /// Called on the main queue after a video's Analysis is stored.
    var onAnalysed: () -> Void = {}

    /// While on, no Analysis runs: one in progress is cancelled and queued again. Turning it off resumes the queue.
    var isPowerSaving = false {
        didSet {
            guard isPowerSaving != oldValue else { return }
            if isPowerSaving { job?.cancel() } else { startNext() }
        }
    }

    private let cacheFile: URL
    private var cache = AnalysisCache()
    /// Settled videos not yet analysed, newest first, with the file they were when queued.
    private var pending: [(video: URL, file: VideoFile)] = []
    /// The video being analysed (see `key`), so a folder scan meanwhile doesn't queue it again.
    private var running: String?
    private var job: Task<Void, Never>?
    /// Videos whose Analysis failed (see `key`): retried only once the file changes.
    private var failed: Set<String> = []

    init(cacheFile: URL) {
        self.cacheFile = cacheFile
    }

    func loadCache() {
        guard let data = try? Data(contentsOf: cacheFile) else { return }
        guard let loaded = AnalysisCache(json: data) else {
            Log.write("analysis", "cache unreadable or from another version; videos will be analysed again")
            return
        }
        cache = loaded
    }

    func analysis(of video: URL, file: VideoFile) -> Analysis? {
        cache.analysis(forVideoAt: video.path, file: file)
    }

    /// After each folder scan: prunes the cache to the folder's videos and queues the settled ones not yet analysed.
    func update(directory: URL, present: [String: VideoFile], settled: [String: Date]) {
        let byPath = Dictionary(uniqueKeysWithValues: present.map {
            (directory.appendingPathComponent($0.key).path, $0.value)
        })
        if cache.prune(present: byPath) { saveCache() }
        let presentKeys = Set(present.map { Self.key(directory.appendingPathComponent($0.key), $0.value) })
        failed.formIntersection(presentKeys)
        let done = Set(present.filter { name, file in
            let key = Self.key(directory.appendingPathComponent(name), file)
            return cache.analysis(forVideoAt: directory.appendingPathComponent(name).path, file: file) != nil
                || failed.contains(key) || key == running
        }.keys)
        let toAnalyse = videosToAnalyse(settled: settled.filter { present[$0.key] != nil }, analysed: done)
        pending = toAnalyse.compactMap { name in present[name].map { (directory.appendingPathComponent(name), $0) } }
        startNext()
    }

    private func startNext() {
        guard running == nil, !isPowerSaving, !pending.isEmpty else { return }
        let (video, file) = pending.removeFirst()
        running = Self.key(video, file)
        let poster = AppFiles.posterDirectory.appendingPathComponent(posterFileName(forVideoAt: video.path, file: file))
        job = Task.detached(priority: .utility) {
            let start = Date()
            let outcome: Result<Analysis, Error>
            do {
                let measured = try await LibraryAnalyser.measure(video)
                let image = try await LibraryAnalyser.posterImage(of: video, at: measured.posterSeconds)
                guard Library.save(image, to: poster) else { throw CocoaError(.fileWriteUnknown) }
                outcome = .success(Analysis(
                    meanLuminance: measured.meanLuminance, flashesPerSecond: measured.flashesPerSecond,
                    posterSeconds: measured.posterSeconds, poster: poster.lastPathComponent))
            } catch {
                // AVFoundation may report a cancelled read or image request as its own error; a cancelled job must
                // be re-queued, not marked failed (which would keep the video from ever playing).
                outcome = .failure(Task.isCancelled ? CancellationError() : error)
            }
            let took = Date().timeIntervalSince(start)
            DispatchQueue.main.async { [weak self] in self?.finish(video, file: file, outcome: outcome, took: took) }
        }
    }

    private func finish(_ video: URL, file: VideoFile, outcome: Result<Analysis, Error>, took: TimeInterval) {
        running = nil
        job = nil
        switch outcome {
        case .success(let analysis):
            cache.store(analysis, forVideoAt: video.path, file: file)
            saveCache()
            Log.write("analysis", String(
                format: "video=%@ luminance=%.3f flashes=%.1f/s poster=%.2fs took=%.1fs", video.lastPathComponent,
                analysis.meanLuminance, analysis.flashesPerSecond, analysis.posterSeconds, took))
            onAnalysed()
        case .failure(is CancellationError):
            pending.insert((video, file), at: 0)
            Log.write("analysis", "video=\(video.lastPathComponent) paused for Low Power Mode")
        case .failure(let error):
            failed.insert(Self.key(video, file))
            Log.write("analysis", "video=\(video.lastPathComponent) failed: \(error); it will not play")
        }
        startNext()
    }

    private func saveCache() {
        do {
            try FileManager.default.createDirectory(at: AppFiles.supportDirectory, withIntermediateDirectories: true)
            try cache.json().write(to: cacheFile, options: .atomic)
        } catch {
            Log.write("analysis", "cannot save cache: \(error.localizedDescription)")
        }
    }

    /// Identifies one version of a video file: its path, size and modification date.
    private static func key(_ video: URL, _ file: VideoFile) -> String {
        "\(video.path)\u{0}\(file.size)\u{0}\(file.modifiedMilliseconds)"
    }
}
