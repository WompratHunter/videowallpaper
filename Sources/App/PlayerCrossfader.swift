import AVFoundation

// MARK: - Crossfade
// The second player of a crossfade: it loads the incoming video beside the Player's one, fades its layers in once
// they are ready for display, then hands it to the Player, which releases the outgoing one. Decisions (what a pause,
// tear-down, failure or timeout means for a fade) come from Core's Crossfade; this only applies them.

/// A looping, muted player for one video, as the Player's own is built.
struct LoopingPlayer {
    let url: URL
    let player: AVQueuePlayer
    let looper: AVPlayerLooper

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.url = url
        self.player = player
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    func release() {
        looper.disableLooping()
        player.pause()
        player.removeAllItems()
    }
}

final class PlayerCrossfader {
    /// Replace the Player's video at once.
    var onCut: (URL) -> Void = { _ in }
    /// The incoming player is now on the active layers; the Player adopts it and releases its own.
    var onPromote: (LoopingPlayer) -> Void = { _ in }

    private let layers: PlayerLayers
    private var state = Crossfade()
    private var incoming: (id: Int, video: LoopingPlayer)?
    private var observations: [NSKeyValueObservation] = []

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(layers: PlayerLayers) {
        self.layers = layers
        layers.onIncomingReady = { [weak self] in
            guard let self, let id = self.incoming?.id else { return }
            self.apply(self.state.incomingReady(id: id, now: self.now))
        }
    }

    func request(_ url: URL, duration: TimeInterval, current: URL?, isPlaying: Bool) {
        apply(state.request(url, duration: duration, current: current, isPlaying: isPlaying, now: now))
    }

    /// The Player paused (occluded, screens asleep): the fade completes at once.
    func pause() { apply(state.pause()) }

    /// The Player is tearing down its own player: the incoming one goes too.
    func interrupt() { apply(state.interrupt()) }

    /// On the shared tick, so a video that never becomes ready, or a fade that never finishes, is not left running.
    func tick() { apply(state.tick(now: now)) }

    private func apply(_ actions: [CrossfadeAction]) {
        for action in actions {
            switch action {
            case .cut(let url):
                log("cut video=\(url.lastPathComponent)")
                dropIncoming()
                onCut(url)
            case let .load(id, url):
                load(url, id: id)
            case let .animate(id, duration):
                animate(id: id, duration: duration)
            case .promote(let url):
                promote(url)
            case .dropIncoming:
                log("dropped incoming video=\(incomingName)")
                dropIncoming()
            case .abandon(let url):
                log("abandoned video=\(url.lastPathComponent): failed or not ready; keeping the Current video")
                dropIncoming()
            }
        }
    }
}

// MARK: - Incoming player

extension PlayerCrossfader {
    private func load(_ url: URL, id: Int) {
        let video = LoopingPlayer(url: url)
        incoming = (id, video)
        log("loading video=\(url.lastPathComponent)")
        observations = [
            video.player.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
                guard player.currentItem?.status == .failed else { return }
                DispatchQueue.main.async { self?.failed(id: id) }
            },
            video.looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
                guard looper.status == .failed else { return }
                DispatchQueue.main.async { self?.failed(id: id) }
            }
        ]
        // Playing while hidden, so the first visible frame is already moving.
        video.player.play()
        layers.attachIncoming(video.player)
    }

    private func animate(id: Int, duration: TimeInterval) {
        log("fading video=\(incomingName) over=\(Int(duration))s")
        layers.fadeInIncoming(duration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.apply(self.state.animationFinished(id: id))
        }
    }

    private func promote(_ url: URL) {
        guard let video = incoming?.video, video.url == url else {
            // Core only promotes the video it loaded; anything else is a broken invariant.
            Log.write("crossfade", "promote without incoming video=\(url.lastPathComponent); cutting")
            dropIncoming()
            onCut(url)
            return
        }
        stopObserving()
        incoming = nil
        layers.promoteIncoming()
        log("done video=\(url.lastPathComponent)")
        onPromote(video)
    }

    private func failed(id: Int) { apply(state.incomingFailed(id: id)) }

    private var incomingName: String { incoming?.video.url.lastPathComponent ?? "none" }

    private func dropIncoming() {
        stopObserving()
        incoming?.video.release()
        incoming = nil
        layers.dropIncoming()
    }

    private func stopObserving() {
        observations.forEach { $0.invalidate() }
        observations = []
    }

    private func log(_ message: String) { Log.write("crossfade", message) }
}
