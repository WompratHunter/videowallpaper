import Foundation
import SharedKernel

// MARK: - Wallpaper folder listing
// Only the user's videos count as a folder change. Finder's .DS_Store (and an older version's hidden Poster) also
// land in the folder; treating those as changes would reset the Recovery backoff and end a rest on the Poster.

package func isWallpaperVideo(named name: String) -> Bool {
    !name.hasPrefix(".") && ["mp4", "mov", "m4v"].contains((name as NSString).pathExtension.lowercased())
}

/// The videos among a folder's entries (name to modification date); events that leave it unchanged are ignored.
package func videoListing<Entry>(of entries: [String: Entry]) -> [String: Entry] {
    entries.filter { isWallpaperVideo(named: $0.key) }
}

// MARK: - Settle check
// A video being copied into the folder grows for a while; loading it early fails or plays a truncated file.
// A file is ready once its size is unchanged across two checks about 3 s apart. The directory watch only fires
// when entries change, not while a file grows, so the settler keeps re-checking until nothing is in flux.

package struct VideoFile: Equatable {
    package let size: Int64
    package let modified: Date

    package init(size: Int64, modified: Date) {
        self.size = size
        self.modified = modified
    }

    /// Whole milliseconds, so a date read back from disk or JSON compares equal to the original.
    package var modifiedMilliseconds: Int64 { version.modifiedMilliseconds }

    package var version: Version { Version(size: size, modified: modified) }
}

/// Videos whose non-zero size is the same in both snapshots, with their latest modification date.
package func settledVideos(earlier: [String: VideoFile], later: [String: VideoFile]) -> [String: Date] {
    later.filter { name, file in file.size > 0 && earlier[name]?.size == file.size }.mapValues(\.modified)
}

package struct SettleOutcome: Equatable {
    /// The settled set changed: the player must re-decide what to show.
    package let isReadyChanged: Bool
    /// Some file is still in flux: schedule another check after `checkInterval`.
    package let needsAnotherCheck: Bool
}

package struct FolderSettler {
    package static let checkInterval: TimeInterval = 3

    /// The settled videos: the only ones the player may load.
    package private(set) var ready: [String: Date]
    /// The snapshot the next scheduled check compares against; nil when no check is pending.
    private var baseline: [String: VideoFile]?

    /// At launch there is no earlier snapshot, so an unchanged modification date stands in for it: a non-empty
    /// video untouched for `checkInterval` is settled and plays at once, while one written more recently waits for
    /// the first check. The launch snapshot is that check's baseline, so a copy that kept the source's date and
    /// is still growing is dropped then too.
    package init(launch snapshot: [String: VideoFile], now: Date) {
        let cutoff = now.addingTimeInterval(-Self.checkInterval)
        ready = snapshot.filter { _, file in file.size > 0 && file.modified <= cutoff }.mapValues(\.modified)
        baseline = snapshot
    }

    /// A folder event. Returns true when the caller should schedule `check` after `checkInterval`.
    package mutating func noteEvent(_ snapshot: [String: VideoFile]) -> Bool {
        guard baseline == nil else { return false }
        baseline = snapshot
        return true
    }

    /// The scheduled check: updates `ready` and says whether the player must hear about it.
    package mutating func check(_ snapshot: [String: VideoFile]) -> SettleOutcome {
        let earlier = baseline ?? [:]
        let before = ready
        ready = settledVideos(earlier: earlier, later: snapshot)
        // A stable empty file (a placeholder that never grows) is not loaded, but not polled forever either:
        // a later folder event starts a new check.
        let inFlux = snapshot.contains { name, file in
            ready[name] == nil && !(file.size == 0 && earlier[name]?.size == 0)
        }
        baseline = inFlux ? snapshot : nil
        return SettleOutcome(isReadyChanged: ready != before, needsAnotherCheck: inFlux)
    }
}
