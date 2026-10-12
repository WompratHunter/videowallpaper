import Foundation

// MARK: - Player state report
// Plain-string snapshot of a player's health, so the wake/unlock log line can be formatted and tested without
// AVFoundation. The player adapter maps AV enums to their case names before building one.

public struct PlayerStateReport: CustomStringConvertible, Equatable, Sendable {
    public static let noPlayer = Self(
        playerStatus: nil, itemStatus: "none", itemError: nil,
        timeControl: "none", waitingReason: nil, timeAdvanced: nil)

    public let playerStatus: String?
    public let itemStatus: String
    public let itemError: String?
    public let timeControl: String
    public let waitingReason: String?
    public let timeAdvanced: Bool?

    public init(
        playerStatus: String?,
        itemStatus: String,
        itemError: String?,
        timeControl: String,
        waitingReason: String?,
        timeAdvanced: Bool?
    ) {
        self.playerStatus = playerStatus
        self.itemStatus = itemStatus
        self.itemError = itemError
        self.timeControl = timeControl
        self.waitingReason = waitingReason
        self.timeAdvanced = timeAdvanced
    }

    public var description: String {
        guard let playerStatus else { return "player=none" }
        let error = itemError.map { "\"\($0)\"" } ?? "none"
        let advanced = timeAdvanced.map { $0 ? "yes" : "no" } ?? "unknown"
        return "player=\(playerStatus) item=\(itemStatus) error=\(error) "
            + "timeControl=\(timeControl) waiting=\(waitingReason ?? "none") advanced=\(advanced)"
    }
}

/// Whether playback moved between two samples of the current time, in seconds.
/// Any change counts, because the looper wraps back to the start; nil when either sample is unavailable.
func playbackAdvanced(from earlier: Double?, to later: Double?) -> Bool? {
    guard let earlier, let later, earlier.isFinite, later.isFinite else { return nil }
    return later != earlier
}
