import Foundation

// MARK: - Wallpaper folder listing
// Only the user's videos count as a folder change. The hidden Poster export and Finder's .DS_Store also land in
// the folder; treating those as changes would reset the Recovery backoff and end a rest on the Poster for nothing.

func isWallpaperVideo(named name: String) -> Bool {
    !name.hasPrefix(".") && ["mp4", "mov", "m4v"].contains((name as NSString).pathExtension.lowercased())
}

/// The videos among a folder's entries (name to modification date); events that leave it unchanged are ignored.
func videoListing(of entries: [String: Date]) -> [String: Date] {
    entries.filter { isWallpaperVideo(named: $0.key) }
}

// MARK: - Folder change decision

enum FolderChangeAction: Equatable {
    case keepPlaying
    case switchTo(URL)
    /// Show the Poster and rebuild after a short debounce, replacing any backoff timer.
    case rebuildSoon(RecoveryCause)
    case restNoVideo
}

/// What to do when the folder's set of videos changes. `isRecovering` covers a pending rebuild and any rest on
/// the Poster; a video becoming available then rebuilds promptly instead of waiting out the backoff.
func folderChangeAction(newest: URL?, current: URL?, currentExists: Bool, isRecovering: Bool) -> FolderChangeAction {
    guard let newest else { return .restNoVideo }
    if current != nil && !currentExists { return .rebuildSoon(.fileMissing) }
    if isRecovering { return .rebuildSoon(.videoAvailable) }
    return newest == current ? .keepPlaying : .switchTo(newest)
}
