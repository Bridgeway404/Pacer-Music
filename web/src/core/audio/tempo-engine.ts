/**
 * TempoEngine — abstraction over anything that can play audio at a
 * controllable tempo. Implementations:
 *
 *  - ProceduralBeatEngine: synthesizes a beat in real time with Web Audio.
 *    Tempo is exact and ramps are perfectly smooth. Zero licensing issues.
 *  - FileTempoEngine: plays an audio file (bundled demo audio or a
 *    user-uploaded file) through an HTMLMediaElement, using `playbackRate`
 *    with `preservesPitch` for pitch-preserving time-stretch where the
 *    browser supports it.
 *
 * A more sophisticated DSP time-stretch (phase vocoder, e.g. SoundTouch)
 * can be slotted in behind this same interface later.
 */

export type TempoEngineState = "idle" | "loading" | "playing" | "paused" | "stopped";

export interface TempoEngineStatus {
  state: TempoEngineState;
  /** BPM of the source material (null when unknown/not applicable). */
  sourceBpm: number | null;
  /** BPM the engine is currently ramping toward. */
  targetBpm: number | null;
  /** BPM actually sounding right now (mid-ramp values included). */
  currentBpm: number | null;
  /** currentBpm / sourceBpm, i.e. effective playback-rate multiplier. */
  playbackRate: number;
  /** Whether the implementation preserves pitch while shifting tempo. */
  pitchPreserved: boolean;
}

export interface TempoEngine {
  readonly id: string;
  readonly label: string;

  /** Prepare audio (decode file, build graph). Safe to call repeatedly. */
  load(): Promise<void>;
  play(): Promise<void>;
  pause(): void;
  stop(): void;
  /**
   * Ramp the audible tempo toward `bpm` over `rampMs` (default implementation
   * choice). Values are clamped to a sane playable range by implementations.
   */
  setTargetBpm(bpm: number, rampMs?: number): void;
  getStatus(): TempoEngineStatus;
  /** Subscribe to status changes; returns unsubscribe. */
  subscribe(cb: (status: TempoEngineStatus) => void): () => void;
  /** Beat callback for UI pulse visualization (best effort). */
  onBeat?(cb: (beatNumber: number) => void): () => void;
  dispose(): void;
}
