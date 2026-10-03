import Foundation

// MARK: - Crossfade
// The state of a switch from the Current video to another. The incoming player loads beside the outgoing one,
// fades in once it is ready for display, then replaces it, so two decoders only run during a fade. Every way a
// fade can end (finished, paused, torn down, failed, timed out) is decided here, so the player only applies
// actions and is never left with an orphaned second player. A failed incoming video never costs the healthy
// outgoing one, so a switch can't drop the Live wallpaper to the Poster.

enum CrossfadeAction: Equatable {
    /// Replace both players with the target at once (and drop any incoming player).
    case cut(URL)
    /// Build the incoming player for the target, hidden above the outgoing one.
    case load(id: Int, URL)
    /// Fade the incoming layers in; report `animationFinished(id:)` when done.
    case animate(id: Int, duration: TimeInterval)
    /// The incoming player becomes the Current video's player; the outgoing one is released.
    case promote(URL)
    /// Release the incoming player; the outgoing one carries on (or is being torn down anyway).
    case dropIncoming
    /// The incoming video failed or never became ready: release it, and the outgoing video carries on unharmed.
    case abandon(URL)
}

struct Crossfade {
    /// Every switch outside the slow Visible-only fallback (which Rotation asks for with its own duration).
    static let quickDuration: TimeInterval = 5
    /// How long the incoming video may take to become ready for display, and how long a fade may overrun.
    static let readyTimeout: TimeInterval = 15

    private struct Fade {
        let id: Int
        let target: URL
        let duration: TimeInterval
        let since: TimeInterval
        var isFading = false
    }

    private var fade: Fade?
    /// A different target requested mid-fade; it follows once the running fade finishes.
    private var queued: (target: URL, duration: TimeInterval)?
    private var nextID = 0

    /// Switch to `target` over `duration` seconds; zero, or a player nobody can see, means a cut.
    mutating func request(
        _ target: URL, duration: TimeInterval, current: URL?, isPlaying: Bool, now: TimeInterval
    ) -> [CrossfadeAction] {
        guard duration > 0, isPlaying else {
            end()
            return [.cut(target)]
        }
        guard let running = fade else {
            return target == current ? [] : [load(target, duration: duration, now: now)]
        }
        if running.isFading {
            // The last request wins: asking for the fading target again cancels anything queued behind it.
            queued = target == running.target ? nil : (target, duration)
            return []
        }
        if target == running.target { return [] }
        end()
        return target == current ? [.dropIncoming] : [.dropIncoming, load(target, duration: duration, now: now)]
    }

    mutating func incomingReady(id: Int, now: TimeInterval) -> [CrossfadeAction] {
        guard let running = fade, running.id == id, !running.isFading else { return [] }
        fade = Fade(id: id, target: running.target, duration: running.duration, since: now, isFading: true)
        return [.animate(id: id, duration: running.duration)]
    }

    mutating func animationFinished(id: Int) -> [CrossfadeAction] {
        guard let running = fade, running.id == id, running.isFading else { return [] }
        return finish(running, now: running.since + running.duration)
    }

    mutating func incomingFailed(id: Int) -> [CrossfadeAction] {
        guard let running = fade, running.id == id else { return [] }
        end()
        return [.abandon(running.target)]
    }

    /// The player was paused (occluded or screens asleep): nobody sees the fade, so it completes now.
    mutating func pause() -> [CrossfadeAction] {
        guard let running = fade else { return [] }
        let next = queued
        end()
        if let next { return [.cut(next.target)] }
        return [.promote(running.target)]
    }

    /// Both players are being torn down (Recovery, Low Power Mode, a cut): forget the fade and any queued target.
    mutating func interrupt() -> [CrossfadeAction] {
        guard fade != nil else { return [] }
        end()
        return [.dropIncoming]
    }

    /// On the shared tick: a video never ready for display is abandoned, and an overdue fade is completed.
    mutating func tick(now: TimeInterval) -> [CrossfadeAction] {
        guard let running = fade else { return [] }
        if !running.isFading {
            guard now - running.since >= Self.readyTimeout else { return [] }
            end()
            return [.abandon(running.target)]
        }
        guard now - running.since >= running.duration + Self.readyTimeout else { return [] }
        return finish(running, now: now)
    }

    private mutating func load(_ target: URL, duration: TimeInterval, now: TimeInterval) -> CrossfadeAction {
        nextID += 1
        fade = Fade(id: nextID, target: target, duration: duration, since: now)
        return .load(id: nextID, target)
    }

    private mutating func finish(_ running: Fade, now: TimeInterval) -> [CrossfadeAction] {
        let next = queued
        end()
        guard let next else { return [.promote(running.target)] }
        return [.promote(running.target)]
            + request(next.target, duration: next.duration, current: running.target, isPlaying: true, now: now)
    }

    private mutating func end() {
        fade = nil
        queued = nil
    }
}
