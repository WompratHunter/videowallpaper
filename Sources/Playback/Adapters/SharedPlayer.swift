import AVFoundation
import QuartzCore
import SharedKernel

// MARK: - Shared player
// The player port's adapter. One decoder feeds every display: each window hosts AVPlayerLayers bound to the same queue
// player, above a Poster layer that shares one decoded image, so tearing the player down reveals the Poster, never
// black. During a crossfade a second, incoming queue player fades in above it. KVO and notifications are hopped to the
// main queue before they are reported.

@MainActor
package final class SharedPlayer: PlayerPort {
    package var onSignal: (PlayerSignal) -> Void = { _ in }

    private var current: LoopingPlayer?
    private var observations: [NSKeyValueObservation] = []
    private var incoming: (id: Int, video: LoopingPlayer)?
    private var incomingObservations: [NSKeyValueObservation] = []
    private var failureObserver: NSObjectProtocol?
    private let layers = PlayerLayers()

    package init() {
        layers.onIncomingReady = { [weak self] in
            guard let self, let id = self.incoming?.id else { return }
            self.onSignal(.incomingReady(id: id))
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let item = note.object as? AVPlayerItem
            let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error).map(describe)
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                guard let self, let item, self.current?.player.items().contains(item) == true else { return }
                self.onSignal(.failed(.playToEnd(error: error)))
            }
        }
    }

    deinit {
        failureObserver.map(NotificationCenter.default.removeObserver)
    }

    /// A Poster layer with the video layers above it, sized to `frame`; the caller's window only hosts it.
    package func makeLayers(frame: CGRect) -> CALayer { layers.make(frame: frame) }

    package func setPoster(_ poster: PosterImage) { layers.setPoster(poster.image) }

    // MARK: - Current player

    package var hasCurrent: Bool { current != nil }

    package var position: Double? {
        guard let time = current?.player.currentTime(), time.isNumeric else { return nil }
        return time.seconds
    }

    package var hasFailed: Bool { current.map { $0.player.hasFailed(looper: $0.looper) } ?? false }

    package func stateReport(timeAdvanced: Bool?) -> PlayerStateReport {
        guard let current else { return .noPlayer }
        return current.player.stateReport(looper: current.looper, timeAdvanced: timeAdvanced)
    }

    package func loadCurrent(_ video: URL) {
        releasePlayer()
        let built = LoopingPlayer(url: video)
        current = built
        observe(built)
        layers.attach(built.player)
    }

    package func releaseCurrent() {
        releasePlayer()
        layers.attach(nil)
    }

    package func play() { current?.player.play() }

    package func pause() { current?.player.pause() }

    package func seek(to seconds: Double, then: @escaping () -> Void) {
        guard let player = current?.player else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self, weak player] _ in
            DispatchQueue.main.async {
                guard let self, let player, player === self.current?.player else { return }
                then()
            }
        }
    }

    private func releasePlayer() {
        observations.forEach { $0.invalidate() }
        observations = []
        current?.release()
        current = nil
    }

    private func observe(_ video: LoopingPlayer) {
        let itemStatus = video.player.observe(\.currentItem?.status, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.itemStatusChanged() }
        }
        let looperStatus = video.looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
            guard looper.status == .failed else { return }
            DispatchQueue.main.async { self?.onSignal(.failed(.looper)) }
        }
        observations = [itemStatus, looperStatus]
    }

    private func itemStatusChanged() {
        guard let item = current?.player.currentItem else { return }
        switch item.status {
        case .failed: onSignal(.failed(.item))
        case .readyToPlay: onSignal(.ready)
        default: break
        }
    }
}

// MARK: - Incoming player

extension SharedPlayer {
    package func loadIncoming(_ video: URL, id: Int) {
        let player = LoopingPlayer(url: video)
        incoming = (id, player)
        incomingObservations = [
            player.player.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
                guard player.currentItem?.status == .failed else { return }
                DispatchQueue.main.async { self?.onSignal(.incomingFailed(id: id)) }
            },
            player.looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
                guard looper.status == .failed else { return }
                DispatchQueue.main.async { self?.onSignal(.incomingFailed(id: id)) }
            }
        ]
        // Playing while hidden, so the first visible frame is already moving.
        player.player.play()
        layers.attachIncoming(player.player)
    }

    package func fadeInIncoming(duration: TimeInterval) {
        layers.fadeInIncoming(duration: duration)
    }

    package func promoteIncoming() {
        guard let video = incoming?.video else { return }
        stopObservingIncoming()
        incoming = nil
        layers.promoteIncoming()
        releasePlayer()
        current = video
        observe(video)
    }

    package func dropIncoming() {
        stopObservingIncoming()
        incoming?.video.release()
        incoming = nil
        layers.dropIncoming()
    }

    private func stopObservingIncoming() {
        incomingObservations.forEach { $0.invalidate() }
        incomingObservations = []
    }
}
