import App
import Application

// MARK: - Daylight adapters

extension Composition {
    static func daylight() -> DaylightService {
        DaylightLocation(cacheFile: AppFiles.locationCacheFile)
    }
}
