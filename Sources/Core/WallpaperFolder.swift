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
