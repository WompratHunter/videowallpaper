import Application
import Library

// MARK: - Library adapters

extension Composition {
    static func library() -> LibraryService {
        LibraryService(
            folder: FileWallpaperFolder(location: AppFiles.wallpaperDirectory, legacyPoster: AppFiles.legacyPoster),
            analyser: AVFoundationAnalyser(),
            store: FileLibraryStore(
                analysisCache: AppFiles.analysisCacheFile, posterDirectory: AppFiles.posterDirectory))
    }
}
