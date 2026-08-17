import type { CadenceSample } from "../shared/types";

/**
 * Anything that can produce cadence samples: a simulator, tap input,
 * DeviceMotion step detection, or an eventual native (iOS/watch) bridge.
 *
 * Providers push samples; they never decide what the music should do.
 * All smoothing/decision logic lives in {@link CadenceEngine}.
 */
export interface CadenceProvider {
  /** Stable identifier, e.g. "simulator". */
  readonly id: string;
  /** Human label for diagnostics UI. */
  readonly label: string;
  start(): Promise<void>;
  stop(): Promise<void>;
  /** Subscribe to samples. Returns an unsubscribe function. */
  subscribe(callback: (sample: CadenceSample) => void): () => void;
}

/** Small helper base class implementing the subscriber list. */
export abstract class BaseCadenceProvider implements CadenceProvider {
  abstract readonly id: string;
  abstract readonly label: string;
  private subscribers = new Set<(sample: CadenceSample) => void>();

  abstract start(): Promise<void>;
  abstract stop(): Promise<void>;

  subscribe(callback: (sample: CadenceSample) => void): () => void {
    this.subscribers.add(callback);
    return () => this.subscribers.delete(callback);
  }

  protected emit(sample: CadenceSample): void {
    for (const cb of this.subscribers) cb(sample);
  }
}
