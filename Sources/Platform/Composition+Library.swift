import App
import Application

// MARK: - Library adapters

extension Composition {
    static func library() -> LibraryService {
        Library(
            directory: AppFiles.wallpaperDirectory, analysisCache: AppFiles.analysisCacheFile,
            posterDirectory: AppFiles.posterDirectory, legacyPoster: AppFiles.legacyPoster)
    }
}
