import type { CadenceSample } from "../shared/types";
import { BaseCadenceProvider } from "./provider";

/**
 * SimulatedCadenceProvider — a realistic fake runner for development & Demo Mode.
 *
 * - Holds a target SPM and drifts toward it at a configurable ramp rate,
 *   so pace changes are gradual like a real runner's.
 * - Adds gaussian-ish noise per sample so the smoothing engine has real work.
 * - `setTargetSpm(0)` simulates stopping (emits zero-cadence samples).
 */

export interface SimulatorConfig {
  /** Emit interval in ms. */
  intervalMs: number;
  /** Standard deviation of per-sample noise, SPM. */
  noiseSpm: number;
  /** Max SPM change per second while ramping toward the target. */
  rampSpmPerSecond: number;
  /** Initial cadence. */
  initialSpm: number;
}

export const DEFAULT_SIMULATOR_CONFIG: SimulatorConfig = {
  intervalMs: 600,
  noiseSpm: 2,
  rampSpmPerSecond: 2.5,
  initialSpm: 154,
};

export class SimulatedCadenceProvider extends BaseCadenceProvider {
  readonly id = "simulator";
  readonly label = "Cadence Simulator";

  private config: SimulatorConfig;
  private currentSpm: number;
  private targetSpm: number;
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(config: Partial<SimulatorConfig> = {}) {
    super();
    this.config = { ...DEFAULT_SIMULATOR_CONFIG, ...config };
    this.currentSpm = this.config.initialSpm;
    this.targetSpm = this.config.initialSpm;
  }

  /** Where the simulated runner is trying to be. 0 = stop running. */
  setTargetSpm(spm: number): void {
    this.targetSpm = spm;
  }

  getTargetSpm(): number {
    return this.targetSpm;
  }

  getCurrentSpm(): number {
    return this.currentSpm;
  }

  /** Instantly jump (useful for tests/demos of spikes). */
  jumpTo(spm: number): void {
    this.currentSpm = spm;
    this.targetSpm = spm;
  }

  async start(): Promise<void> {
    if (this.timer) return;
    this.timer = setInterval(() => this.step(), this.config.intervalMs);
  }

  async stop(): Promise<void> {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private step(): void {
    const { intervalMs, rampSpmPerSecond, noiseSpm } = this.config;
    const maxDelta = (rampSpmPerSecond * intervalMs) / 1000;
    const delta = this.targetSpm - this.currentSpm;
    this.currentSpm += Math.abs(delta) <= maxDelta ? delta : Math.sign(delta) * maxDelta;

    let spm = 0;
    if (this.targetSpm > 0 || this.currentSpm > 1) {
      // Sum of two uniforms ≈ triangular noise, good enough for a fake runner.
      const noise = (Math.random() + Math.random() - 1) * noiseSpm * 1.6;
      spm = Math.max(0, this.currentSpm + noise);
    } else {
      this.currentSpm = 0;
    }

    const sample: CadenceSample = {
      capturedAt: Date.now(),
      spm: Math.round(spm * 10) / 10,
      source: "simulator",
    };
    this.emit(sample);
  }
}
