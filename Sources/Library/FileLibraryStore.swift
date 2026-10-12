import AppKit

// MARK: - Library store adapter
// Today's store: the Analysis cache as JSON and one JPEG Poster per Version, both in Application Support (Platform
// hands in the paths), never in the Wallpaper folder.

public final class FileLibraryStore: LibraryStore {
    private let analysisCache: URL
    private let posterDirectory: URL

    public init(analysisCache: URL, posterDirectory: URL) {
        self.analysisCache = analysisCache
        self.posterDirectory = posterDirectory
    }

    public func loadAnalysisCache() -> Data? {
        try? Data(contentsOf: analysisCache)
    }

    public func saveAnalysisCache(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: analysisCache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: analysisCache, options: .atomic)
    }

    public func posterNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: posterDirectory.path)) ?? []
    }

    public func posterFile(named name: String) -> URL {
        posterDirectory.appendingPathComponent(name)
    }

    public func savePoster(_ image: CGImage, named name: String) throws {
        let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        guard let data else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: posterDirectory, withIntermediateDirectories: true)
        try data.write(to: posterFile(named: name), options: .atomic)
    }

    public func removePoster(named name: String) {
        try? FileManager.default.removeItem(at: posterFile(named: name))
    }

    public func loadImage(at file: URL) -> CGImage? {
        NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
