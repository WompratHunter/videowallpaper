import Foundation
import SharedKernel

// MARK: - Rotation rules
// The Rotation's constants, the brightness ranking the Target brightness is a place in, and what a switch may look
// like at each Presence. Part of the Rotation (see Rotation.swift), split out for length.

enum RotationRules {
    /// The largest mean-luminance difference a switch may make while anyone could see it.
    static let brightnessBand = 0.08
    /// With fewer videos, aiming `dynamic` at the Target brightness would leave too little to rotate: it acts as `all`.
    static let minimumForDaylight = 4
    /// `dynamic` picks at random among unplayed videos this close to the Target brightness, in rank.
    static let targetWindow = 0.15
    /// Further than this from the Target brightness, in rank, the Current video goes at the next Unseen or Veiled
    /// moment without waiting for Dwell. Wide enough that dusk is followed by ordinary Dwell switches.
    static let offTarget = 0.4
    /// Exactly 0.08 apart is within the band, whatever the floating-point rounding.
    static let tolerance = 1e-9
    /// The crossfade of every switch outside the slow Visible-only fallback (see `allowedTransition(for:)`).
    static let quickFade: TimeInterval = 5
}

// MARK: - Target brightness

/// Each video's place from darkest (0) to brightest (1), evenly spaced whatever the luminance gaps, so the Target
/// brightness means the same with any library. Ties go by name so the order is stable; a lone video sits at 0.5.
func brightnessRanks(_ videos: [EligibleVideo]) -> [String: Double] {
    let sorted = videos.sorted { ($0.meanLuminance, $0.name) < ($1.meanLuminance, $1.name) }
    let last = Double(max(sorted.count - 1, 1))
    let pairs = sorted.enumerated().map { ($1.name, sorted.count == 1 ? 0.5 : Double($0) / last) }
    return Dictionary(pairs) { first, _ in first }
}

// MARK: - Allowed transition

/// What a switch may look like at a given Presence: Unseen and Veiled take a 5 s crossfade after the minimum Dwell;
/// Visible only takes the slow fallback after an hour. Only Unseen allows a large brightness jump.
struct AllowedTransition: Equatable {
    let crossfade: TimeInterval
    let minimumDwell: TimeInterval
    let allowsBrightnessJump: Bool
}

func allowedTransition(for state: Presence) -> AllowedTransition {
    let quick = RotationRules.quickFade
    switch state {
    case .unseen: return AllowedTransition(crossfade: quick, minimumDwell: 20 * 60, allowsBrightnessJump: true)
    case .veiled: return AllowedTransition(crossfade: quick, minimumDwell: 20 * 60, allowsBrightnessJump: false)
    case .visible: return AllowedTransition(crossfade: 20, minimumDwell: 60 * 60, allowsBrightnessJump: false)
    }
}
