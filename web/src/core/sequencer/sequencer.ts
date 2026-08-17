import type { Track } from "../shared/types";
import { getBpmMatch, type BpmMatch, type BpmMatchPreferences } from "../bpm/match";

/**
 * Playlist intelligence: given a target cadence and a playlist, rank tracks
 * by how well they'd serve the runner *right now* and build an adaptive
 * "Up Next" queue.
 */

export interface SequencerContext {
  targetSpm: number;
  /** Track currently playing (excluded from ranking, used for transition cost). */
  currentTrack?: Track | null;
  /** Track ids played recently, most recent last. */
  recentlyPlayedIds?: string[];
  /** Track ids the user skipped this session. */
  skippedIds?: string[];
  bpmPrefs?: BpmMatchPreferences;
  weights?: Partial<SequencerWeights>;
}

export interface SequencerWeights {
  /** Weight of the BPM compatibility score. */
  bpmMatch: number;
  /** Max penalty for a track played recently (scaled by recency). */
  recentlyPlayed: number;
  /** Penalty for a track the user skipped this session. */
  skipped: number;
  /** Max penalty for a jarring perceived-BPM jump from the current track. */
  transition: number;
  /** Perceived-BPM jump (SPM) at which the transition penalty saturates. */
  transitionSaturationSpm: number;
  /** Flat score for tracks with unknown BPM (kept, but ranked low). */
  unknownBpmScore: number;
}

export const DEFAULT_SEQUENCER_WEIGHTS: SequencerWeights = {
  bpmMatch: 1,
  recentlyPlayed: 0.45,
  skipped: 0.75,
  transition: 0.2,
  transitionSaturationSpm: 30,
  unknownBpmScore: 0.15,
};

export interface RankedTrack {
  track: Track;
  score: number;
  match: BpmMatch | null;
  reasons: string[];
}

/** Rank every candidate track for the given context, best first. */
export function rankTracks(tracks: Track[], context: SequencerContext): RankedTrack[] {
  const weights = { ...DEFAULT_SEQUENCER_WEIGHTS, ...context.weights };
  const recent = context.recentlyPlayedIds ?? [];
  const skipped = new Set(context.skippedIds ?? []);
  const currentMatch = context.currentTrack
    ? getBpmMatch(context.targetSpm, context.currentTrack.bpm, context.bpmPrefs)
    : null;

  const ranked: RankedTrack[] = [];
  for (const track of tracks) {
    if (context.currentTrack && track.id === context.currentTrack.id) continue;

    const reasons: string[] = [];
    const match = getBpmMatch(context.targetSpm, track.bpm, context.bpmPrefs);
    let score: number;

    if (match === null) {
      score = weights.unknownBpmScore;
      reasons.push("BPM unknown");
    } else {
      score = match.score * weights.bpmMatch;
      reasons.push(
        `${match.perceivedBpm.toFixed(0)} perceived BPM (${match.multiplier}x) vs ${context.targetSpm} SPM target`,
      );

      // Avoid whiplash transitions between consecutive tracks.
      if (currentMatch) {
        const jump = Math.abs(match.perceivedBpm - currentMatch.perceivedBpm);
        const transitionPenalty =
          Math.min(1, jump / weights.transitionSaturationSpm) * weights.transition;
        if (transitionPenalty > 0.01) {
          score -= transitionPenalty;
          reasons.push(`transition jump ${jump.toFixed(0)} BPM from current track`);
        }
      }
    }

    const recentIndex = recent.lastIndexOf(track.id);
    if (recentIndex !== -1) {
      // Most recently played ⇒ full penalty; decays for older plays.
      const recency = (recentIndex + 1) / recent.length;
      const penalty = weights.recentlyPlayed * recency;
      score -= penalty;
      reasons.push("played recently");
    }

    if (skipped.has(track.id)) {
      score -= weights.skipped;
      reasons.push("skipped this session");
    }

    ranked.push({ track, score, match, reasons });
  }

  ranked.sort((a, b) => b.score - a.score);
  return ranked;
}

/** Build the visible "Up Next" queue (top N ranked tracks). */
export function buildQueue(tracks: Track[], context: SequencerContext, length = 5): RankedTrack[] {
  return rankTracks(tracks, context).slice(0, length);
}

/** Pick the next track to play (or null if nothing is available). */
export function pickNextTrack(tracks: Track[], context: SequencerContext): RankedTrack | null {
  return rankTracks(tracks, context)[0] ?? null;
}
