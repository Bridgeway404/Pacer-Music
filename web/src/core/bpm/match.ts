/**
 * BPM ↔ cadence matching.
 *
 * A runner at 170 SPM can comfortably run to ~170 BPM (one step per beat)
 * or ~85 BPM (one step per half-beat, "half-time" feel), and a 340 BPM
 * track would be perceived at half speed. So we evaluate the track at a
 * set of musically meaningful multipliers and pick the best perceived fit.
 */

export interface BpmMatchPreferences {
  /** Multipliers to consider (applied to the track BPM). */
  multipliers?: number[];
  /** |perceived − cadence| ≤ this ⇒ "good match", SPM. */
  toleranceSpm?: number;
  /** Score reaches 0 at this difference, SPM. */
  maxDifferenceSpm?: number;
  /**
   * Score penalty factor for non-1x multipliers (0–1). 1 = no penalty.
   * Slightly favors direct 1:1 matches when scores are otherwise close.
   */
  altMultiplierWeight?: number;
}

export interface BpmMatch {
  /** 0–1. 1 = perceived tempo exactly equals cadence. */
  score: number;
  /** The multiplier that produced the best perceived match. */
  multiplier: number;
  /** trackBpm × multiplier. */
  perceivedBpm: number;
  /** |perceivedBpm − cadence|, SPM. */
  difference: number;
  /** difference ≤ tolerance. */
  isGoodMatch: boolean;
  /**
   * Tempo the track should be *played at* for perfect sync, in track-BPM
   * terms (cadence / multiplier). Only meaningful for tempo-shiftable audio
   * (Demo Audio Mode); streaming providers cannot use this.
   */
  recommendedTargetTempo: number;
  /** Playback-rate multiplier to reach the recommended tempo (target/track). */
  recommendedPlaybackRate: number;
}

export const DEFAULT_BPM_PREFS: Required<BpmMatchPreferences> = {
  multipliers: [0.5, 1, 2],
  toleranceSpm: 6,
  maxDifferenceSpm: 25,
  altMultiplierWeight: 0.92,
};

/**
 * Evaluate how well `trackBpm` suits a runner at `cadenceSpm`.
 * Returns null when the track BPM is unknown or inputs are invalid.
 */
export function getBpmMatch(
  cadenceSpm: number,
  trackBpm: number | null | undefined,
  preferences: BpmMatchPreferences = {},
): BpmMatch | null {
  if (trackBpm == null || trackBpm <= 0 || cadenceSpm <= 0 || !Number.isFinite(cadenceSpm)) {
    return null;
  }
  const prefs = { ...DEFAULT_BPM_PREFS, ...preferences };

  let best: BpmMatch | null = null;
  for (const multiplier of prefs.multipliers) {
    const perceivedBpm = trackBpm * multiplier;
    const difference = Math.abs(perceivedBpm - cadenceSpm);
    const closeness = Math.max(0, 1 - difference / prefs.maxDifferenceSpm);
    const weight = multiplier === 1 ? 1 : prefs.altMultiplierWeight;
    const score = closeness * weight;
    const candidate: BpmMatch = {
      score,
      multiplier,
      perceivedBpm,
      difference,
      isGoodMatch: difference <= prefs.toleranceSpm,
      recommendedTargetTempo: cadenceSpm / multiplier,
      recommendedPlaybackRate: cadenceSpm / multiplier / trackBpm,
    };
    if (best === null || candidate.score > best.score) {
      best = candidate;
    }
  }
  return best;
}
