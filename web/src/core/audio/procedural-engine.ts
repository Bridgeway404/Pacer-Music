import type { TempoEngine, TempoEngineState, TempoEngineStatus } from "./tempo-engine";

/**
 * ProceduralBeatEngine — synthesizes a running beat in real time with the
 * Web Audio API (kick / snare / hats / bass, scheduled ahead of time).
 *
 * Because the audio is generated, tempo is *exact* and can glide smoothly
 * to any BPM with no artifacts — the purest demonstration of Pacer's
 * cadence-to-music loop, with zero licensing constraints.
 */

const LOOKAHEAD_MS = 25;
const SCHEDULE_AHEAD_S = 0.12;

export class ProceduralBeatEngine implements TempoEngine {
  readonly id = "procedural";
  readonly label = "Synth beat (Web Audio)";

  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private state: TempoEngineState = "idle";
  private currentBpm = 150;
  private targetBpm = 150;
  private rampPerTick = 0;
  private nextBeatTime = 0;
  private beatNumber = 0;
  private schedulerTimer: ReturnType<typeof setInterval> | null = null;
  private subscribers = new Set<(s: TempoEngineStatus) => void>();
  private beatSubscribers = new Set<(n: number) => void>();

  constructor(initialBpm = 150) {
    this.currentBpm = initialBpm;
    this.targetBpm = initialBpm;
  }

  async load(): Promise<void> {
    if (this.ctx) return;
    const Ctx =
      window.AudioContext ??
      (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctx) throw new Error("Web Audio API not supported");
    this.ctx = new Ctx();
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.7;
    this.master.connect(this.ctx.destination);
    this.state = "paused";
    this.notify();
  }

  async play(): Promise<void> {
    await this.load();
    if (!this.ctx) return;
    if (this.ctx.state === "suspended") await this.ctx.resume();
    if (this.state === "playing") return;
    this.state = "playing";
    this.nextBeatTime = this.ctx.currentTime + 0.06;
    this.schedulerTimer = setInterval(() => this.schedule(), LOOKAHEAD_MS);
    this.notify();
  }

  pause(): void {
    if (this.schedulerTimer) clearInterval(this.schedulerTimer);
    this.schedulerTimer = null;
    this.ctx?.suspend();
    this.state = "paused";
    this.notify();
  }

  stop(): void {
    if (this.schedulerTimer) clearInterval(this.schedulerTimer);
    this.schedulerTimer = null;
    this.beatNumber = 0;
    this.ctx?.suspend();
    this.state = "stopped";
    this.notify();
  }

  setTargetBpm(bpm: number, rampMs = 3000): void {
    this.targetBpm = Math.min(220, Math.max(60, bpm));
    // Glide: distribute the BPM delta over the ramp window; applied per beat.
    const delta = this.targetBpm - this.currentBpm;
    const beats = Math.max(1, (rampMs / 60_000) * this.currentBpm);
    this.rampPerTick = delta / beats;
    this.notify();
  }

  getStatus(): TempoEngineStatus {
    return {
      state: this.state,
      sourceBpm: null, // synthesized — there is no fixed source tempo
      targetBpm: this.targetBpm,
      currentBpm: this.currentBpm,
      playbackRate: 1,
      pitchPreserved: true,
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
    this.ctx?.close();
    this.ctx = null;
    this.master = null;
    this.subscribers.clear();
    this.beatSubscribers.clear();
    this.state = "idle";
  }

  private schedule(): void {
    if (!this.ctx || this.state !== "playing") return;
    while (this.nextBeatTime < this.ctx.currentTime + SCHEDULE_AHEAD_S) {
      this.playBeat(this.beatNumber, this.nextBeatTime);
      const secondsPerBeat = 60 / this.currentBpm;
      this.nextBeatTime += secondsPerBeat;
      this.beatNumber += 1;

      // Glide toward the target tempo, one small step per beat.
      if (Math.abs(this.targetBpm - this.currentBpm) > Math.abs(this.rampPerTick)) {
        this.currentBpm += this.rampPerTick;
      } else {
        this.currentBpm = this.targetBpm;
      }
      const captured = this.beatNumber;
      const delayMs = Math.max(0, (this.nextBeatTime - this.ctx.currentTime) * 1000 - 20);
      setTimeout(() => {
        for (const cb of this.beatSubscribers) cb(captured);
      }, delayMs);
    }
    this.notify();
  }

  private playBeat(beat: number, time: number): void {
    if (!this.ctx || !this.master) return;
    const inBar = beat % 4;

    // Kick on every beat — the runner's footfall anchor.
    this.kick(time);
    // Snare on 2 and 4.
    if (inBar === 1 || inBar === 3) this.snare(time);
    // Hats on 8ths.
    this.hat(time, 0.5);
    this.hat(time + 30 / this.currentBpm, 0.25);
    // Simple bassline: root–root–fifth–octave pattern per bar.
    const bassNotes = [55, 55, 82.4, 110];
    this.bass(time, bassNotes[inBar]);
  }

  private kick(time: number): void {
    if (!this.ctx || !this.master) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.frequency.setValueAtTime(150, time);
    osc.frequency.exponentialRampToValueAtTime(45, time + 0.1);
    gain.gain.setValueAtTime(1, time);
    gain.gain.exponentialRampToValueAtTime(0.001, time + 0.25);
    osc.connect(gain).connect(this.master);
    osc.start(time);
    osc.stop(time + 0.26);
  }

  private snare(time: number): void {
    if (!this.ctx || !this.master) return;
    const bufferSize = this.ctx.sampleRate * 0.12;
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / bufferSize);
    const noise = this.ctx.createBufferSource();
    noise.buffer = buffer;
    const filter = this.ctx.createBiquadFilter();
    filter.type = "highpass";
    filter.frequency.value = 1400;
    const gain = this.ctx.createGain();
    gain.gain.setValueAtTime(0.5, time);
    gain.gain.exponentialRampToValueAtTime(0.001, time + 0.12);
    noise.connect(filter).connect(gain).connect(this.master);
    noise.start(time);
  }

  private hat(time: number, level: number): void {
    if (!this.ctx || !this.master) return;
    const bufferSize = this.ctx.sampleRate * 0.04;
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / bufferSize);
    const noise = this.ctx.createBufferSource();
    noise.buffer = buffer;
    const filter = this.ctx.createBiquadFilter();
    filter.type = "highpass";
    filter.frequency.value = 7000;
    const gain = this.ctx.createGain();
    gain.gain.setValueAtTime(0.18 * level, time);
    gain.gain.exponentialRampToValueAtTime(0.001, time + 0.04);
    noise.connect(filter).connect(gain).connect(this.master);
    noise.start(time);
  }

  private bass(time: number, freq: number): void {
    if (!this.ctx || !this.master) return;
    const osc = this.ctx.createOscillator();
    osc.type = "sawtooth";
    const filter = this.ctx.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.value = 320;
    const gain = this.ctx.createGain();
    const secondsPerBeat = 60 / this.currentBpm;
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.22, time);
    gain.gain.exponentialRampToValueAtTime(0.001, time + secondsPerBeat * 0.85);
    osc.connect(filter).connect(gain).connect(this.master);
    osc.start(time);
    osc.stop(time + secondsPerBeat * 0.9);
  }

  private notify(): void {
    const status = this.getStatus();
    for (const cb of this.subscribers) cb(status);
  }
}
