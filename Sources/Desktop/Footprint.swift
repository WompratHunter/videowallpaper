import Foundation

// MARK: - Footprint
// Recording and restoring the user's own desktop picture per screen, so uninstall leaves the system as it was. The
// decisions are pure; `DesktopService` gathers their inputs from the ports and applies the result.

public struct DesktopPictureOptions: Codable, Equatable, Sendable {
    /// `NSImageScaling` raw value.
    public var scaling: UInt?
    public var allowsClipping: Bool?
    /// sRGB red, green, blue, alpha.
    public var fillColor: [Double]?

    public init(scaling: UInt? = nil, allowsClipping: Bool? = nil, fillColor: [Double]? = nil) {
        self.scaling = scaling
        self.allowsClipping = allowsClipping
        self.fillColor = fillColor
    }
}

public struct DesktopPicture: Codable, Equatable, Sendable {
    public let path: String
    public let options: DesktopPictureOptions

    public init(path: String, options: DesktopPictureOptions) {
        self.path = path
        self.options = options
    }
}

/// The pictures this app sets: Posters in Application Support and the legacy hidden Poster in the Wallpaper folder.
public struct OwnPictures: Sendable {
    public let posterDirectory: String
    public let legacyPoster: String

    public init(posterDirectory: String, legacyPoster: String) {
        self.posterDirectory = posterDirectory
        self.legacyPoster = legacyPoster
    }

    public func contains(_ path: String) -> Bool {
        let path = (path as NSString).standardizingPath
        let directory = (posterDirectory as NSString).standardizingPath
        return path == (legacyPoster as NSString).standardizingPath || path.hasPrefix(directory + "/")
    }
}

/// The user's desktop picture per screen before this app first changed it, keyed by a stable screen identifier.
struct OriginalPictures: Codable, Equatable {
    var screens: [String: DesktopPicture]

    init(screens: [String: DesktopPicture]) {
        self.screens = screens
    }

    init?(json: Data) {
        guard let decoded = try? JSONDecoder().decode(Self.self, from: json) else { return nil }
        self = decoded
    }

    func json() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(self)
        } catch {
            fatalError("encoding plain strings, numbers and arrays cannot fail: \(error)")
        }
    }
}

/// What to save before setting a Poster, or nil when the record is unchanged. Recorded entries are never
/// overwritten, so later runs (when the screens show the Poster) keep the true original. A screen not yet recorded
/// is added unless it already shows our Poster, because then its original is unknown.
func originalsToRecord(
    existing: OriginalPictures?, current: [String: DesktopPicture], ownPictures own: OwnPictures
) -> OriginalPictures? {
    var record = existing ?? OriginalPictures(screens: [:])
    for (screen, picture) in current where record.screens[screen] == nil && !own.contains(picture.path) {
        record.screens[screen] = picture
    }
    guard !record.screens.isEmpty, record != existing else { return nil }
    return record
}

/// The picture to set per screen to undo this app. Only screens showing our Poster are touched: a picture the user
/// chose since install stays. A screen with no usable record falls back to another screen's original, then to the
/// system default picture.
func restorePlan(
    originals: OriginalPictures?,
    current: [String: DesktopPicture],
    ownPictures own: OwnPictures,
    fallback: DesktopPicture?,
    fileExists: (String) -> Bool
) -> [String: DesktopPicture] {
    let usable = (originals?.screens ?? [:]).filter { fileExists($0.value.path) }
    let anyOriginal = usable.min { $0.key < $1.key }?.value
    let fallback = fallback.flatMap { fileExists($0.path) ? $0 : nil }
    var plan: [String: DesktopPicture] = [:]
    for (screen, picture) in current where own.contains(picture.path) {
        plan[screen] = usable[screen] ?? anyOriginal ?? fallback
    }
    return plan
}
