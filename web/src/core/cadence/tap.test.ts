import { describe, expect, it } from "vitest";
import { TapCadenceProvider } from "./tap";

describe("TapCadenceProvider", () => {
  it("derives SPM from evenly spaced taps (170 SPM)", () => {
    const p = new TapCadenceProvider();
    const interval = 60_000 / 170;
    for (let i = 0; i < 8; i++) p.tap(i * interval);
    expect(p.currentSpm(7 * interval)).toBeCloseTo(170, 0);
  });

  it("handles steps-per-tap scaling (tap every other footfall)", () => {
    const p = new TapCadenceProvider({ stepsPerTap: 2 });
    const interval = (60_000 / 170) * 2; // tapping half as often
    for (let i = 0; i < 8; i++) p.tap(i * interval);
    expect(p.currentSpm(7 * interval)).toBeCloseTo(170, 0);
  });

  it("uses the median interval so one hesitation doesn't skew the estimate", () => {
    const p = new TapCadenceProvider();
    const interval = 60_000 / 160;
    let t = 0;
    for (let i = 0; i < 6; i++) {
      p.tap(t);
      t += interval;
    }
    p.tap(t + 900); // one long hesitation
    const spm = p.currentSpm(t + 900);
    expect(spm).toBeGreaterThan(150);
  });

  it("returns null with fewer than 2 taps", () => {
    const p = new TapCadenceProvider();
    expect(p.currentSpm(0)).toBeNull();
    p.tap(0);
    expect(p.currentSpm(0)).toBeNull();
  });

  it("emits a sample on each tap once cadence is estimable", () => {
    const p = new TapCadenceProvider();
    const samples: number[] = [];
    p.subscribe((s) => samples.push(s.spm));
    const interval = 60_000 / 150;
    for (let i = 0; i < 5; i++) p.tap(i * interval);
    expect(samples.length).toBeGreaterThanOrEqual(3);
    expect(samples.at(-1)).toBeCloseTo(150, 0);
  });
});
