import SharedKernel

// MARK: - Library slice
// The Library's part of the app snapshot: the Video catalogue (every Video in the Wallpaper folder with its Version and
// why it does or doesn't play) and the eligible Videos the Rotation may pick from.

public struct LibrarySlice: Equatable {
    /// The Videos the Rotation may play, as of the last settle check or Analysis.
    public var eligible: [EligibleVideo]
    /// Every Video in the Wallpaper folder, by name.
    public var videos: [CatalogueEntry]

    public init(eligible: [EligibleVideo] = [], videos: [CatalogueEntry] = []) {
        self.eligible = eligible
        self.videos = videos
    }
}

/// One Video in the catalogue: its current Version and catalogue status.
public struct CatalogueEntry: Equatable {
    public let id: VideoID
    public let version: Version
    public let status: CatalogueStatus

    public init(id: VideoID, version: Version, status: CatalogueStatus) {
        self.id = id
        self.version = version
        self.status = status
    }
}

/// Why a Video does or doesn't play.
public enum CatalogueStatus: Equatable {
    /// Still being copied (or not yet checked): not analysed or played until its size holds across a settle check.
    case settling
    /// Settled and waiting for, or in, Analysis (paused while Low Power Mode is on).
    case analysing
    /// Analysis failed; retried only once the file changes.
    case analysisFailed
    /// Over the flash limit: left out of the Rotation.
    case excluded(flashesPerSecond: Double)
    /// Over the flash limit but in FlashOverride, so it plays.
    case overridden(flashesPerSecond: Double)
    /// Within the flash limit: in the Rotation.
    case eligible

    /// Whether the Rotation may play it.
    public var isPlayable: Bool {
        switch self {
        case .eligible, .overridden: return true
        case .settling, .analysing, .analysisFailed, .excluded: return false
        }
    }
}

// MARK: - Catalogue

/// Every Video present (name to file) with its status: settling until settled, then by its Analysis (verdict with the
/// FlashOverride names) or its failure, else analysing. Sorted by name.
func catalogue(
    present: [String: VideoFile],
    settled: Set<String>,
    analyses: [String: Analysis],
    failed: Set<String>,
    overrides: [String]
) -> [CatalogueEntry] {
    present.map { name, file in
        let status: CatalogueStatus
        if !settled.contains(name) {
            status = .settling
        } else if let analysis = analyses[name] {
            let rate = analysis.flashesPerSecond
            switch flashVerdict(flashesPerSecond: rate, fileName: name, overrides: overrides) {
            case .withinLimit: status = .eligible
            case .excluded: status = .excluded(flashesPerSecond: rate)
            case .overridden: status = .overridden(flashesPerSecond: rate)
            }
        } else {
            status = failed.contains(name) ? .analysisFailed : .analysing
        }
        return CatalogueEntry(id: VideoID(name), version: file.version, status: status)
    }
    .sorted { $0.id < $1.id }
}
