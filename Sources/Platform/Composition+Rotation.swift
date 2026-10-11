import App
import Application

// MARK: - Rotation adapters

extension Composition {
    static func rotation() -> RotationService {
        RotationScheduler(directory: AppFiles.wallpaperDirectory, dwellScale: RotationScheduler.debugDwellScale)
    }
}
