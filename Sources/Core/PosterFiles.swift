import Foundation

// MARK: - Poster storage
// Posters live in Application Support, never in the Wallpaper folder. Each video gets its own name, derived from
// its path, size and modification date, so a replaced file gets a fresh Poster and macOS (which caches desktop
// pictures by URL) never shows a stale one.

private let posterPrefix = "poster-"
private let posterExtension = ".jpg"
private let posterFrameChoice = "mean-luminance"

/// The Poster's file name for a video. FNV-1a, not `Hasher`, because `Hasher` is seeded per process and the
/// name must be the same on every launch. The frame choice is part of the name: Posters exported at 5 s before
/// Analysis chose a representative frame get new names, so macOS shows the new frame instead of its cached image.
func posterFileName(forVideoAt path: String, file: VideoFile) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    let key = "\(path)\u{0}\(file.size)\u{0}\(file.modifiedMilliseconds)\u{0}\(posterFrameChoice)"
    for byte in key.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    let hex = String(hash, radix: 16)
    return posterPrefix + String(repeating: "0", count: 16 - hex.count) + hex + posterExtension
}

func isPosterFileName(_ name: String) -> Bool {
    name.hasPrefix(posterPrefix) && name.hasSuffix(posterExtension)
}

/// Posters in the folder that belong to no current video, so app data doesn't grow with every video ever played.
/// The Current video's Poster is always kept: it is the desktop picture, and an unreadable Wallpaper folder lists no
/// videos at all.
func stalePosters(in names: [String], keeping keep: Set<String>, current: String) -> [String] {
    names.filter { isPosterFileName($0) && !keep.contains($0) && $0 != current }.sorted()
}
