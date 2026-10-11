import Foundation

// MARK: - Video identity
// The only video types every context agrees on (see CONTEXT.md). A Video is its file name: renaming a file makes a
// new Video. A Version is one content of it, told apart by size and modification time, so replacing a file under the
// same name gives the Video a new Version. Analysis and Posters are keyed by Version; Pass history, the new-video
// queue and FlashOverride by Video.

public struct VideoID: Hashable, Comparable, CustomStringConvertible {
    public let fileName: String

    public init(_ fileName: String) {
        self.fileName = fileName
    }

    public var description: String { fileName }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.fileName < rhs.fileName }
}

public struct Version: Hashable {
    public let size: Int64
    /// Whole milliseconds, so a date read back from disk or JSON compares equal to the original.
    public let modifiedMilliseconds: Int64

    public init(size: Int64, modifiedMilliseconds: Int64) {
        self.size = size
        self.modifiedMilliseconds = modifiedMilliseconds
    }

    public init(size: Int64, modified: Date) {
        self.init(size: size, modifiedMilliseconds: Int64((modified.timeIntervalSince1970 * 1000).rounded()))
    }

    public var modified: Date { Date(timeIntervalSince1970: Double(modifiedMilliseconds) / 1000) }
}

/// A Video the Rotation may play: analysed and not Excluded. All Rotation ever sees of the Library: never flash rates
/// or files.
public struct EligibleVideo: Equatable {
    public let id: VideoID
    public let version: Version
    public let meanLuminance: Double

    public init(id: VideoID, version: Version, meanLuminance: Double) {
        self.id = id
        self.version = version
        self.meanLuminance = meanLuminance
    }

    /// The file name, the Video's identity.
    public var name: String { id.fileName }
    /// When this Version was written; newly added Videos queue newest first.
    public var modified: Date { version.modified }
}
