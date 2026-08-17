import type { CadenceSample } from "../shared/types";
import { RollingWindow, emaStep, median } from "./filters";

/**
 * CadenceEngine — turns a noisy stream of raw SPM samples into a stable
 * musical target.
 *
 * Design goals (see docs/ARCHITECTURE.md):
 *  - Smooth ~8–12 s of history so one-off jitters don't move the target.
 *  - Hysteresis: ignore differences below `changeThresholdSpm`.
 *  - Sustained-change detection: a meaningful change must persist for
 *    `sustainMs` before the target moves.
 *  - React to a real sustained pace change within ~10–15 s end to end.
 *
 * The engine is fully deterministic: all time comes from sample timestamps
 * and explicit `tick(now)` calls. It never reads the wall clock, which makes
 * it trivially unit-testable and portable to native runtimes.
 */

export interface CadenceEngineConfig {
  /** Smoothing window over raw samples, ms. */
  windowMs: number;
  /** Number of most-recent samples fed to the median pre-filter. */
  medianWindow: number;
  /** EMA alpha applied to the median-filtered signal. */
  emaAlpha: number;
  /** Minimum |smoothed − target| (SPM) considered a real change. */
  changeThresholdSpm: number;
  /** How long a candidate change must persist before we retarget, ms. */
  sustainMs: number;
  /** Samples required before the first target locks. */
  minSamplesForLock: number;
  /** No samples for this long ⇒ runner is considered stopped, ms. */
  stopTimeoutMs: number;
  /** Raw samples outside [minValidSpm, maxValidSpm] are discarded (0 = stop signal). */
  minValidSpm: number;
  maxValidSpm: number;
}

export const DEFAULT_CADENCE_CONFIG: CadenceEngineConfig = {
  windowMs: 10_000,
  medianWindow: 5,
  emaAlpha: 0.3,
  changeThresholdSpm: 4,
  sustainMs: 5_000,
  minSamplesForLock: 5,
  stopTimeoutMs: 4_000,
  minValidSpm: 40,
  maxValidSpm: 240,
};

export type CadenceEngineState =
  | "idle" // never received a sample
  | "acquiring" // receiving samples, no target locked yet
  | "locked" // target established
  | "stopped"; // runner stopped (no/zero samples)

export interface CadenceDecision {
  at: number;
  type: "initial_lock" | "retarget" | "stop" | "resume";
  targetSpm: number | null;
  previousTargetSpm: number | null;
  reason: string;
}

export interface CadenceEngineUpdate {
  at: number;
  rawSpm: number | null;
  smoothedSpm: number | null;
  targetSpm: number | null;
  state: CadenceEngineState;
  /** Present only on the updates where a decision was made. */
  decision: CadenceDecision | null;
  /** Candidate retarget in progress (for diagnostics UI). */
  pending: { candidateSpm: number; sinceMs: number } | null;
}

export class CadenceEngine {
  readonly config: CadenceEngineConfig;

  private window: RollingWindow;
  private ema: number | null = null;
  private smoothed: number | null = null;
  private target: number | null = null;
  private state: CadenceEngineState = "idle";
  private pendingSince: number | null = null;
  private lastSampleAt: number | null = null;
  private sampleCount = 0;
  private lastRaw: number | null = null;

  constructor(config: Partial<CadenceEngineConfig> = {}) {
    this.config = { ...DEFAULT_CADENCE_CONFIG, ...config };
    this.window = new RollingWindow(this.config.windowMs);
  }

  getState(): CadenceEngineState {
    return this.state;
  }

  getTarget(): number | null {
    return this.target;
  }

  getSmoothed(): number | null {
    return this.smoothed;
  }

  /** Feed one raw sample. Returns the resulting engine view. */
  addSample(sample: CadenceSample): CadenceEngineUpdate {
    const { config } = this;
    const now = sample.capturedAt;

    // Zero SPM is an explicit "no steps" signal.
    if (sample.spm <= 0) {
      this.lastSampleAt = now;
      return this.handleStop(now, "zero-cadence sample");
    }

    // Discard physically implausible readings entirely.
    if (sample.spm < config.minValidSpm || sample.spm > config.maxValidSpm) {
      return this.snapshot(now, null);
    }

    this.lastRaw = sample.spm;
    this.lastSampleAt = now;
    this.sampleCount += 1;
    this.window.push(now, sample.spm);

    // Median pre-filter kills single-sample spikes; EMA smooths the rest.
    const med = median(this.window.lastValues(config.medianWindow));
    this.ema = emaStep(this.ema, med, config.emaAlpha);
    this.smoothed = this.ema;

    let decision: CadenceDecision | null = null;

    if (this.state === "idle" || this.state === "stopped") {
      const wasStopped = this.state === "stopped";
      this.state = "acquiring";
      if (wasStopped) {
        decision = this.makeDecision(now, "resume", this.target, "cadence resumed after stop");
      }
    }

    if (this.state === "acquiring") {
      if (this.sampleCount >= config.minSamplesForLock && this.window.size() >= config.minSamplesForLock) {
        const locked = Math.round(this.smoothed);
        const prev = this.target;
        this.target = locked;
        this.state = "locked";
        this.pendingSince = null;
        decision = this.makeDecision(
          now,
          "initial_lock",
          prev,
          `locked initial cadence at ${locked} SPM after ${this.sampleCount} samples`,
        );
      }
      return this.snapshot(now, decision);
    }

    // state === "locked": hysteresis + sustained-change detection.
    const diff = this.smoothed - (this.target as number);
    if (Math.abs(diff) >= config.changeThresholdSpm) {
      if (this.pendingSince === null) {
        this.pendingSince = now;
      } else if (now - this.pendingSince >= config.sustainMs) {
        const prev = this.target;
        this.target = Math.round(this.smoothed);
        this.pendingSince = null;
        decision = this.makeDecision(
          now,
          "retarget",
          prev,
          `sustained change: smoothed ${this.smoothed.toFixed(1)} SPM vs target ${prev} SPM ` +
            `for ≥${(config.sustainMs / 1000).toFixed(0)}s`,
        );
      }
    } else {
      // Back inside the tolerance band — abandon any pending change.
      this.pendingSince = null;
    }

    return this.snapshot(now, decision);
  }

  /**
   * Advance wall time without a sample (drive from a UI interval).
   * Detects the "runner stopped producing samples" case.
   */
  tick(now: number): CadenceEngineUpdate {
    if (
      this.lastSampleAt !== null &&
      this.state !== "stopped" &&
      this.state !== "idle" &&
      now - this.lastSampleAt >= this.config.stopTimeoutMs
    ) {
      return this.handleStop(now, `no samples for ${this.config.stopTimeoutMs} ms`);
    }
    return this.snapshot(now, null);
  }

  reset(): void {
    this.window.clear();
    this.ema = null;
    this.smoothed = null;
    this.target = null;
    this.state = "idle";
    this.pendingSince = null;
    this.lastSampleAt = null;
    this.sampleCount = 0;
    this.lastRaw = null;
  }

  private handleStop(now: number, reason: string): CadenceEngineUpdate {
    let decision: CadenceDecision | null = null;
    if (this.state !== "stopped" && this.state !== "idle") {
      this.state = "stopped";
      this.pendingSince = null;
      this.window.clear();
      this.ema = null;
      this.smoothed = null;
      this.sampleCount = 0;
      // Keep `target` so music can hold tempo briefly; the orchestrator
      // decides whether to pause playback on stop.
      decision = this.makeDecision(now, "stop", this.target, reason);
    }
    return this.snapshot(now, decision);
  }

  private makeDecision(
    at: number,
    type: CadenceDecision["type"],
    previousTargetSpm: number | null,
    reason: string,
  ): CadenceDecision {
    return { at, type, targetSpm: this.target, previousTargetSpm, reason };
  }

  private snapshot(at: number, decision: CadenceDecision | null): CadenceEngineUpdate {
    return {
      at,
      rawSpm: this.lastRaw,
      smoothedSpm: this.smoothed,
      targetSpm: this.target,
      state: this.state,
      decision,
      pending:
        this.pendingSince !== null && this.smoothed !== null
          ? { candidateSpm: Math.round(this.smoothed), sinceMs: at - this.pendingSince }
          : null,
    };
  }
}
