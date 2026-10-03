import AppKit

// MARK: - Library
// The Wallpaper folder's videos: watched for changes, settled, analysed and screened for flashing before use, and
// the pick of what to play. Analysis is in LibraryAnalysis.swift and LibraryAnalyser.swift; Posters (saved, exported
// and pruned) in LibraryPosters.swift.

final class Library {
    /// Called on the main queue when the set of eligible videos changes; the Rotation decides what plays.
    var onChange: () -> Void = {}
    /// The `FlashOverride` file names, read each time eligibility is decided.
    var flashOverrides: () -> [String] = { [] }
    /// Low Power Mode: no new Analysis starts while on.
    var isPowerSaving: Bool {
        get { analyses.isPowerSaving }
        set { analyses.isPowerSaving = newValue }
    }

    let directory: URL
    let analyses: LibraryAnalysisQueue
    private var folderWatch: DispatchSourceFileSystemObject?
    private var settler = FolderSettler(launch: [:], now: Date())
    private var eligible: [EligibleVideo] = []
    /// The last logged verdict per video that doesn't simply play, so each exclusion or override is logged once.
    private var loggedVerdicts: [String: FlashVerdict] = [:]

    init(directory: URL, analysisCache: URL) {
        self.directory = directory
        analyses = LibraryAnalysisQueue(cacheFile: analysisCache)
        analyses.onAnalysed = { [weak self] in self?.eligibilityMayHaveChanged(cause: "analysis") }
    }

    deinit {
        folderWatch?.cancel()
    }

    /// Removes the legacy Poster, loads the Analysis cache, seeds the settled videos, starts watching the folder and
    /// analysing. Call once at launch, after setting `isPowerSaving` and before the first `eligibleVideos()`.
    func start() {
        removeLegacyPoster()
        analyses.loadCache()
        startFolderWatch()
        eligible = eligibleVideos()
        logVerdicts()
        queueAnalysis()
    }

    /// Settled videos whose Analysis is known and which aren't Excluded, with their mean luminance. The folder is
    /// listed again so a just-deleted or replaced file is skipped in the gap before the next settle check.
    func eligibleVideos() -> [EligibleVideo] {
        let present = Self.videoSnapshot(of: directory)
        let settled = settler.ready.filter { present[$0.key] != nil }
        var analysed: [String: Analysis] = [:]
        for (name, file) in present {
            analysed[name] = analyses.analysis(of: directory.appendingPathComponent(name), file: file)
        }
        return screenEligible(settled: settled, analyses: analysed, overrides: flashOverrides())
    }

    /// Settled videos that aren't Excluded, analysed or not, newest first: those whose Poster may stand in at launch.
    func videosNotExcluded() -> [URL] {
        let present = Self.videoSnapshot(of: directory)
        var analysed: [String: Analysis] = [:]
        for (name, file) in present {
            analysed[name] = analyses.analysis(of: directory.appendingPathComponent(name), file: file)
        }
        return notExcludedNewestFirst(
            settled: settler.ready.filter { present[$0.key] != nil }, analyses: analysed, overrides: flashOverrides()
        ).map { directory.appendingPathComponent($0) }
    }
}

// MARK: - Eligibility

extension Library {
    private func queueAnalysis() {
        analyses.update(directory: directory, present: Self.videoSnapshot(of: directory), settled: settler.ready)
    }

    /// After a settle change or a new Analysis: tells the player only when the eligible set changed.
    private func eligibilityMayHaveChanged(cause: String) {
        logVerdicts()
        let now = eligibleVideos()
        guard now != eligible else { return }
        eligible = now
        Log.write(cause, "eligible videos=\(now.count)")
        onChange()
    }

    /// Logs each video that is Excluded for flashing (or plays only by override) once, with its rate.
    private func logVerdicts() {
        let overrides = flashOverrides()
        let present = Self.videoSnapshot(of: directory)
        var rates: [String: Double] = [:]
        var verdicts: [String: FlashVerdict] = [:]
        for (name, file) in present {
            guard let rate = analyses.analysis(of: directory.appendingPathComponent(name), file: file)?.flashesPerSecond
            else { continue }
            rates[name] = rate
            verdicts[name] = flashVerdict(flashesPerSecond: rate, fileName: name, overrides: overrides)
        }
        for name in verdictsToLog(previous: loggedVerdicts, current: verdicts) {
            let rate = String(format: "%.1f", rates[name] ?? 0)
            Log.write("flash", verdicts[name] == .excluded
                ? "excluded video=\(name) flashes=\(rate)/s (limit \(Int(FlashVerdict.limitPerSecond))/s)"
                : "override video=\(name) flashes=\(rate)/s plays (in FlashOverride)")
        }
        loggedVerdicts = verdicts
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
        queueAnalysis()
        eligibilityMayHaveChanged(cause: "folder-change")
    }
}
