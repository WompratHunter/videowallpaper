import Foundation

// MARK: - Desktop ports
// What Desktop needs of the system: the desktop picture per screen (`WorkspaceDesktopPictures` today, `NSWorkspace`)
// and somewhere to keep the record of the user's own pictures (`FileOriginalsStore`, a file in Application Support).
// Tests use in-memory fakes of both.

/// The system desktop picture, per screen.
public protocol DesktopPicturePort: AnyObject {
    /// Every connected screen's stable identifier, in the system's order.
    var screens: [String] { get }
    /// The main screen's current picture.
    var mainScreenPicture: URL? { get }
    /// The screen's current picture with its options, nil when it has none to read.
    func picture(on screen: String) -> DesktopPicture?
    /// Throws when the system refuses; the error's description is logged.
    func setPicture(_ file: URL, options: DesktopPictureOptions, on screen: String) throws
    /// Whether a picture file still exists, so a deleted original is never restored.
    func fileExists(atPath path: String) -> Bool
}

/// The record of the user's own pictures, as the bytes `OriginalPictures` encodes.
public protocol OriginalsStore: AnyObject {
    /// Where the record lives, named in the log when it can't be decoded.
    var location: String { get }
    /// Whether a record exists, readable or not.
    var exists: Bool { get }
    /// Nil when there is no record or it can't be read.
    func read() -> Data?
    func write(_ data: Data) throws
}
