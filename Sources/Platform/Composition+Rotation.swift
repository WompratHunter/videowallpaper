import Application
import Foundation
import Rotation

// MARK: - Rotation adapters
// The Rotation is pure apart from the auto-appearance flag, which it reads through its port.

extension Composition {
    static func rotation() -> RotationService {
        RotationService(
            directory: AppFiles.wallpaperDirectory, dwellScale: debugDwellScale, appearance: GlobalAutoAppearance())
    }

    /// A manual test's shortened Dwell: `VIDEOWALLPAPER_DWELL_SCALE` (e.g. 0.01 makes 20 min 12 s), honoured only by
    /// a `make debug` build, so the installed app can't be affected.
    private static var debugDwellScale: Double {
        #if DEBUG
        let scale = ProcessInfo.processInfo.environment["VIDEOWALLPAPER_DWELL_SCALE"].flatMap(Double.init)
        return scale.map { max($0, 0.001) } ?? 1
        #else
        return 1
        #endif
    }
}

// MARK: - Auto-appearance

/// The global `AppleInterfaceStyleSwitchesAutomatically` flag, read only. It is undocumented: absent reads as off, so
/// the default Mode falls back to `all`.
final class GlobalAutoAppearance: AutoAppearancePort {
    var isAutoAppearance: Bool {
        UserDefaults.standard.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically")
    }
}
