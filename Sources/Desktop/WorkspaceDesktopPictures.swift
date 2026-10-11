import AppKit

// MARK: - Desktop pictures per screen
// NSWorkspace reads and sets the picture of the current Space only; other Spaces keep whatever they had.

public final class WorkspaceDesktopPictures: DesktopPicturePort {
    public init() {}

    public var screens: [String] {
        NSScreen.screens.map(Self.key(for:))
    }

    public var mainScreenPicture: URL? {
        NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    public func picture(on screen: String) -> DesktopPicture? {
        guard let screen = Self.screen(screen), let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }
        // Resolved like the app's own paths, so a symlinked home still matches its Posters.
        let raw = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        return DesktopPicture(path: url.resolvingSymlinksInPath().path, options: Self.options(from: raw))
    }

    public func setPicture(_ file: URL, options: DesktopPictureOptions, on screen: String) throws {
        guard let screen = Self.screen(screen) else { return }
        try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: Self.workspaceOptions(from: options))
    }

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private static func screen(_ key: String) -> NSScreen? {
        NSScreen.screens.first { Self.key(for: $0) == key }
    }

    /// The display's UUID survives reboots and reconnection, unlike the numeric display ID.
    private static func key(for screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = CGDirectDisplayID(number?.uint32Value ?? 0)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid)
        else { return "display-\(displayID)" }
        return text as String
    }

    // MARK: - Option conversion

    private static func options(from raw: [NSWorkspace.DesktopImageOptionKey: Any]) -> DesktopPictureOptions {
        let color = (raw[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
        return DesktopPictureOptions(
            scaling: (raw[.imageScaling] as? NSNumber)?.uintValue,
            allowsClipping: (raw[.allowClipping] as? NSNumber)?.boolValue,
            fillColor: color.map {
                [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent].map(Double.init)
            })
    }

    private static func workspaceOptions(
        from options: DesktopPictureOptions
    ) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var raw: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = options.scaling { raw[.imageScaling] = NSNumber(value: scaling) }
        if let clipping = options.allowsClipping { raw[.allowClipping] = NSNumber(value: clipping) }
        if let rgba = options.fillColor, rgba.count == 4 {
            raw[.fillColor] = NSColor(
                srgbRed: CGFloat(rgba[0]), green: CGFloat(rgba[1]), blue: CGFloat(rgba[2]), alpha: CGFloat(rgba[3]))
        }
        return raw
    }
}
