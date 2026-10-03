import Foundation

// MARK: - Wallpaper folder listing
// Only the user's videos count as a folder change. The hidden Poster export and Finder's .DS_Store also land in
// the folder; treating those as changes would reset the Recovery backoff and end a rest on the Poster for nothing.

func isWallpaperVideo(named name: String) -> Bool {
    !name.hasPrefix(".") && ["mp4", "mov", "m4v"].contains((name as NSString).pathExtension.lowercased())
}

/// The videos among a folder's entries (name to modification date); events that leave it unchanged are ignored.
func videoListing<Entry>(of entries: [String: Entry]) -> [String: Entry] {
    entries.filter { isWallpaperVideo(named: $0.key) }
}

/// "Newest video wins": the latest modification date, ties broken by name so the pick is stable.
func newestVideo(in listing: [String: Date]) -> String? {
    listing.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
}

// MARK: - Settle check
// A video being copied into the folder grows for a while; loading it early fails or plays a truncated file.
// A file is ready once its size is unchanged across two checks about 3 s apart. The directory watch only fires
// when entries change, not while a file grows, so the settler keeps re-checking until nothing is in flux.

struct VideoFile: Equatable {
    let size: Int64
    let modified: Date
}

/// Videos whose non-zero size is the same in both snapshots, with their latest modification date.
func settledVideos(earlier: [String: VideoFile], later: [String: VideoFile]) -> [String: Date] {
    later.filter { name, file in file.size > 0 && earlier[name]?.size == file.size }.mapValues(\.modified)
}

struct FolderSettler {
    static let checkInterval: TimeInterval = 3

    /// The settled videos: the only ones the player may load.
    private(set) var ready: [String: Date]
    /// The snapshot the next scheduled check compares against; nil when no check is pending.
    private var baseline: [String: VideoFile]?

    init(trusting snapshot: [String: VideoFile]) {
        ready = snapshot.mapValues(\.modified)
    }

    /// A folder event. Returns true when the caller should schedule `check` after `checkInterval`.
    mutating func noteEvent(_ snapshot: [String: VideoFile]) -> Bool {
        guard baseline == nil else { return false }
        baseline = snapshot
        return true
    }

    /// The scheduled check. Updates `ready` and returns true when another check is needed.
    mutating func check(_ snapshot: [String: VideoFile]) -> Bool {
        let earlier = baseline ?? [:]
        ready = settledVideos(earlier: earlier, later: snapshot)
        // A stable empty file (a placeholder that never grows) is not loaded, but not polled forever either:
        // a later folder event starts a new check.
        let inFlux = snapshot.contains { name, file in
            ready[name] == nil && !(file.size == 0 && earlier[name]?.size == 0)
        }
        baseline = inFlux ? snapshot : nil
        return inFlux
    }
}

// MARK: - Folder change decision

enum FolderChangeAction: Equatable {
    case keepPlaying
    case switchTo(URL)
    /// Show the Poster and rebuild at once, replacing any backoff timer. The settle check already debounced
    /// the burst of folder events, so no further delay is needed.
    case rebuildNow(RecoveryCause)
    case restNoVideo
    /// Low Power Mode: no player is built; leaving it re-picks the newest video.
    case waitForPower
}

/// What to do when the folder's set of settled videos changes. `isRecovering` covers a pending rebuild and any rest on
/// the Poster; a video becoming available then rebuilds promptly instead of waiting out the backoff.
func folderChangeAction(
    newest: URL?, current: URL?, currentExists: Bool, isRecovering: Bool, isPowerSaving: Bool
) -> FolderChangeAction {
    if isPowerSaving { return .waitForPower }
    guard let newest else { return .restNoVideo }
    if current != nil && !currentExists { return .rebuildNow(.fileMissing) }
    if isRecovering { return .rebuildNow(.videoAvailable) }
    return newest == current ? .keepPlaying : .switchTo(newest)
}
