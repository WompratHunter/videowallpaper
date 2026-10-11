import SharedKernel

// MARK: - Library slice
// The Library's part of the app snapshot. Ticket 06 adds the Video catalogue (every Video with its Version and
// catalogue status).

public struct LibrarySlice: Equatable {
    /// The Videos the Rotation may play, as of the last settle check or Analysis.
    public var eligible: [EligibleVideo]

    public init(eligible: [EligibleVideo] = []) {
        self.eligible = eligible
    }
}
