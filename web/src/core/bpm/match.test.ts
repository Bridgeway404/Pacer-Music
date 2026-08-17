import { describe, expect, it } from "vitest";
import { getBpmMatch } from "./match";

describe("getBpmMatch", () => {
  it("returns a perfect 1x match when BPM equals cadence", () => {
    const m = getBpmMatch(170, 170);
    expect(m).not.toBeNull();
    expect(m?.multiplier).toBe(1);
    expect(m?.difference).toBe(0);
    expect(m?.score).toBe(1);
    expect(m?.isGoodMatch).toBe(true);
    expect(m?.perceivedBpm).toBe(170);
  });

  it("matches half-time: 85 BPM track for a 170 SPM runner via 2x", () => {
    const m = getBpmMatch(170, 85);
    expect(m?.multiplier).toBe(2);
    expect(m?.perceivedBpm).toBe(170);
    expect(m?.difference).toBe(0);
    expect(m?.isGoodMatch).toBe(true);
  });

  it("matches double-time: 340 BPM material perceived at 0.5x", () => {
    const m = getBpmMatch(170, 340);
    expect(m?.multiplier).toBe(0.5);
    expect(m?.perceivedBpm).toBe(170);
    expect(m?.isGoodMatch).toBe(true);
  });

  it("slightly prefers a direct 1x match over an equally-close 2x match", () => {
    // 168 track at 1x (diff 2) vs 85 track at 2x (diff 2): 1x should score higher.
    const direct = getBpmMatch(170, 168);
    const half = getBpmMatch(170, 85.99);
    expect(direct).not.toBeNull();
    expect(half).not.toBeNull();
    expect(direct!.score).toBeGreaterThan(half!.score);
  });

  it("reports a poor match for musically unrelated tempi", () => {
    const m = getBpmMatch(170, 140);
    expect(m?.isGoodMatch).toBe(false);
    // Best option is 1x with a 30 BPM gap → score 0 at default 25-SPM falloff…
    // or 0.5/2x which are even further. Either way, near-zero score.
    expect(m!.score).toBeLessThan(0.2);
  });

  it("respects a custom tolerance", () => {
    const strict = getBpmMatch(170, 165, { toleranceSpm: 3 });
    const loose = getBpmMatch(170, 165, { toleranceSpm: 8 });
    expect(strict?.isGoodMatch).toBe(false);
    expect(loose?.isGoodMatch).toBe(true);
  });

  it("computes recommendedTargetTempo and playback rate for tempo-shifting", () => {
    // 150 BPM demo track, runner at 165 SPM, 1x match:
    // play the track at 165 BPM ⇒ rate 1.1.
    const m = getBpmMatch(165, 150);
    expect(m?.multiplier).toBe(1);
    expect(m?.recommendedTargetTempo).toBeCloseTo(165);
    expect(m?.recommendedPlaybackRate).toBeCloseTo(1.1);
  });

  it("computes recommended tempo through a 2x multiplier", () => {
    // 82 BPM track, runner at 170 ⇒ perceived 164 via 2x; to sync perfectly
    // the track itself should play at 85 BPM ⇒ rate 85/82.
    const m = getBpmMatch(170, 82);
    expect(m?.multiplier).toBe(2);
    expect(m?.recommendedTargetTempo).toBeCloseTo(85);
    expect(m?.recommendedPlaybackRate).toBeCloseTo(85 / 82);
  });

  it("returns null for unknown or invalid inputs", () => {
    expect(getBpmMatch(170, null)).toBeNull();
    expect(getBpmMatch(170, undefined)).toBeNull();
    expect(getBpmMatch(170, 0)).toBeNull();
    expect(getBpmMatch(170, -10)).toBeNull();
    expect(getBpmMatch(0, 150)).toBeNull();
    expect(getBpmMatch(NaN, 150)).toBeNull();
  });

  it("score decays monotonically with distance", () => {
    const scores = [170, 172, 175, 180, 190].map((bpm) => getBpmMatch(170, bpm)!.score);
    for (let i = 1; i < scores.length; i++) {
      expect(scores[i]).toBeLessThanOrEqual(scores[i - 1]);
    }
  });

  it("supports custom multipliers (e.g. 1.5x triplet feel)", () => {
    const m = getBpmMatch(180, 120, { multipliers: [0.5, 1, 1.5, 2] });
    expect(m?.multiplier).toBe(1.5);
    expect(m?.perceivedBpm).toBe(180);
  });
});
