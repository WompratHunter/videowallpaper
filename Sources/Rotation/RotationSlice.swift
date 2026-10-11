import SharedKernel

// MARK: - Rotation slice
// The Rotation's part of the app snapshot. Ticket 08 adds each Video's Rotation status, Dwell and the last switch.

public struct RotationSlice: Equatable {
    /// The video the Live wallpaper is showing (or will, once Low Power Mode ends).
    public var current: VideoID?

    public init(current: VideoID? = nil) {
        self.current = current
    }
}
