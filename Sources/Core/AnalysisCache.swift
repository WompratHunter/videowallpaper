import Foundation

// MARK: - Analysis cache
// Each video is analysed once. The result is kept in Application Support, keyed by the video's path, size and
// modification date, so a replaced file is analysed again; entries for videos no longer in the folder are pruned.

/// A video's Analysis: its measurements plus the Poster saved from it.
struct Analysis: Codable, Equatable {
    let meanLuminance: Double
    let flashesPerSecond: Int
    let posterSeconds: Double
    /// The Poster's file name in the app's Poster folder.
    let poster: String
}

struct AnalysisCache: Equatable {
    /// Bumped when the stored fields or their meaning change; an index in another version is discarded.
    private static let version = 1

    private struct Entry: Codable, Equatable {
        let size: Int64
        let modifiedMilliseconds: Int64
        let analysis: Analysis

        func matches(_ file: VideoFile) -> Bool {
            size == file.size && modifiedMilliseconds == file.modifiedMilliseconds
        }
    }

    private struct Index: Codable {
        let version: Int
        let videos: [String: Entry]
    }

    /// Keyed by the video's path.
    private var entries: [String: Entry] = [:]

    init() {}

    /// Nil when the data is unreadable or from another version; the caller starts empty and re-analyses.
    init?(json: Data) {
        guard let index = try? JSONDecoder().decode(Index.self, from: json), index.version == Self.version
        else { return nil }
        entries = index.videos
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Index(version: Self.version, videos: entries))
    }

    /// The cached Analysis, only when the file is unchanged since it was analysed.
    func analysis(forVideoAt path: String, file: VideoFile) -> Analysis? {
        guard let entry = entries[path], entry.matches(file) else { return nil }
        return entry.analysis
    }

    mutating func store(_ analysis: Analysis, forVideoAt path: String, file: VideoFile) {
        entries[path] = Entry(size: file.size, modifiedMilliseconds: file.modifiedMilliseconds, analysis: analysis)
    }

    /// Keeps only entries for videos still present (path to file) and unchanged. Returns true when any was removed.
    mutating func prune(present: [String: VideoFile]) -> Bool {
        let before = entries.count
        entries = entries.filter { path, entry in present[path].map { entry.matches($0) } ?? false }
        return entries.count != before
    }
}

// MARK: - Eligible videos

/// A video the Rotation may play: analysed, and not Excluded for flashing.
struct EligibleVideo: Equatable {
    let name: String
    let modified: Date
    let meanLuminance: Double
}

/// The settled videos (name to modification date) whose Analysis is known and whose flash verdict allows playing,
/// sorted by name. A video not yet analysed is not eligible: it has not been screened.
func screenEligible(
    settled: [String: Date], analyses: [String: Analysis], overrides: [String]
) -> [EligibleVideo] {
    settled.compactMap { name, modified -> EligibleVideo? in
        guard let analysis = analyses[name],
              flashVerdict(flashesPerSecond: analysis.flashesPerSecond, fileName: name, overrides: overrides).isPlayable
        else { return nil }
        return EligibleVideo(name: name, modified: modified, meanLuminance: analysis.meanLuminance)
    }
    .sorted { $0.name < $1.name }
}

/// Settled videos still waiting for Analysis, newest first so the video most likely to play is ready soonest.
func videosToAnalyse(settled: [String: Date], analysed: Set<String>) -> [String] {
    settled.filter { !analysed.contains($0.key) }
        .sorted { ($0.value, $0.key) > ($1.value, $1.key) }
        .map(\.key)
}
