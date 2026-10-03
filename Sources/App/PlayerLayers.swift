import AVFoundation
import QuartzCore

// MARK: - Player layers
// Every window's Poster layer and two video layers above it. The active video layers all show the Player's one
// queue player and the Poster layers share one decoded image, so tearing the player down reveals the Poster, never
// black. During a crossfade the other slot shows the incoming player above the active one and fades in.

final class PlayerLayers {
    /// Called on the main queue once every incoming video layer is ready for display.
    var onIncomingReady: () -> Void = {}

    private let slots = [NSHashTable<AVPlayerLayer>.weakObjects(), NSHashTable<AVPlayerLayer>.weakObjects()]
    private let posterLayers = NSHashTable<CALayer>.weakObjects()
    private var poster: CGImage?
    private var active = 0
    private var player: AVPlayer?
    private var incomingPlayer: AVPlayer?
    private var isIncomingVisible = false
    private var readyObservations: [NSKeyValueObservation] = []
    private var hasReportedReady = false

    private var incoming: Int { 1 - active }

    /// A Poster layer with the video layers above it, sized to `frame`, showing the current players and Poster.
    func make(frame: CGRect) -> CALayer {
        let container = CALayer()
        container.frame = frame
        let posterLayer = CALayer()
        posterLayer.frame = container.bounds
        posterLayer.contentsGravity = .resizeAspectFill
        posterLayer.masksToBounds = true
        posterLayer.contents = poster
        container.addSublayer(posterLayer)
        posterLayers.add(posterLayer)
        for slot in slots.indices {
            let videoLayer = AVPlayerLayer()
            videoLayer.frame = container.bounds
            videoLayer.videoGravity = .resizeAspectFill
            container.addSublayer(videoLayer)
            slots[slot].add(videoLayer)
        }
        withoutAnimation(arrange)
        if incomingPlayer != nil { observeReadiness() }
        return container
    }

    /// Binds every active video layer, including those made later, to `player`; nil leaves only the Poster showing.
    func attach(_ player: AVPlayer?) {
        self.player = player
        slots[active].allObjects.forEach { $0.player = player }
    }

    func setPoster(_ image: CGImage) {
        poster = image
        posterLayers.allObjects.forEach { $0.contents = image }
    }
}

// MARK: - Crossfade

extension PlayerLayers {
    /// Shows `player` hidden above the active layers; `onIncomingReady` fires once every layer can draw it.
    func attachIncoming(_ player: AVPlayer) {
        incomingPlayer = player
        isIncomingVisible = false
        hasReportedReady = false
        withoutAnimation(arrange)
        observeReadiness()
    }

    func fadeInIncoming(duration: TimeInterval) {
        isIncomingVisible = true
        withoutAnimation {
            for layer in slots[incoming].allObjects {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 0
                animation.toValue = 1
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: "crossfade")
                layer.opacity = 1
            }
        }
    }

    /// The incoming layers become the active ones at full opacity; the old active layers let go of their player.
    func promoteIncoming() {
        let outgoing = active
        active = incoming
        player = incomingPlayer
        incomingPlayer = nil
        isIncomingVisible = false
        stopObservingReadiness()
        withoutAnimation {
            slots[outgoing].allObjects.forEach { $0.player = nil }
            arrange()
        }
    }

    func dropIncoming() {
        incomingPlayer = nil
        isIncomingVisible = false
        stopObservingReadiness()
        withoutAnimation(arrange)
    }

    /// Stacking, opacity and players for both slots; the incoming slot sits above the active one.
    private func arrange() {
        for layer in slots[active].allObjects {
            layer.removeAnimation(forKey: "crossfade")
            layer.zPosition = 0
            layer.opacity = 1
            layer.player = player
        }
        for layer in slots[incoming].allObjects {
            if !isIncomingVisible { layer.removeAnimation(forKey: "crossfade") }
            layer.zPosition = 1
            layer.opacity = isIncomingVisible ? 1 : 0
            layer.player = incomingPlayer
        }
    }

    private func observeReadiness() {
        readyObservations = slots[incoming].allObjects.map {
            $0.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.reportReadyIfAll() }
            }
        }
    }

    private func stopObservingReadiness() {
        readyObservations.forEach { $0.invalidate() }
        readyObservations = []
    }

    private func reportReadyIfAll() {
        let layers = slots[incoming].allObjects
        guard incomingPlayer != nil, !hasReportedReady, !layers.isEmpty,
              layers.allSatisfy({ $0.isReadyForDisplay })
        else { return }
        hasReportedReady = true
        onIncomingReady()
    }

    /// These layers are not view-backed, so property changes would otherwise animate implicitly.
    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
