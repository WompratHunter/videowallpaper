import Foundation

// MARK: - Desktop pictures
// Recording and restoring the user's own desktop picture per screen, so uninstall leaves the system as it was.

struct DesktopPictureOptions: Codable, Equatable {
    /// `NSImageScaling` raw value.
    var scaling: UInt?
    var allowsClipping: Bool?
    /// sRGB red, green, blue, alpha.
    var fillColor: [Double]?
}

struct DesktopPicture: Codable, Equatable {
    let path: String
    let options: DesktopPictureOptions
}

/// The pictures this app sets: Posters in Application Support and the legacy hidden Poster in the Wallpaper folder.
struct OwnPictures {
    let posterDirectory: String
    let legacyPoster: String

    func contains(_ path: String) -> Bool {
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
