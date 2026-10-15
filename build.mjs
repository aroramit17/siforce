// Bundles the extension into dist/. Load dist/ as an unpacked extension.
//   npm run build        one-off build
//   npm run watch        rebuild on change

import * as esbuild from 'esbuild';
import { copyFile, mkdir, rm, writeFile } from 'node:fs/promises';
import { deflateSync } from 'node:zlib';

const watch = process.argv.includes('--watch');
const out = 'dist';

await rm(out, { recursive: true, force: true });
await mkdir(`${out}/icons`, { recursive: true });

const common = { bundle: true, target: 'chrome120', logLevel: 'info', legalComments: 'none' };
const builds = [
  { ...common, entryPoints: ['src/background/index.js'], outfile: `${out}/background.js`, format: 'esm', platform: 'browser' },
  { ...common, entryPoints: ['src/content/content.js'], outfile: `${out}/content.js`, format: 'iife', loader: { '.css': 'text' } },
  { ...common, entryPoints: ['src/options/options.js'], outfile: `${out}/options.js`, format: 'esm' },
];

for (const file of ['manifest.json', 'options/options.html', 'options/options.css']) {
  await copyFile(`src/${file}`, `${out}/${file.split('/').pop()}`);
}
for (const size of [16, 32, 48, 128]) await writeFile(`${out}/icons/${size}.png`, drawIcon(size));

if (watch) {
  for (const b of builds) await (await esbuild.context(b)).watch();
} else {
  await Promise.all(builds.map((b) => esbuild.build(b)));
}

// ---------- Icon: white microphone on a violet-to-blue rounded square ----------

function drawIcon(size) {
  const px = Buffer.alloc(size * size * 4);
  const ss = 4; // supersampling for smooth edges
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let bg = 0, fg = 0;
      for (let sy = 0; sy < ss; sy++) {
        for (let sx = 0; sx < ss; sx++) {
          const u = (x + (sx + 0.5) / ss) / size * 2 - 1; // -1..1
          const v = (y + (sy + 0.5) / ss) / size * 2 - 1;
          if (roundedSquare(u, v, 0.92, 0.42) <= 0) {
            bg++;
            if (mic(u, v)) fg++;
          }
        }
      }
      const n = ss * ss;
      const t = (x + y) / (2 * size);
      const base = [91 + (11 - 91) * t, 76 + (122 - 76) * t, 224]; // #5b4ce0 -> #0b7ae0
      const f = fg / Math.max(bg, 1);
      const i = (y * size + x) * 4;
      px[i] = base[0] + (255 - base[0]) * f;
      px[i + 1] = base[1] + (255 - base[1]) * f;
      px[i + 2] = base[2] + (255 - base[2]) * f;
      px[i + 3] = (bg / n) * 255;
    }
  }
  return encodePng(size, size, px);
}

function roundedSquare(u, v, half, r) {
  const qx = Math.abs(u) - (half - r), qy = Math.abs(v) - (half - r);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
}

function mic(u, v) {
  const w = 0.075; // stroke half-width
  // capsule body
  const cy = Math.max(-0.42, Math.min(0.02, v));
  if (Math.hypot(u, v - cy) <= 0.2) return true;
  // U-shaped holder: lower half of a ring centred at (0, 0.02)
  const d = Math.hypot(u, v - 0.02);
  if (v >= 0.02 && Math.abs(d - 0.36) <= w) return true;
  if (v >= -0.1 && v < 0.02 && Math.abs(Math.abs(u) - 0.36) <= w) return true;
  // stem and foot
  if (Math.abs(u) <= w && v >= 0.38 && v <= 0.6) return true;
  if (Math.abs(u) <= 0.24 && Math.abs(v - 0.6) <= w) return true;
  return false;
}

function encodePng(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr.set([8, 6, 0, 0, 0], 8); // 8-bit RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function crc32(buf) {
  let c = ~0;
  for (const b of buf) {
    c ^= b;
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}
