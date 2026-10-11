import Desktop
import Foundation

// MARK: - Where the app keeps its files
// Everything the app writes lives under Application Support; the Wallpaper folder holds only the user's videos. Only
// Platform knows these paths: each module is handed the ones it uses when it is built.

enum AppFiles {
    static let wallpaperDirectory = debugFolder
        ?? URL(fileURLWithPath: NSString("~/Movies/LiveWallpaper").expandingTildeInPath)
    /// A debug run on its own folder keeps its cache and Posters beside it, so it can't prune the installed app's.
    static let supportDirectory = debugFolder.map {
        $0.deletingLastPathComponent().appendingPathComponent("\($0.lastPathComponent)-support", isDirectory: true)
    } ?? FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VideoWallpaper", isDirectory: true)
    static let posterDirectory = supportDirectory.appendingPathComponent("posters", isDirectory: true)
    static let analysisCacheFile = supportDirectory.appendingPathComponent("analysis-cache.json")
    static let originalsFile = supportDirectory.appendingPathComponent("original-desktop-pictures.json")
    static let locationCacheFile = supportDirectory.appendingPathComponent("location.json")
    /// Written into the Wallpaper folder by versions before Posters moved to Application Support.
    static let legacyPoster = wallpaperDirectory.appendingPathComponent(".poster.jpg")
    static let defaultDesktopPicture = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
    /// The LaunchAgent `make install` writes; Set Launch at login writes or removes it.
    static let launchAgentFile = URL(
        fileURLWithPath: NSString("~/Library/LaunchAgents/com.videowallpaper.plist").expandingTildeInPath)

    static let ownPictures = OwnPictures(
        posterDirectory: posterDirectory.resolvingSymlinksInPath().path,
        legacyPoster: legacyPoster.resolvingSymlinksInPath().path)

    /// A manual test's Wallpaper folder, `VIDEOWALLPAPER_FOLDER`, honoured only by a `make debug` build.
    private static var debugFolder: URL? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["VIDEOWALLPAPER_FOLDER"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        #else
        return nil
        #endif
    }
}
