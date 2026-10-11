// MARK: - Daylight slice
// Daylight's part of the app snapshot: the last Daylight worked out (only while `dynamic` Mode aims at it) and its
// source. Never coordinates.

public struct DaylightSlice: Equatable {
    /// From 0 (night) to 1 (full day); nil until `dynamic` Mode first asks.
    public var level: Double?
    /// Where the level came from: the sun at a fix, the cached fix or the time zone's city, or the appearance.
    public var source: DaylightBasis?

    public init(level: Double? = nil, source: DaylightBasis? = nil) {
        self.level = level
        self.source = source
    }

    /// The place in the Rotation's dark-to-bright ranking the next pick aims for: Daylight itself.
    public var targetBrightness: Double? { level }
}
