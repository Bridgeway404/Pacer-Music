import { describe, expect, it } from "vitest";
import { RollingWindow, emaStep, mean, median } from "./filters";

describe("median", () => {
  it("handles odd and even lengths", () => {
    expect(median([3, 1, 2])).toBe(2);
    expect(median([4, 1, 3, 2])).toBe(2.5);
  });
  it("returns NaN for empty input", () => {
    expect(Number.isNaN(median([]))).toBe(true);
  });
  it("is robust to a single outlier", () => {
    expect(median([160, 161, 159, 400, 160])).toBe(160);
  });
});

describe("mean", () => {
  it("averages values", () => {
    expect(mean([1, 2, 3])).toBe(2);
  });
});

describe("emaStep", () => {
  it("initializes to the first value", () => {
    expect(emaStep(null, 160, 0.3)).toBe(160);
  });
  it("moves a fraction toward the new value", () => {
    expect(emaStep(160, 170, 0.3)).toBeCloseTo(163);
  });
  it("converges toward a constant input", () => {
    let v: number | null = 150;
    for (let i = 0; i < 50; i++) v = emaStep(v, 170, 0.3);
    expect(v).toBeGreaterThan(169.5);
  });
});

describe("RollingWindow", () => {
  it("evicts values outside the time window", () => {
    const w = new RollingWindow(5000);
    w.push(0, 1);
    w.push(2000, 2);
    w.push(6000, 3); // evicts t=0
    expect(w.values()).toEqual([2, 3]);
    expect(w.size()).toBe(2);
  });
  it("returns the last N values", () => {
    const w = new RollingWindow(60_000);
    [1, 2, 3, 4, 5].forEach((v, i) => w.push(i * 1000, v));
    expect(w.lastValues(3)).toEqual([3, 4, 5]);
    expect(w.lastValues(10)).toEqual([1, 2, 3, 4, 5]);
  });
});
