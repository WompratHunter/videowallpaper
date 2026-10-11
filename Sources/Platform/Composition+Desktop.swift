import Application
import Desktop

// MARK: - Desktop adapters

extension Composition {
    /// Also used on its own by `--restore-wallpaper`.
    static func desktop() -> DesktopService {
        DesktopService(
            pictures: WorkspaceDesktopPictures(),
            originals: FileOriginalsStore(file: AppFiles.originalsFile),
            ownPictures: AppFiles.ownPictures,
            defaultPicture: AppFiles.defaultDesktopPicture)
    }

    /// The `--restore-wallpaper` command, run by `make uninstall` without the app: its lines go through the same log
    /// sink. Exit status 0 when every screen showing a Poster got its picture back (or none shows one), else 1.
    static func restoreWallpaper() -> Int32 {
        let desktop = desktop()
        desktop.onEvent = { StderrLogSink.write(.desktop($0)) }
        return desktop.restoreOriginals() ? 0 : 1
    }
}
