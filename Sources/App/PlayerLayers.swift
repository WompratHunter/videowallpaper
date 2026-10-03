import AVFoundation
import QuartzCore

// MARK: - Player layers
// Every window's Poster layer and the video layer above it. The video layers all show the Player's one queue player,
// and the Poster layers share one decoded image, so tearing the player down reveals the Poster, never black.

final class PlayerLayers {
    private let videoLayers = NSHashTable<AVPlayerLayer>.weakObjects()
    private let posterLayers = NSHashTable<CALayer>.weakObjects()
    private var poster: CGImage?
    private var player: AVPlayer?

    /// A Poster layer with the video layer above it, sized to `frame`, showing the current player and Poster.
    func make(frame: CGRect) -> CALayer {
        let container = CALayer()
        container.frame = frame
        let posterLayer = CALayer()
        posterLayer.frame = container.bounds
        posterLayer.contentsGravity = .resizeAspectFill
        posterLayer.masksToBounds = true
        posterLayer.contents = poster
        let videoLayer = AVPlayerLayer()
        videoLayer.frame = container.bounds
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.player = player
        container.addSublayer(posterLayer)
        container.addSublayer(videoLayer)
        posterLayers.add(posterLayer)
        videoLayers.add(videoLayer)
        return container
    }

    /// Binds every video layer, including those made later, to `player`; nil leaves only the Poster showing.
    func attach(_ player: AVPlayer?) {
        self.player = player
        videoLayers.allObjects.forEach { $0.player = player }
    }

    func setPoster(_ image: CGImage) {
        poster = image
        posterLayers.allObjects.forEach { $0.contents = image }
    }
}
