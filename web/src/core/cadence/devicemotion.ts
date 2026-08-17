import type { CadenceSample } from "../shared/types";
import { BaseCadenceProvider } from "./provider";

/**
 * DeviceMotionCadenceProvider — EXPERIMENTAL.
 *
 * Estimates cadence from `devicemotion` accelerometer events using
 * peak detection on the acceleration magnitude:
 *
 *   1. magnitude = |a| of accelerationIncludingGravity
 *   2. high-pass via subtracting a slow EMA (removes gravity/baseline)
 *   3. a step = signal crossing above `peakThreshold` after having dropped
 *      below `resetThreshold`, with a refractory period (max ~4 steps/sec)
 *   4. SPM = step count in the rolling window, extrapolated to a minute
 *
 * Honest accuracy note: phone placement (hand vs pocket vs armband),
 * browser event throttling, and screen-lock suspension make this far less
 * reliable than native pedometer APIs (Core Motion). It is shipped behind
 * an "Experimental" flag and clearly labeled in the UI. The eventual iOS
 * native provider (docs/INTEGRATIONS.md) is the real answer.
 *
 * iOS Safari requires a user-gesture-triggered permission request
 * (`DeviceMotionEvent.requestPermission()`), handled in `start()`.
 */

export interface DeviceMotionConfig {
  /** Rolling step-count window, ms. */
  windowMs: number;
  /** Acceleration delta (m/s²) that counts as a step peak. */
  peakThreshold: number;
  /** Signal must fall below this before another peak can register. */
  resetThreshold: number;
  /** Minimum ms between steps (240 SPM ceiling). */
  refractoryMs: number;
  /** Baseline EMA alpha (slow). */
  baselineAlpha: number;
  /** Emit interval, ms. */
  emitIntervalMs: number;
}

export const DEFAULT_DEVICEMOTION_CONFIG: DeviceMotionConfig = {
  windowMs: 5000,
  peakThreshold: 1.8,
  resetThreshold: 0.6,
  refractoryMs: 250,
  baselineAlpha: 0.05,
  emitIntervalMs: 1000,
};

export class DeviceMotionCadenceProvider extends BaseCadenceProvider {
  readonly id = "devicemotion";
  readonly label = "Motion Sensor (experimental)";

  private config: DeviceMotionConfig;
  private stepTimes: number[] = [];
  private baseline: number | null = null;
  private armed = true;
  private lastStepAt = 0;
  private timer: ReturnType<typeof setInterval> | null = null;
  private handler = (e: DeviceMotionEvent) => this.onMotion(e);

  constructor(config: Partial<DeviceMotionConfig> = {}) {
    super();
    this.config = { ...DEFAULT_DEVICEMOTION_CONFIG, ...config };
  }

  static isSupported(): boolean {
    return typeof window !== "undefined" && "DeviceMotionEvent" in window;
  }

  async start(): Promise<void> {
    if (!DeviceMotionCadenceProvider.isSupported()) {
      throw new Error("DeviceMotion is not supported in this browser");
    }
    // iOS 13+ permission gate — must be called from a user gesture.
    const DME = DeviceMotionEvent as unknown as {
      requestPermission?: () => Promise<"granted" | "denied">;
    };
    if (typeof DME.requestPermission === "function") {
      const result = await DME.requestPermission();
      if (result !== "granted") {
        throw new Error("Motion sensor permission denied");
      }
    }
    window.addEventListener("devicemotion", this.handler);
    this.timer = setInterval(() => this.emitEstimate(), this.config.emitIntervalMs);
  }

  async stop(): Promise<void> {
    if (typeof window !== "undefined") {
      window.removeEventListener("devicemotion", this.handler);
    }
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.stepTimes = [];
    this.baseline = null;
  }

  /** Exposed for unit testing the detection math without real events. */
  processMagnitude(magnitude: number, at: number): void {
    this.baseline =
      this.baseline === null
        ? magnitude
        : this.baseline + this.config.baselineAlpha * (magnitude - this.baseline);
    const signal = magnitude - this.baseline;

    if (this.armed && signal > this.config.peakThreshold && at - this.lastStepAt >= this.config.refractoryMs) {
      this.stepTimes.push(at);
      this.lastStepAt = at;
      this.armed = false;
    } else if (!this.armed && signal < this.config.resetThreshold) {
      this.armed = true;
    }

    const cutoff = at - this.config.windowMs;
    while (this.stepTimes.length && this.stepTimes[0] < cutoff) this.stepTimes.shift();
  }

  private onMotion(e: DeviceMotionEvent): void {
    const a = e.accelerationIncludingGravity;
    if (!a || a.x === null || a.y === null || a.z === null) return;
    const magnitude = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    this.processMagnitude(magnitude, Date.now());
  }

  private emitEstimate(): void {
    const now = Date.now();
    const cutoff = now - this.config.windowMs;
    const steps = this.stepTimes.filter((t) => t >= cutoff).length;
    const spm = (steps * 60_000) / this.config.windowMs;
    const sample: CadenceSample = {
      capturedAt: now,
      spm: Math.round(spm),
      source: "devicemotion",
    };
    this.emit(sample);
  }
}
