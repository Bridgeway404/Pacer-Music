import type { CadenceSample } from "../shared/types";
import { BaseCadenceProvider } from "./provider";
import { median } from "./filters";

/**
 * TapCadenceProvider — the user taps a button once per step (or per footfall
 * of one foot with `stepsPerTap = 2`) and we derive SPM from tap intervals.
 *
 * Lets the concept be demonstrated on any phone with zero sensors.
 */
export interface TapConfig {
  /** How many steps one tap represents (2 = tap every other footfall). */
  stepsPerTap: number;
  /** Taps kept for the interval estimate. */
  windowTaps: number;
  /** Emit a fresh sample at this interval while taps are active, ms. */
  emitIntervalMs: number;
  /** If no tap for this long, emit zero-cadence (runner stopped), ms. */
  idleTimeoutMs: number;
}

export const DEFAULT_TAP_CONFIG: TapConfig = {
  stepsPerTap: 1,
  windowTaps: 8,
  emitIntervalMs: 1000,
  idleTimeoutMs: 3000,
};

export class TapCadenceProvider extends BaseCadenceProvider {
  readonly id = "tap";
  readonly label = "Tap Cadence";

  private config: TapConfig;
  private tapTimes: number[] = [];
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(config: Partial<TapConfig> = {}) {
    super();
    this.config = { ...DEFAULT_TAP_CONFIG, ...config };
  }

  /** Register a tap. `at` defaults to now (injectable for tests). */
  tap(at: number = Date.now()): void {
    this.tapTimes.push(at);
    if (this.tapTimes.length > this.config.windowTaps) {
      this.tapTimes = this.tapTimes.slice(-this.config.windowTaps);
    }
    this.emitSample(at);
  }

  /** Current SPM estimate from recent tap intervals (null if <2 taps). */
  currentSpm(now: number = Date.now()): number | null {
    const taps = this.tapTimes.filter((t) => now - t <= this.config.idleTimeoutMs * 2);
    if (taps.length < 2) return null;
    const intervals: number[] = [];
    for (let i = 1; i < taps.length; i++) intervals.push(taps[i] - taps[i - 1]);
    const medInterval = median(intervals);
    if (!medInterval || medInterval <= 0) return null;
    return (60_000 / medInterval) * this.config.stepsPerTap;
  }

  async start(): Promise<void> {
    if (this.timer) return;
    this.timer = setInterval(() => {
      const now = Date.now();
      const last = this.tapTimes[this.tapTimes.length - 1];
      if (last === undefined) return;
      if (now - last >= this.config.idleTimeoutMs) {
        // Runner stopped tapping.
        if (now - last < this.config.idleTimeoutMs + this.config.emitIntervalMs * 2) {
          this.emit({ capturedAt: now, spm: 0, source: "tap" });
        }
        return;
      }
      this.emitSample(now);
    }, this.config.emitIntervalMs);
  }

  async stop(): Promise<void> {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.tapTimes = [];
  }

  private emitSample(now: number): void {
    const spm = this.currentSpm(now);
    if (spm !== null) {
      this.emit({ capturedAt: now, spm: Math.round(spm * 10) / 10, source: "tap" });
    }
  }
}
