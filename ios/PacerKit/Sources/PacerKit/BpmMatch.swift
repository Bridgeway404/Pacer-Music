import Foundation

/// BPM ↔ cadence matching.
///
/// A runner at 170 SPM can comfortably run to ~170 BPM (one step per beat)
/// or ~85 BPM (one step per half-beat, "half-time" feel), and 340 BPM
/// material is perceived at half speed. We evaluate a track at a set of
/// musically meaningful multipliers and pick the best perceived fit.
public struct BpmMatchPreferences: Sendable {
    /// Multipliers to consider (applied to the track BPM).
    public var multipliers: [Double] = [0.5, 1, 2]
    /// |perceived − cadence| ≤ this ⇒ "good match", SPM.
    public var toleranceSpm: Double = 6
    /// Score reaches 0 at this difference, SPM.
    public var maxDifferenceSpm: Double = 25
    /// Score penalty factor for non-1x multipliers (0–1). 1 = no penalty.
    /// Slightly favors direct 1:1 matches when scores are otherwise close.
    public var altMultiplierWeight: Double = 0.92

    public init() {}
}

public struct BpmMatch: Sendable, Equatable {
    /// 0–1. 1 = perceived tempo exactly equals cadence.
    public let score: Double
    /// The multiplier that produced the best perceived match.
    public let multiplier: Double
    /// trackBpm × multiplier.
    public let perceivedBpm: Double
    /// |perceivedBpm − cadence|, SPM.
    public let difference: Double
    /// difference ≤ tolerance.
    public let isGoodMatch: Bool
    /// Tempo the track should be *played at* for perfect sync, in track-BPM
    /// terms (cadence / multiplier). Only meaningful for tempo-shiftable
    /// audio (Demo Audio Mode); streaming providers cannot use this.
    public let recommendedTargetTempo: Double
    /// Playback-rate multiplier to reach the recommended tempo (target/track).
    public let recommendedPlaybackRate: Double
}

public enum BpmMatcher {
    /// Evaluate how well `trackBpm` suits a runner at `cadenceSpm`.
    /// Returns nil when the track BPM is unknown or inputs are invalid.
    public static func match(
        cadenceSpm: Double,
        trackBpm: Double?,
        preferences: BpmMatchPreferences = BpmMatchPreferences()
    ) -> BpmMatch? {
        guard let trackBpm, trackBpm > 0, cadenceSpm > 0, cadenceSpm.isFinite else {
            return nil
        }

        var best: BpmMatch?
        for multiplier in preferences.multipliers {
            let perceivedBpm = trackBpm * multiplier
            let difference = abs(perceivedBpm - cadenceSpm)
            let closeness = max(0, 1 - difference / preferences.maxDifferenceSpm)
            let weight = multiplier == 1 ? 1 : preferences.altMultiplierWeight
            let candidate = BpmMatch(
                score: closeness * weight,
                multiplier: multiplier,
                perceivedBpm: perceivedBpm,
                difference: difference,
                isGoodMatch: difference <= preferences.toleranceSpm,
                recommendedTargetTempo: cadenceSpm / multiplier,
                recommendedPlaybackRate: cadenceSpm / multiplier / trackBpm
            )
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }
        return best
    }
}
