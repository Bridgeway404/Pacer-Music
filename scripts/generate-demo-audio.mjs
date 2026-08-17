#!/usr/bin/env node
/**
 * Generates the bundled demo audio loops (public/audio/demo-<bpm>.wav).
 *
 * Every sample is synthesized here — kick, snare, hats, bass — so the
 * project owns these recordings outright and Pacer may legally tempo-shift
 * them. Loops are exact bar multiples for seamless looping.
 *
 * Usage: node scripts/generate-demo-audio.mjs
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const SAMPLE_RATE = 22050;
const BPMS = [82, 120, 140, 150, 160, 170, 180];
const BARS = 8; // 8 bars of 4/4 per loop

const outDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public", "audio");
mkdirSync(outDir, { recursive: true });

/** Deterministic PRNG so generated files are reproducible. */
function mulberry32(seed) {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generateLoop(bpm) {
  const secondsPerBeat = 60 / bpm;
  const totalBeats = BARS * 4;
  const totalSamples = Math.round(totalBeats * secondsPerBeat * SAMPLE_RATE);
  const data = new Float64Array(totalSamples);
  const rand = mulberry32(bpm * 7919);

  const addKick = (startS) => {
    const dur = 0.22;
    const n = Math.min(totalSamples, Math.round((startS + dur) * SAMPLE_RATE));
    for (let i = Math.round(startS * SAMPLE_RATE); i < n; i++) {
      const t = i / SAMPLE_RATE - startS;
      const freq = 140 * Math.exp(-t * 22) + 42;
      const env = Math.exp(-t * 18);
      data[i] += 0.85 * env * Math.sin(2 * Math.PI * freq * t);
    }
  };

  const addSnare = (startS) => {
    const dur = 0.12;
    const n = Math.min(totalSamples, Math.round((startS + dur) * SAMPLE_RATE));
    let hp = 0;
    for (let i = Math.round(startS * SAMPLE_RATE); i < n; i++) {
      const t = i / SAMPLE_RATE - startS;
      const env = Math.exp(-t * 30);
      const noise = rand() * 2 - 1;
      hp = 0.7 * hp + 0.3 * noise; // crude low-pass; subtract for high-pass
      data[i] += 0.4 * env * (noise - hp) + 0.15 * env * Math.sin(2 * Math.PI * 190 * t);
    }
  };

  const addHat = (startS, level) => {
    const dur = 0.04;
    const n = Math.min(totalSamples, Math.round((startS + dur) * SAMPLE_RATE));
    let prev = 0;
    for (let i = Math.round(startS * SAMPLE_RATE); i < n; i++) {
      const t = i / SAMPLE_RATE - startS;
      const env = Math.exp(-t * 90);
      const noise = rand() * 2 - 1;
      const highpassed = noise - prev; // 1st-order high-pass
      prev = noise;
      data[i] += level * env * highpassed;
    }
  };

  const addBass = (startS, freq, durBeats) => {
    const dur = secondsPerBeat * durBeats * 0.9;
    const n = Math.min(totalSamples, Math.round((startS + dur) * SAMPLE_RATE));
    for (let i = Math.round(startS * SAMPLE_RATE); i < n; i++) {
      const t = i / SAMPLE_RATE - startS;
      const env = Math.min(1, t * 60) * Math.exp(-t * 2.2);
      // Saw-ish via two detuned squares, mellowed with a fixed low-pass feel.
      const s1 = Math.sign(Math.sin(2 * Math.PI * freq * t));
      const s2 = Math.sign(Math.sin(2 * Math.PI * freq * 1.005 * t));
      const sub = Math.sin(2 * Math.PI * (freq / 2) * t);
      data[i] += env * (0.10 * s1 + 0.08 * s2 + 0.16 * sub);
    }
  };

  // A minor-ish two-bar bass pattern (root, root, b3, 5), repeated.
  const bassPattern = [55.0, 55.0, 65.4, 82.4];

  for (let beat = 0; beat < totalBeats; beat++) {
    const t = beat * secondsPerBeat;
    const inBar = beat % 4;
    addKick(t);
    if (inBar === 1 || inBar === 3) addSnare(t);
    addHat(t, 0.22);
    addHat(t + secondsPerBeat / 2, 0.12);
    if (inBar === 0 || inBar === 2) {
      addBass(t, bassPattern[(Math.floor(beat / 4) + inBar / 2) % 4], 2);
    }
  }

  // Normalize with light headroom.
  let peak = 0;
  for (const v of data) peak = Math.max(peak, Math.abs(v));
  const gain = peak > 0 ? 0.89 / peak : 1;
  const pcm = new Int16Array(totalSamples);
  for (let i = 0; i < totalSamples; i++) {
    pcm[i] = Math.max(-32768, Math.min(32767, Math.round(data[i] * gain * 32767)));
  }
  return pcm;
}

function writeWav(path, pcm) {
  const dataSize = pcm.length * 2;
  const buffer = Buffer.alloc(44 + dataSize);
  buffer.write("RIFF", 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write("WAVE", 8);
  buffer.write("fmt ", 12);
  buffer.writeUInt32LE(16, 16); // PCM chunk size
  buffer.writeUInt16LE(1, 20); // PCM format
  buffer.writeUInt16LE(1, 22); // mono
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(SAMPLE_RATE * 2, 28); // byte rate
  buffer.writeUInt16LE(2, 32); // block align
  buffer.writeUInt16LE(16, 34); // bits per sample
  buffer.write("data", 36);
  buffer.writeUInt32LE(dataSize, 40);
  Buffer.from(pcm.buffer, pcm.byteOffset, dataSize).copy(buffer, 44);
  writeFileSync(path, buffer);
}

for (const bpm of BPMS) {
  const pcm = generateLoop(bpm);
  const file = join(outDir, `demo-${bpm}.wav`);
  writeWav(file, pcm);
  console.log(`wrote ${file} (${(pcm.length * 2 / 1024 / 1024).toFixed(2)} MB, ${bpm} BPM)`);
}
