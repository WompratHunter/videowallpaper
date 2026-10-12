import Foundation
import SharedKernel

// MARK: - Library service
// The Wallpaper folder's Videos: watched for changes, settled, analysed and screened for flashing before use, with the
// catalogue a UI shows and the eligible Videos the Rotation picks from. Analysis is in AnalysisQueue.swift; Posters
// (saved, exported and pruned) in LibraryService+Posters.swift. Every OS touchpoint is a port (LibraryPorts.swift).

@MainActor
public final class LibraryService {
    /// The Library's events, on the main actor; a changed eligible set lets the Rotation decide what plays.
    public var onEvent: (LibraryEvent) -> Void = { _ in }
    /// The `FlashOverride` file names, read each time eligibility is decided.
    public var flashOverrides: () -> [String] = { [] }
    /// Low Power Mode: no Analysis runs while on; one in progress is cancelled and queued again.
    public var isLowPowerMode: Bool {
        get { analyses.isLowPowerMode }
        set { analyses.isLowPowerMode = newValue }
    }

    let folder: WallpaperFolderAccess
    let store: LibraryStore
    let analyser: VideoAnalyser
    let analyses: AnalysisQueue
    private let timer: LibraryTimer
    /// Poster reads and exports still running off the main actor, by request.
    var posterWork: [Int: Task<Void, Never>] = [:]
    var nextPosterWork = 0
    private var settler: FolderSettler
    private var eligible: [EligibleVideo] = []
    private var videos: [CatalogueEntry] = []
    /// The last reported verdict per Video that doesn't simply play, so each exclusion or override is reported once.
    private var reportedVerdicts: [String: FlashVerdict] = [:]

    public init(
        folder: WallpaperFolderAccess,
        analyser: VideoAnalyser,
        store: LibraryStore,
        timer: LibraryTimer = MainQueueTimer()
    ) {
        self.folder = folder
        self.analyser = analyser
        self.store = store
        self.timer = timer
        settler = FolderSettler(launch: [:], now: timer.now)
        analyses = AnalysisQueue(folder: folder, analyser: analyser, store: store)
        analyses.onAnalysed = { [weak self] in self?.eligibilityMayHaveChanged(cause: .analysis) }
        analyses.onEvent = { [weak self] event in
            // The catalogue shows the failure in the snapshot this event publishes.
            if case .analysisFailed = event { self?.scanFolder() }
            self?.emit(event)
        }
    }

    /// Removes the legacy Poster, loads the Analysis cache, seeds the settled Videos, starts watching the folder and
    /// analysing. Call once at launch, after setting `isLowPowerMode` and before the first `eligibleVideos`.
    public func start() {
        removeLegacyPoster()
        analyses.loadCache()
        startFolderWatch()
        let scan = scanFolder()
        eligible = scan.eligible
        reportVerdicts(scan)
        queueAnalysis()
    }

    /// The eligible Videos as of the last settle check or Analysis, so reading them on every tick lists nothing.
    public var eligibleVideos: [EligibleVideo] { eligible }

    /// The folder's Videos right now, settled or not.
    public var videoNames: Set<String> { Set(listVideos().keys) }

    public var slice: LibrarySlice { LibrarySlice(eligible: eligible, videos: videos) }

    func emit(_ event: LibraryEvent) {
        onEvent(event)
    }

    /// The folder's Videos (no other files) with size and modification date, for the settle check.
    func listVideos() -> [String: VideoFile] {
        videoListing(of: folder.list())
    }

    /// Settled Videos that aren't Excluded, analysed or not, newest first: those whose Poster may stand in at launch.
    func videosNotExcluded(present: [String: VideoFile]) -> [String] {
        notExcludedNewestFirst(
            settled: settler.ready.filter { present[$0.key] != nil },
            analyses: analyses(of: present), overrides: flashOverrides())
    }

    private func analyses(of present: [String: VideoFile]) -> [String: Analysis] {
        var analysed: [String: Analysis] = [:]
        for (name, file) in present {
            analysed[name] = analyses.analysis(of: name, file: file)
        }
        return analysed
    }
}

// MARK: - Eligibility

extension LibraryService {
    /// One listing of the folder, with what it means: the eligible Videos, the catalogue and the flash verdicts.
    struct FolderScan {
        let eligible: [EligibleVideo]
        let rates: [String: Double]
        let verdicts: [String: FlashVerdict]
    }

    /// Settled Videos whose Analysis is known and which aren't Excluded, with their mean luminance. The folder is
    /// listed again so a just-deleted or replaced file is skipped in the gap before the next settle check. Updates the
    /// catalogue on the way.
    @discardableResult
    func scanFolder() -> FolderScan {
        let present = listVideos()
        let analysed = analyses(of: present)
        let overrides = flashOverrides()
        videos = catalogue(
            present: present, settled: Set(settler.ready.keys), analyses: analysed,
            failed: Set(present.filter { analyses.hasFailed($0.key, file: $0.value) }.keys), overrides: overrides)
        let settled = present.filter { settler.ready[$0.key] != nil }
        return FolderScan(
            eligible: screenEligible(settled: settled, analyses: analysed, overrides: overrides),
            rates: analysed.mapValues(\.flashesPerSecond),
            verdicts: Dictionary(uniqueKeysWithValues: analysed.map { name, analysis in
                (name, flashVerdict(flashesPerSecond: analysis.flashesPerSecond, fileName: name, overrides: overrides))
            }))
    }

    private func queueAnalysis() {
        analyses.update(present: listVideos(), settled: settler.ready)
    }

    /// After a settle change or a new Analysis: tells the Rotation only when the eligible set changed.
    private func eligibilityMayHaveChanged(cause: EligibilityCause) {
        let scan = scanFolder()
        reportVerdicts(scan)
        guard scan.eligible != eligible else { return }
        eligible = scan.eligible
        emit(.eligibleSetChanged(eligible: scan.eligible, cause: cause))
    }

    /// Reports each Video that is Excluded for flashing (or plays only by override) once, with its rate.
    private func reportVerdicts(_ scan: FolderScan) {
        for name in verdictsToLog(previous: reportedVerdicts, current: scan.verdicts) {
            let rate = scan.rates[name] ?? 0
            emit(scan.verdicts[name] == .excluded
                ? .excluded(VideoID(name), flashesPerSecond: rate)
                : .overridden(VideoID(name), flashesPerSecond: rate))
        }
        reportedVerdicts = scan.verdicts
    }
}

// MARK: - Folder watching

extension LibraryService {
    /// Earlier versions wrote the Poster into the Wallpaper folder; it now lives in Application Support.
    private func removeLegacyPoster() {
        do {
            if try folder.removeLegacyPoster() { emit(.legacyPosterRemoved) }
        } catch {
            emit(.legacyPosterNotRemoved(reason: error.localizedDescription))
        }
    }

    private func startFolderWatch() {
        folder.create()
        // Seeded before the watch so Videos still play if it can't be opened; a copy still running at launch waits
        // for the first check like any other.
        settler = FolderSettler(launch: listVideos(), now: timer.now)
        scheduleSettleCheck()
        guard folder.watch({ [weak self] in self?.folderChanged() }) else {
            emit(.folderNotWatched(path: folder.location.path))
            return
        }
    }

    private func folderChanged() {
        // The catalogue shows a new or growing file as settling at once.
        scanFolder()
        guard settler.noteEvent(listVideos()) else { return }
        scheduleSettleCheck()
    }

    private func scheduleSettleCheck() {
        timer.after(FolderSettler.checkInterval) { [weak self] in self?.settleCheck() }
    }

    /// Only settled Videos reach the player, so a file still being copied is never loaded.
    private func settleCheck() {
        let outcome = settler.check(listVideos())
        if outcome.needsAnotherCheck { scheduleSettleCheck() }
        guard outcome.isReadyChanged else { return }
        // The catalogue first, so the snapshot this event publishes shows what settled.
        scanFolder()
        emit(.settled(videos: settler.ready.keys.sorted().map(VideoID.init)))
        queueAnalysis()
        eligibilityMayHaveChanged(cause: .folderChange)
    }
}
