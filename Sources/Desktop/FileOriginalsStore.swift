import Foundation

// MARK: - Originals file
// The record of the user's own pictures as a JSON file; Platform names the file.

public final class FileOriginalsStore: OriginalsStore {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public var location: String { file.path }

    public var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    public func read() -> Data? {
        try? Data(contentsOf: file)
    }

    public func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
