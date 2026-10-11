import AppKit

// MARK: - System window list
// The window-list port's adapter: `CGWindowListCopyWindowInfo` bounds, layer and alpha, which need no Screen Recording
// permission, and every display's bounds. Window-list bounds and display bounds share the global top-left-origin
// space, so no flipping is needed.

@MainActor
public final class SystemWindowList: WindowListPort {
    public init() {}

    public func windows() -> [ListedWindow]? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        return info.compactMap(Self.listedWindow)
    }

    public func screens() -> [ScreenRect] {
        NSScreen.screens.compactMap { screen -> ScreenRect? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return Self.rect(CGDisplayBounds(CGDirectDisplayID(id.uint32Value)))
        }
    }

    private static func listedWindow(_ entry: [String: Any]) -> ListedWindow? {
        guard let layer = entry[kCGWindowLayer as String] as? Int,
              let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
        let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
        return ListedWindow(layer: layer, alpha: alpha, bounds: rect(bounds))
    }

    private static func rect(_ cg: CGRect) -> ScreenRect {
        ScreenRect(minX: Double(cg.minX), minY: Double(cg.minY), width: Double(cg.width), height: Double(cg.height))
    }
}
