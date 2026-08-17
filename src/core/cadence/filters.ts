/**
 * Pure signal-processing helpers used by the cadence engine.
 */

/** Median of an array of numbers. Returns NaN for an empty array. */
export function median(values: number[]): number {
  if (values.length === 0) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

/** Arithmetic mean. Returns NaN for an empty array. */
export function mean(values: number[]): number {
  if (values.length === 0) return NaN;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

/**
 * Exponential moving average step.
 * `alpha` in (0, 1]: higher = more responsive, lower = smoother.
 */
export function emaStep(previous: number | null, next: number, alpha: number): number {
  if (previous === null || Number.isNaN(previous)) return next;
  return previous + alpha * (next - previous);
}

/** A timestamped scalar reading. */
export interface TimedValue {
  t: number;
  value: number;
}

/**
 * Fixed-duration rolling window of timestamped values.
 * Values older than `windowMs` relative to the newest entry are evicted.
 */
export class RollingWindow {
  private buffer: TimedValue[] = [];

  constructor(private readonly windowMs: number) {}

  push(t: number, value: number): void {
    this.buffer.push({ t, value });
    this.evict(t);
  }

  /** Drop entries older than the window relative to `now`. */
  evict(now: number): void {
    const cutoff = now - this.windowMs;
    while (this.buffer.length > 0 && this.buffer[0].t < cutoff) {
      this.buffer.shift();
    }
  }

  values(): number[] {
    return this.buffer.map((v) => v.value);
  }

  /** The most recent `n` values (fewer if not available). */
  lastValues(n: number): number[] {
    return this.buffer.slice(-n).map((v) => v.value);
  }

  size(): number {
    return this.buffer.length;
  }

  newestTimestamp(): number | null {
    return this.buffer.length ? this.buffer[this.buffer.length - 1].t : null;
  }

  clear(): void {
    this.buffer = [];
  }
}
