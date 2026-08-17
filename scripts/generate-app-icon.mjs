#!/usr/bin/env node
/**
 * Generates the placeholder Pacer app icon (1024×1024 PNG): a beat-pulse
 * equalizer in pace-green on deep navy. Pure Node (zlib) — no dependencies.
 *
 * Usage: node scripts/generate-app-icon.mjs
 */
import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const SIZE = 1024;

function crc32(buf) {
  let table = crc32.table;
  if (!table) {
    table = crc32.table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c;
    }
  }
  let crc = -1;
  for (const b of buf) crc = (crc >>> 8) ^ table[(crc ^ b) & 0xff];
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

// Pixel painting -------------------------------------------------------------
const px = new Uint8Array(SIZE * SIZE * 3);

function setPx(x, y, r, g, b) {
  const i = (y * SIZE + x) * 3;
  px[i] = r;
  px[i + 1] = g;
  px[i + 2] = b;
}

// Background: vertical navy gradient.
for (let y = 0; y < SIZE; y++) {
  const t = y / SIZE;
  const r = Math.round(10 + 8 * t);
  const g = Math.round(13 + 10 * t);
  const b = Math.round(28 + 18 * t);
  for (let x = 0; x < SIZE; x++) setPx(x, y, r, g, b);
}

// Beat-pulse bars (symmetric equalizer around the vertical center).
const bars = [0.28, 0.5, 0.82, 0.62, 1.0, 0.62, 0.82, 0.5, 0.28];
const barWidth = 56;
const gap = 34;
const totalWidth = bars.length * barWidth + (bars.length - 1) * gap;
const startX = Math.round((SIZE - totalWidth) / 2);
const maxHalf = 300;

for (let i = 0; i < bars.length; i++) {
  const half = Math.round(maxHalf * bars[i]);
  const x0 = startX + i * (barWidth + gap);
  for (let y = 512 - half; y <= 512 + half; y++) {
    for (let x = x0; x < x0 + barWidth; x++) {
      // Rounded caps.
      const dyTop = y - (512 - half + barWidth / 2);
      const dyBot = y - (512 + half - barWidth / 2);
      const cx = x - (x0 + barWidth / 2);
      const inTop = y >= 512 - half + barWidth / 2 || cx * cx + dyTop * dyTop <= (barWidth / 2) ** 2;
      const inBot = y <= 512 + half - barWidth / 2 || cx * cx + dyBot * dyBot <= (barWidth / 2) ** 2;
      if (inTop && inBot) {
        // Pace green with subtle vertical shading.
        const shade = 1 - Math.abs(y - 512) / (maxHalf * 1.6);
        setPx(x, y, Math.round(92 * shade + 20), Math.round(242 * shade + 13), Math.round(168 * shade + 15));
      }
    }
  }
}

// PNG assembly ---------------------------------------------------------------
const raw = Buffer.alloc(SIZE * (SIZE * 3 + 1));
for (let y = 0; y < SIZE; y++) {
  raw[y * (SIZE * 3 + 1)] = 0; // filter: none
  Buffer.from(px.buffer, y * SIZE * 3, SIZE * 3).copy(raw, y * (SIZE * 3 + 1) + 1);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0);
ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8; // bit depth
ihdr[9] = 2; // color type: truecolor
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

const out = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "ios/Pacer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
);
writeFileSync(out, png);
console.log(`wrote ${out} (${(png.length / 1024).toFixed(0)} KB)`);
