import type { TempoEngine, TempoEngineState, TempoEngineStatus } from "./tempo-engine";

/**
 * FileTempoEngine — plays an audio file whose BPM we know, shifting tempo
 * via HTMLMediaElement.playbackRate.
 *
 * `preservesPitch = true` (supported in all modern evergreen browsers) gives
 * browser-native pitch-preserving time-stretch. Where unsupported, the audio
 * simply pitch-shifts with rate — clearly reported via `pitchPreserved`.
 *
 * ONLY for audio we are permitted to manipulate: the bundled synthesized
 * demo loops, or files the user uploads and represents they may use.
 * Never used for DRM/streaming content.
 */

export interface FileTempoEngineOptions {
  url: string;
  sourceBpm: number;
  loop?: boolean;
  /** Clamp for playback rate (musical sanity + browser limits). */
  minRate?: number;
  maxRate?: number;
}

export class FileTempoEngine implements TempoEngine {
  readonly id = "file";
  readonly label = "File playback (playbackRate)";

  private audio: HTMLAudioElement | null = null;
  private state: TempoEngineState = "idle";
  private sourceBpm: number;
  private targetBpm: number;
  private currentBpm: number;
  private rampTimer: ReturnType<typeof setInterval> | null = null;
  private beatTimer: ReturnType<typeof setInterval> | null = null;
  private beatNumber = 0;
  private subscribers = new Set<(s: TempoEngineStatus) => void>();
  private beatSubscribers = new Set<(n: number) => void>();
  private readonly opts: Required<FileTempoEngineOptions>;

  constructor(options: FileTempoEngineOptions) {
    this.opts = {
      loop: true,
      minRate: 0.6,
      maxRate: 1.6,
      ...options,
    };
    this.sourceBpm = options.sourceBpm;
    this.targetBpm = options.sourceBpm;
    this.currentBpm = options.sourceBpm;
  }

  async load(): Promise<void> {
    if (this.audio) return;
    this.state = "loading";
    this.notify();
    const audio = new Audio(this.opts.url);
    audio.loop = this.opts.loop;
    audio.preload = "auto";
    // Pitch preservation flag (standard + legacy vendor property).
    audio.preservesPitch = true;
    (audio as HTMLAudioElement & { mozPreservesPitch?: boolean }).mozPreservesPitch = true;
    this.audio = audio;
    await new Promise<void>((resolve, reject) => {
      audio.addEventListener("canplaythrough", () => resolve(), { once: true });
      audio.addEventListener("error", () => reject(new Error(`Failed to load ${this.opts.url}`)), {
        once: true,
      });
      audio.load();
    });
    this.state = "paused";
    this.notify();
  }

  async play(): Promise<void> {
    await this.load();
    if (!this.audio) return;
    await this.audio.play();
    this.state = "playing";
    this.applyRate();
    this.startBeatClock();
    this.notify();
  }

  pause(): void {
    this.audio?.pause();
    this.state = "paused";
    this.stopBeatClock();
    this.notify();
  }

  stop(): void {
    if (this.audio) {
      this.audio.pause();
      this.audio.currentTime = 0;
    }
    this.state = "stopped";
    this.stopBeatClock();
    this.notify();
  }

  setTargetBpm(bpm: number, rampMs = 2500): void {
    const minBpm = this.sourceBpm * this.opts.minRate;
    const maxBpm = this.sourceBpm * this.opts.maxRate;
    this.targetBpm = Math.min(maxBpm, Math.max(minBpm, bpm));

    if (this.rampTimer) clearInterval(this.rampTimer);
    const stepMs = 80;
    const start = this.currentBpm;
    const delta = this.targetBpm - start;
    if (Math.abs(delta) < 0.1 || rampMs <= 0) {
      this.currentBpm = this.targetBpm;
      this.applyRate();
      this.notify();
      return;
    }
    const steps = Math.max(1, Math.round(rampMs / stepMs));
    let step = 0;
    this.rampTimer = setInterval(() => {
      step += 1;
      // Ease-in-out for a musical, non-jarring transition.
      const t = step / steps;
      const eased = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      this.currentBpm = start + delta * eased;
      this.applyRate();
      this.notify();
      if (step >= steps) {
        this.currentBpm = this.targetBpm;
        this.applyRate();
        if (this.rampTimer) clearInterval(this.rampTimer);
        this.rampTimer = null;
        this.notify();
      }
    }, stepMs);
  }

  getStatus(): TempoEngineStatus {
    return {
      state: this.state,
      sourceBpm: this.sourceBpm,
      targetBpm: this.targetBpm,
      currentBpm: this.currentBpm,
      playbackRate: this.currentBpm / this.sourceBpm,
      pitchPreserved:
        this.audio != null &&
        typeof this.audio.preservesPitch === "boolean" &&
        this.audio.preservesPitch,
    };
  }

  subscribe(cb: (status: TempoEngineStatus) => void): () => void {
    this.subscribers.add(cb);
    return () => this.subscribers.delete(cb);
  }

  onBeat(cb: (beatNumber: number) => void): () => void {
    this.beatSubscribers.add(cb);
    return () => this.beatSubscribers.delete(cb);
  }

  dispose(): void {
    this.stop();
    if (this.rampTimer) clearInterval(this.rampTimer);
    this.audio?.removeAttribute("src");
    this.audio?.load();
    this.audio = null;
    this.subscribers.clear();
    this.beatSubscribers.clear();
    this.state = "idle";
  }

  private applyRate(): void {
    if (!this.audio) return;
    this.audio.playbackRate = this.currentBpm / this.sourceBpm;
  }

  private startBeatClock(): void {
    this.stopBeatClock();
    const tick = () => {
      this.beatNumber += 1;
      for (const cb of this.beatSubscribers) cb(this.beatNumber);
      this.beatTimer = setTimeout(tick, 60_000 / Math.max(40, this.currentBpm)) as unknown as ReturnType<
        typeof setInterval
      >;
    };
    this.beatTimer = setTimeout(tick, 60_000 / Math.max(40, this.currentBpm)) as unknown as ReturnType<
      typeof setInterval
    >;
  }

  private stopBeatClock(): void {
    if (this.beatTimer) {
      clearTimeout(this.beatTimer as unknown as number);
      this.beatTimer = null;
    }
  }

  private notify(): void {
    const status = this.getStatus();
    for (const cb of this.subscribers) cb(status);
  }
}
