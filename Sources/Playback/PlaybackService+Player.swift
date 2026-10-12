import Foundation

// MARK: - Showing a video
// Building, replacing and dropping the current player, and what the player reports. The crossfade's second player
// loads beside the current one, fades in once it is ready for display, then replaces it; every way a fade can end is
// decided by `Crossfade`, so the player is never left with an orphaned second player.

extension PlaybackService {
    /// Replaces the current player with one for `url`, resuming at `seconds`.
    func show(_ url: URL, at seconds: Double = 0) {
        cancelPendingRebuild()
        isRestingWithoutVideo = false
        tearDown()
        let changed = url != video
        video = url
        savedSeconds = seconds
        pendingSeek = seconds > 0 ? seconds : nil
        player.loadCurrent(url)
        currentToken = nextToken()
        monitor.noteRebuild(at: now)
        if gate.isIntendingToPlay && pendingSeek == nil { player.play() }
        if changed { videoChanged(to: url) }
    }

    /// Drops both players: the Poster shows.
    func tearDown() {
        apply(crossfade.interrupt())
        releaseCurrent()
    }

    private func releaseCurrent() {
        player.releaseCurrent()
        currentToken = nil
        pendingSeek = nil
    }

    /// The crossfade finished: the incoming player, already on the active layers, replaced the outgoing one.
    private func adopt(_ url: URL) {
        let changed = url != video
        video = url
        savedSeconds = 0
        pendingSeek = nil
        currentToken = nextToken()
        monitor.noteRebuild(at: now)
        if !gate.isIntendingToPlay { player.pause() }
        if changed { videoChanged(to: url) }
    }

    private func videoChanged(to url: URL) {
        onEvent(.videoShown(videoID(url)))
        onVideoChange(url)
    }

    private func nextToken() -> Int {
        lastToken += 1
        return lastToken
    }

    // MARK: - Player signals

    func handle(_ signal: PlayerSignal) {
        switch signal {
        case .ready:
            seekIfPending()
        case .failed(let failure):
            recover(cause: .failed, detail: detail(of: failure))
        case .incomingReady(let id):
            apply(crossfade.incomingReady(id: id, now: now))
        case .incomingFailed(let id):
            apply(crossfade.incomingFailed(id: id))
        }
    }

    /// Seeks before playing, so a rebuilt player resumes where the old one stopped, not at 0.
    private func seekIfPending() {
        guard let seconds = pendingSeek else { return }
        let token = currentToken
        player.seek(to: seconds) { [weak self] in
            guard let self, self.currentToken == token else { return }
            self.pendingSeek = nil
            if self.gate.isIntendingToPlay { self.player.play() }
        }
    }

    private func detail(of failure: PlayerFailure) -> String {
        switch failure {
        case .item: return "item failed \(stateReport(sinceSeconds: nil))"
        case .looper: return "looper failed \(stateReport(sinceSeconds: nil))"
        case .playToEnd(let error): return "failed-to-play-to-end \(error ?? "")"
        }
    }

    // MARK: - Crossfade

    func apply(_ actions: [CrossfadeAction]) {
        for action in actions {
            switch action {
            case .cut(let url):
                onEvent(.crossfade(.cut(videoID(url))))
                dropIncoming()
                show(url)
            case let .load(id, url):
                incoming = (id, url)
                onEvent(.crossfade(.loading(videoID(url))))
                player.loadIncoming(url, id: id)
            case let .animate(id, duration):
                animate(id: id, duration: duration)
            case .promote(let url):
                promote(url)
            case .dropIncoming:
                onEvent(.crossfade(.droppedIncoming(incoming.map { videoID($0.video) })))
                dropIncoming()
            case .abandon(let url):
                onEvent(.crossfade(.abandoned(videoID(url))))
                dropIncoming()
            }
        }
    }

    private func animate(id: Int, duration: TimeInterval) {
        onEvent(.crossfade(.fading(incoming.map { videoID($0.video) }, duration: duration)))
        player.fadeInIncoming(duration: duration)
        _ = clock.schedule(after: duration) { [weak self] in
            guard let self else { return }
            self.apply(self.crossfade.animationFinished(id: id))
        }
    }

    private func promote(_ url: URL) {
        guard incoming?.video == url else {
            // The domain only promotes the video it loaded; anything else is a broken invariant.
            onEvent(.crossfade(.promotedWithoutIncoming(videoID(url))))
            dropIncoming()
            show(url)
            return
        }
        incoming = nil
        player.promoteIncoming()
        onEvent(.crossfade(.done(videoID(url))))
        adopt(url)
    }

    private func dropIncoming() {
        incoming = nil
        player.dropIncoming()
    }
}
