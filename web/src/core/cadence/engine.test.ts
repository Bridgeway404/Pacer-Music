import { describe, expect, it } from "vitest";
import { CadenceEngine, type CadenceEngineUpdate } from "./engine";
import type { CadenceSample } from "../shared/types";

/**
 * Deterministic test harness: feeds a scripted SPM series at a fixed sample
 * interval, with optional seeded pseudo-random noise.
 */

function makeSample(t: number, spm: number): CadenceSample {
  return { capturedAt: t, spm, source: "simulator" };
}

/** Small deterministic PRNG (mulberry32). */
function rng(seed: number): () => number {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface FeedResult {
  updates: CadenceEngineUpdate[];
  decisions: CadenceEngineUpdate[];
}

function feed(
  engine: CadenceEngine,
  spmSeries: number[],
  { startAt = 0, intervalMs = 600 }: { startAt?: number; intervalMs?: number } = {},
): FeedResult {
  const updates: CadenceEngineUpdate[] = [];
  spmSeries.forEach((spm, i) => {
    updates.push(engine.addSample(makeSample(startAt + i * intervalMs, spm)));
  });
  return { updates, decisions: updates.filter((u) => u.decision !== null) };
}

function constantSeries(spm: number, count: number): number[] {
  return Array.from({ length: count }, () => spm);
}

function noisySeries(spm: number, count: number, noise: number, seed = 42): number[] {
  const rand = rng(seed);
  return Array.from({ length: count }, () => spm + (rand() * 2 - 1) * noise);
}

describe("CadenceEngine", () => {
  it("locks an initial target on stable 160 SPM", () => {
    const engine = new CadenceEngine();
    const { updates, decisions } = feed(engine, constantSeries(160, 20));

    expect(decisions).toHaveLength(1);
    expect(decisions[0].decision?.type).toBe("initial_lock");
    expect(engine.getTarget()).toBe(160);
    expect(updates.at(-1)?.state).toBe("locked");
  });

  it("holds a steady target on noisy 160 SPM (±3 SPM jitter)", () => {
    const engine = new CadenceEngine();
    const { decisions } = feed(engine, noisySeries(160, 60, 3));

    // Only the initial lock — noise must not cause retargets.
    expect(decisions).toHaveLength(1);
    expect(decisions[0].decision?.type).toBe("initial_lock");
    expect(engine.getTarget()).toBeGreaterThanOrEqual(158);
    expect(engine.getTarget()).toBeLessThanOrEqual(162);
  });

  it("retargets on a sustained 160 → 170 transition within 15 s", () => {
    const engine = new CadenceEngine();
    feed(engine, noisySeries(160, 30, 2));
    expect(engine.getTarget()).toBeCloseTo(160, 0);

    const t0 = 30 * 600;
    const series = noisySeries(170, 40, 2, 7);
    let retargetAt: number | null = null;
    series.forEach((spm, i) => {
      const update = engine.addSample(makeSample(t0 + i * 600, spm));
      if (update.decision?.type === "retarget" && retargetAt === null) {
        retargetAt = update.at;
      }
    });

    expect(retargetAt).not.toBeNull();
    const elapsed = (retargetAt as unknown as number) - t0;
    expect(elapsed).toBeLessThanOrEqual(15_000);
    expect(elapsed).toBeGreaterThanOrEqual(4_000); // must not be instant
    expect(engine.getTarget()).toBeGreaterThanOrEqual(167);
    expect(engine.getTarget()).toBeLessThanOrEqual(172);
  });

  it("ignores a brief spike", () => {
    const engine = new CadenceEngine();
    feed(engine, constantSeries(160, 30));

    // 3-second spike to 185, then back — shorter than sustainMs.
    const t0 = 30 * 600;
    const spike = [...constantSeries(185, 5), ...constantSeries(160, 30)];
    const { decisions } = feed(engine, spike, { startAt: t0 });

    expect(decisions.filter((d) => d.decision?.type === "retarget")).toHaveLength(0);
    expect(engine.getTarget()).toBe(160);
  });

  it("follows gradual acceleration 150 → 175 with a few discrete retargets", () => {
    const engine = new CadenceEngine();
    // Accelerate 150→175 over ~2 minutes (0.125 SPM per 600 ms sample).
    const series: number[] = [];
    for (let i = 0; i < 200; i++) series.push(150 + i * 0.125);
    const { decisions } = feed(engine, series);

    const retargets = decisions.filter((d) => d.decision?.type === "retarget");
    expect(retargets.length).toBeGreaterThanOrEqual(2); // follows the trend…
    expect(retargets.length).toBeLessThanOrEqual(8); // …without thrashing
    expect(engine.getTarget()).toBeGreaterThanOrEqual(168);
  });

  it("follows gradual deceleration 175 → 155", () => {
    const engine = new CadenceEngine();
    const series: number[] = [];
    for (let i = 0; i < 160; i++) series.push(175 - i * 0.125);
    feed(engine, series);
    expect(engine.getTarget()).toBeLessThanOrEqual(160);
    expect(engine.getTarget()).toBeGreaterThanOrEqual(152);
  });

  it("detects stopping via zero-cadence samples", () => {
    const engine = new CadenceEngine();
    feed(engine, constantSeries(160, 20));
    const update = engine.addSample(makeSample(20 * 600, 0));
    expect(update.state).toBe("stopped");
    expect(update.decision?.type).toBe("stop");
  });

  it("detects stopping via sample silence (tick timeout)", () => {
    const engine = new CadenceEngine();
    feed(engine, constantSeries(160, 20));
    const lastT = 19 * 600;
    const update = engine.tick(lastT + 5000);
    expect(update.state).toBe("stopped");
    expect(update.decision?.type).toBe("stop");
  });

  it("resumes cleanly after a stop and re-locks", () => {
    const engine = new CadenceEngine();
    feed(engine, constantSeries(160, 20));
    engine.addSample(makeSample(20 * 600, 0));
    expect(engine.getState()).toBe("stopped");

    const t0 = 60_000;
    const { decisions } = feed(engine, constantSeries(172, 20), { startAt: t0 });
    const types = decisions.map((d) => d.decision?.type);
    expect(types).toContain("resume");
    expect(types).toContain("initial_lock");
    expect(engine.getState()).toBe("locked");
    expect(engine.getTarget()).toBeGreaterThanOrEqual(170);
  });

  it("discards physically implausible samples", () => {
    const engine = new CadenceEngine();
    feed(engine, constantSeries(160, 20));
    engine.addSample(makeSample(20 * 600, 900)); // sensor glitch
    engine.addSample(makeSample(21 * 600, 15)); // sub-walking glitch (>0, <min)
    expect(engine.getTarget()).toBe(160);
    expect(engine.getState()).toBe("locked");
  });

  it("does not retarget for a small drift below the threshold", () => {
    const engine = new CadenceEngine();
    feed(engine, constantSeries(160, 20));
    const { decisions } = feed(engine, constantSeries(162, 40), { startAt: 20 * 600 });
    expect(decisions.filter((d) => d.decision?.type === "retarget")).toHaveLength(0);
    expect(engine.getTarget()).toBe(160);
  });

  it("respects a custom sustain window", () => {
    const engine = new CadenceEngine({ sustainMs: 2000 });
    feed(engine, constantSeries(160, 20));
    let retargetAt: number | null = null;
    const t0 = 20 * 600;
    constantSeries(170, 20).forEach((spm, i) => {
      const u = engine.addSample(makeSample(t0 + i * 600, spm));
      if (u.decision?.type === "retarget" && retargetAt === null) retargetAt = u.at;
    });
    expect(retargetAt).not.toBeNull();
    expect((retargetAt as unknown as number) - t0).toBeLessThanOrEqual(9_000);
  });
});
