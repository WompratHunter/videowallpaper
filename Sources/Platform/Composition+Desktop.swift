import App
import Application

// MARK: - Desktop adapters

extension Composition {
    /// Also used on its own by `--restore-wallpaper`.
    nonisolated static func desktop() -> DesktopPictures {
        DesktopPictures(
            originalsFile: AppFiles.originalsFile, ownPictures: AppFiles.ownPictures,
            defaultPicture: AppFiles.defaultDesktopPicture)
    }
}
