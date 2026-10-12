import CoreGraphics
import Foundation
import SharedKernel

// MARK: - Analysis queue
// Every settled Version is analysed once, off the main actor (utility priority, one at a time, none in Low Power Mode):
// mean luminance, flash rate and a Poster from a representative frame. The analyser and store hand back plain values;
// the queue's own state is only touched on the main actor. Results are cached in the store (see AnalysisCache.swift)
// and pruned on each folder scan.

@MainActor
final class AnalysisQueue {
    /// After a Version's Analysis is stored.
    var onAnalysed: () -> Void = {}
    var onEvent: (LibraryEvent) -> Void = { _ in }

    /// While on, no Analysis runs: one in progress is cancelled and queued again. Turning it off resumes the queue.
    var isLowPowerMode = false {
        didSet {
            guard isLowPowerMode != oldValue else { return }
            if isLowPowerMode { job?.cancel() } else { startNext() }
        }
    }

    /// The Analysis in progress, if any.
    private(set) var job: Task<Void, Never>?
    /// The Version being analysed, so a folder scan meanwhile doesn't queue it again.
    private(set) var running: VersionKey?

    private let folder: WallpaperFolderAccess
    private let analyser: VideoAnalyser
    private let store: LibraryStore
    private var cache = AnalysisCache()
    /// Settled Videos not yet analysed, newest first, with the file they were when queued.
    private var pending: [(name: String, file: VideoFile)] = []
    /// Versions whose Analysis failed: retried only once the file changes.
    private var failed: Set<VersionKey> = []

    init(folder: WallpaperFolderAccess, analyser: VideoAnalyser, store: LibraryStore) {
        self.folder = folder
        self.analyser = analyser
        self.store = store
    }

    func loadCache() {
        guard let data = store.loadAnalysisCache() else { return }
        guard let loaded = AnalysisCache(json: data) else {
            onEvent(.analysisCacheUnreadable)
            return
        }
        cache = loaded
    }

    func analysis(of name: String, file: VideoFile) -> Analysis? {
        cache.analysis(forVideoAt: path(of: name), file: file)
    }

    func hasFailed(_ name: String, file: VideoFile) -> Bool {
        failed.contains(VersionKey(name, file))
    }

    /// After each folder scan: prunes the cache to the folder's Videos and queues the settled ones not yet analysed.
    func update(present: [String: VideoFile], settled: [String: Date]) {
        let byPath = Dictionary(uniqueKeysWithValues: present.map { (path(of: $0.key), $0.value) })
        if cache.prune(present: byPath) { saveCache() }
        failed.formIntersection(present.map { VersionKey($0.key, $0.value) })
        let done = Set(present.filter { name, file in
            let key = VersionKey(name, file)
            return analysis(of: name, file: file) != nil || failed.contains(key) || key == running
        }.keys)
        let toAnalyse = videosToAnalyse(settled: settled.filter { present[$0.key] != nil }, analysed: done)
        pending = toAnalyse.compactMap { name in present[name].map { (name, $0) } }
        startNext()
    }

    private func path(of name: String) -> String {
        folder.location.appendingPathComponent(name).path
    }

    private func startNext() {
        guard running == nil, !isLowPowerMode, !pending.isEmpty else { return }
        let (name, file) = pending.removeFirst()
        running = VersionKey(name, file)
        let video = folder.location.appendingPathComponent(name)
        let poster = posterFileName(forVideoAt: video.path, file: file)
        let analyser = analyser
        let store = store
        job = Task(priority: .utility) { [weak self] in
            let run = await Self.analyse(video, poster: poster, analyser: analyser, store: store)
            self?.finish(name, file: file, run: run)
        }
    }

    private func finish(_ name: String, file: VideoFile, run: AnalysisRun) {
        running = nil
        job = nil
        if let reason = run.posterNotSaved { onEvent(.posterNotSaved(fileName: run.poster, reason: reason)) }
        switch run.outcome {
        case .success(let analysis):
            cache.store(analysis, forVideoAt: path(of: name), file: file)
            saveCache()
            onEvent(.analysed(VideoID(name), version: file.version, report: AnalysisReport(
                meanLuminance: analysis.meanLuminance, flashesPerSecond: analysis.flashesPerSecond,
                posterSeconds: analysis.posterSeconds, took: run.took)))
            onAnalysed()
        case .failure(is CancellationError):
            pending.insert((name, file), at: 0)
            onEvent(.analysisPaused(VideoID(name)))
        case .failure(let error):
            failed.insert(VersionKey(name, file))
            onEvent(.analysisFailed(VideoID(name), reason: "\(error)"))
        }
        startNext()
    }

    private func saveCache() {
        do {
            try store.saveAnalysisCache(cache.json())
        } catch {
            onEvent(.analysisCacheNotSaved(reason: error.localizedDescription))
        }
    }
}

// MARK: - Analysis off the main actor

extension AnalysisQueue {
    /// One Analysis, run on the analyser's executor rather than the main actor: measures, takes the Poster frame and
    /// saves it. Only plain values go in and come out.
    private nonisolated static func analyse(
        _ video: URL, poster: String, analyser: VideoAnalyser, store: LibraryStore
    ) async -> AnalysisRun {
        let start = Date()
        var posterNotSaved: String?
        let outcome: Result<Analysis, Error>
        do {
            let measured = try await analyser.measure(video)
            let image = try await analyser.frame(of: video, at: measured.posterSeconds, exact: true)
            do {
                try store.savePoster(image, named: poster)
            } catch {
                posterNotSaved = error.localizedDescription
                throw CocoaError(.fileWriteUnknown)
            }
            outcome = .success(Analysis(
                meanLuminance: measured.meanLuminance, flashesPerSecond: measured.flashesPerSecond,
                posterSeconds: measured.posterSeconds, poster: poster))
        } catch {
            // AVFoundation may report a cancelled read or image request as its own error; a cancelled job must be
            // re-queued, not marked failed (which would keep the video from ever playing).
            outcome = .failure(Task.isCancelled ? CancellationError() : error)
        }
        return AnalysisRun(
            outcome: outcome, took: Date().timeIntervalSince(start), poster: poster, posterNotSaved: posterNotSaved)
    }
}

/// What one Analysis hands back to the main actor.
private struct AnalysisRun: Sendable {
    let outcome: Result<Analysis, Error>
    let took: TimeInterval
    /// The Poster's file name, and why it couldn't be saved if it couldn't.
    let poster: String
    let posterNotSaved: String?
}

/// One Version of one Video: what Analysis and Posters are keyed by.
struct VersionKey: Hashable {
    let name: String
    let version: Version

    init(_ name: String, _ file: VideoFile) {
        self.name = name
        version = file.version
    }
}
