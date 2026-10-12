import AVFoundation

// MARK: - Looping player
// A looping, muted player for one video: the current one, and during a crossfade the incoming one.

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
