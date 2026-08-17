import { describe, expect, it } from "vitest";
import { buildQueue, pickNextTrack, rankTracks } from "./sequencer";
import type { Track } from "../shared/types";

function track(id: string, bpm: number | null): Track {
  return {
    id,
    provider: "demo",
    providerTrackId: id,
    name: `Track ${id}`,
    artist: "Test",
    artworkUrl: null,
    durationMs: 180_000,
    bpm,
  };
}

const LIBRARY: Track[] = [
  track("t150", 150),
  track("t160", 160),
  track("t170", 170),
  track("t180", 180),
  track("t85", 85), // half-time 170
  track("t128", 128),
  track("tNull", null),
];

describe("rankTracks", () => {
  it("ranks the closest BPM first for the target cadence", () => {
    const ranked = rankTracks(LIBRARY, { targetSpm: 160 });
    expect(ranked[0].track.id).toBe("t160");
  });

  it("treats an 85 BPM track as strong for a 170 SPM target (2x)", () => {
    const ranked = rankTracks(LIBRARY, { targetSpm: 170 });
    const ids = ranked.map((r) => r.track.id);
    expect(ids[0]).toBe("t170");
    expect(ids[1]).toBe("t85");
    expect(ranked[1].match?.multiplier).toBe(2);
  });

  it("excludes the current track from the ranking", () => {
    const ranked = rankTracks(LIBRARY, { targetSpm: 170, currentTrack: track("t170", 170) });
    expect(ranked.find((r) => r.track.id === "t170")).toBeUndefined();
  });

  it("penalizes recently played tracks", () => {
    const fresh = rankTracks(LIBRARY, { targetSpm: 160 });
    const afterPlay = rankTracks(LIBRARY, {
      targetSpm: 160,
      recentlyPlayedIds: ["t160"],
    });
    expect(fresh[0].track.id).toBe("t160");
    expect(afterPlay[0].track.id).not.toBe("t160");
    const t160 = afterPlay.find((r) => r.track.id === "t160");
    expect(t160?.reasons).toContain("played recently");
  });

  it("penalizes skipped tracks harder than recently played ones", () => {
    const ranked = rankTracks(LIBRARY, {
      targetSpm: 160,
      skippedIds: ["t160"],
      recentlyPlayedIds: ["t150"],
    });
    const skipped = ranked.find((r) => r.track.id === "t160")!;
    const recent = ranked.find((r) => r.track.id === "t150")!;
    // t160 is a perfect BPM match, t150 is 10 off — yet the skip penalty
    // should drag t160 down at least near t150's level.
    expect(skipped.score).toBeLessThan(recent.score + 0.15);
    expect(skipped.reasons).toContain("skipped this session");
  });

  it("avoids jarring transitions from the current track", () => {
    // Target 170; current track perceived at 170 — the 180 track costs a
    // transition penalty relative to 85 (perceived 170).
    const ranked = rankTracks(LIBRARY, {
      targetSpm: 170,
      currentTrack: track("cur", 170),
    });
    const t85 = ranked.find((r) => r.track.id === "t85")!;
    const t180 = ranked.find((r) => r.track.id === "t180")!;
    expect(t85.score).toBeGreaterThan(t180.score);
    expect(t180.reasons.join(" ")).toContain("transition jump");
  });

  it("keeps unknown-BPM tracks in the pool but ranks them low", () => {
    const ranked = rankTracks(LIBRARY, { targetSpm: 160 });
    const unknown = ranked.find((r) => r.track.id === "tNull")!;
    expect(unknown).toBeDefined();
    expect(unknown.match).toBeNull();
    expect(ranked.indexOf(unknown)).toBeGreaterThan(2);
  });

  it("adapts the ordering when the target cadence changes", () => {
    const at150 = rankTracks(LIBRARY, { targetSpm: 150 });
    const at180 = rankTracks(LIBRARY, { targetSpm: 180 });
    expect(at150[0].track.id).toBe("t150");
    expect(at180[0].track.id).toBe("t180");
  });
});

describe("buildQueue / pickNextTrack", () => {
  it("returns at most the requested queue length", () => {
    expect(buildQueue(LIBRARY, { targetSpm: 160 }, 3)).toHaveLength(3);
  });

  it("picks the best available next track", () => {
    const next = pickNextTrack(LIBRARY, {
      targetSpm: 170,
      currentTrack: track("t170", 170),
      recentlyPlayedIds: ["t85"],
    });
    expect(next).not.toBeNull();
    expect(["t85", "t180", "t160"]).toContain(next!.track.id);
    expect(next!.track.id).not.toBe("t170");
  });

  it("returns null when the library only contains the current track", () => {
    const only = [track("t1", 160)];
    expect(pickNextTrack(only, { targetSpm: 160, currentTrack: only[0] })).toBeNull();
  });
});
