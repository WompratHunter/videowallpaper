import AVFoundation

// MARK: - Player state for logs and health checks
// Maps AV state to the plain strings of PlayerStateReport, so the Core report stays free of AVFoundation.

extension AVQueuePlayer {
    func hasFailed(looper: AVPlayerLooper?) -> Bool {
        status == .failed || currentItem?.status == .failed || looper?.status == .failed
    }

    func stateReport(looper: AVPlayerLooper?, timeAdvanced: Bool?) -> PlayerStateReport {
        let item = currentItem
        return PlayerStateReport(
            playerStatus: name(of: status),
            itemStatus: item.map { name(of: $0.status) } ?? "none",
            itemError: (item?.error ?? error ?? looper?.error).map(describe),
            timeControl: name(of: timeControlStatus),
            waitingReason: reasonForWaitingToPlay?.rawValue,
            timeAdvanced: timeAdvanced)
    }
}

// MARK: - AV state names

private func name(of status: AVPlayer.Status) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

private func name(of status: AVPlayerItem.Status) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

private func name(of status: AVPlayer.TimeControlStatus) -> String {
    switch status {
    case .paused: return "paused"
    case .waitingToPlayAtSpecifiedRate: return "waitingToPlayAtSpecifiedRate"
    case .playing: return "playing"
    @unknown default: return "rawValue\(status.rawValue)"
    }
}

func describe(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
}
