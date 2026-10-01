import {mkdirSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

// Original 120 BPM electronic groove. Every sound is synthesized, without samples.
const sampleRate = 48000;
const duration = 20;
const length = sampleRate * duration;
const left = new Float32Array(length), right = new Float32Array(length);
let seed = 20260930;
const noise = () => {seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 2147483648 - 1;};
const freq = n => 440 * 2 ** ((n - 69) / 12);
const mix = (at, seconds, sound, gain = 1, pan = 0) => {
  const start = Math.round(at * sampleRate), count = Math.min(Math.floor(seconds * sampleRate), length - start);
  for (let i = 0; i < count; i++) {
    const value = sound(i / sampleRate, i) * Math.min(1, (count - i) / 300);
    left[start + i] += value * gain * Math.sqrt((1 - pan) / 2);
    right[start + i] += value * gain * Math.sqrt((1 + pan) / 2);
  }
};
const chords = [[50, 57, 60, 65], [46, 53, 57, 62], [53, 60, 64, 69], [48, 55, 58, 62]];
for (let bar = 0; bar < 5; bar++) {
  for (const [k, n] of chords[bar % 4].entries()) {
    const hz = freq(n);
    mix(bar * 4, 4.8, t => {
      const duck = t + bar * 4 >= 3 ? .48 + .52 * (1 - Math.exp(-((t + bar * 4 - 3) % .5) * 12)) : 1;
      return (1 - Math.exp(-t * 5)) * Math.exp(-t * .45) * duck * (Math.sin(2 * Math.PI * hz * t) + .2 * Math.sin(2 * Math.PI * hz * 1.004 * t));
    }, .052, (k - 1.5) * .4);
  }
}
// Short syncopated plucks build momentum before the first full beat.
const pattern = [0, 7, 12, 15, 7, 12, 19, 15];
for (let step = 0; step < 152; step++) {
  const at = .5 + step * .125;
  if (at > 19.2 || step % 8 === 5 || step % 8 === 6) continue;
  const root = chords[Math.floor(at / 4) % 4][0], hz = freq(root + 12 + pattern[step % 8]);
  const accent = step % 4 === 0 ? 1 : .54;
  mix(at, .45, t => (1 - Math.exp(-t * 500)) * Math.exp(-t * 15) * (Math.sin(2 * Math.PI * hz * t) + .18 * Math.sin(2 * Math.PI * hz * 2 * t) + .1 * Math.sin(2 * Math.PI * hz * 3 * t)), (at < 3 ? .045 : .085) * accent, Math.sin(step * 1.7) * .5);
}
for (let beat = 0; beat < 33; beat++) {
  const at = 3 + beat * .5;
  const energy = at >= 15.5 ? .8 : 1;
  mix(at, .48, t => Math.sin(2 * Math.PI * (46 * t + 115 * .021 * (1 - Math.exp(-t / .021)))) * Math.exp(-t * 11) + noise() * Math.exp(-t * 240) * .09, .67 * energy);
  const hz = freq(chords[Math.floor(at / 4) % 4][0] - 12);
  for (const offset of [.25, ...(beat % 4 === 2 ? [.375] : [])]) {
    mix(at + offset, .24, t => {
      const envelope = Math.min(1, t * 700) * Math.exp(-t * 11);
      let wave = Math.sin(2 * Math.PI * hz * t);
      for (let harmonic = 2; harmonic <= 6; harmonic++) wave += Math.sin(2 * Math.PI * hz * harmonic * t) * Math.exp(-t * harmonic * 9) * .22 / harmonic;
      return Math.tanh(wave * 1.7) * envelope;
    }, .23 * energy);
  }
  if (beat % 2 === 1) {
    for (const offset of [0, .012, .023]) {
      let low = 0;
      mix(at + offset, .14, t => {const n = noise(); low = low * .72 + n * .28; return (n - low) * Math.exp(-t * 28);}, .115 * energy, -.12);
    }
    mix(at, .12, t => Math.sin(2 * Math.PI * 185 * t) * Math.exp(-t * 40), .12);
  }
  for (const offset of [.0, .125, .25, .375]) {
    let low = 0;
    const open = offset === .25;
    mix(at + offset, open ? .15 : .05, t => {const n = noise(); low = .55 * low + .45 * n; return (n - low) * Math.exp(-t * (open ? 29 : 90));}, open ? .066 : .036, offset < .25 ? -.4 : .4);
  }
}
// Beat accents match the scene changes at 3, 8, 10 and 15.5 seconds.
for (const cut of [3, 8, 10, 15.5]) {
  let low = 0;
  mix(cut - .4, .48, t => {const n = noise(); low = .85 * low + .15 * n; return (n - low) * (t / .48) ** 2;}, .17, -.25);
  mix(cut, .8, t => Math.sin(2 * Math.PI * (38 * t + 12 * .07 * (1 - Math.exp(-t / .07)))) * Math.exp(-t * 8), .38);
  let smooth = 0;
  mix(cut, .65, t => {smooth = .93 * smooth + .07 * noise(); return smooth * Math.exp(-t * 7);}, .16, .35);
}
// Tactile key transients hit at the deepest point of each keypress.
for (const at of [3, 8.5, 9]) mix(at, .05, t => (noise() * .7 + Math.sin(2 * Math.PI * 390 * t) * .3) * Math.exp(-t * 95), .2);
for (const at of [7.75, 9.75, 15.25]) {
  for (let i = 0; i < 4; i++) {
    let low = 0;
    mix(at + i * .0625, .08, t => {const n = noise(); low = .8 * low + .2 * n; return (n - low) * Math.exp(-t * 45);}, .06 + i * .023, (i - 1.5) * .2);
  }
}
for (let i = 0; i < 3; i++) {
  const hz = freq([62, 69, 74][i]);
  mix(16 + i * .25, 3.7, t => (1 - Math.exp(-t * 90)) * Math.exp(-t * 2.4) * (Math.sin(2 * Math.PI * hz * t) + .15 * Math.sin(2 * Math.PI * hz * 2.001 * t)), .12, (i - 1) * .35);
}
// A short stereo delay adds space without smearing the drum transients.
const delay = Math.round(sampleRate * .1875);
for (let i = delay; i < length; i++) {const a = left[i - delay], b = right[i - delay]; left[i] += b * .095; right[i] += a * .095;}
let peak = 0;
for (let i = 0; i < length; i++) {
  const t = i / sampleRate, fade = Math.min(1, t / .03, Math.max(0, (duration - t) / .75));
  left[i] = Math.tanh(left[i] * 1.45) * fade; right[i] = Math.tanh(right[i] * 1.45) * fade;
  peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
}
const data = Buffer.alloc(length * 4);
for (let i = 0; i < length; i++) {data.writeInt16LE(Math.round(left[i] / peak * .87 * 32767), i * 4); data.writeInt16LE(Math.round(right[i] / peak * .87 * 32767), i * 4 + 2);}
const header = Buffer.alloc(44);
header.write('RIFF', 0); header.writeUInt32LE(36 + data.length, 4); header.write('WAVEfmt ', 8);
header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(2, 22);
header.writeUInt32LE(sampleRate, 24); header.writeUInt32LE(sampleRate * 4, 28); header.writeUInt16LE(4, 32); header.writeUInt16LE(16, 34);
header.write('data', 36); header.writeUInt32LE(data.length, 40);
const output = fileURLToPath(new URL('../public/score.wav', import.meta.url));
mkdirSync(fileURLToPath(new URL('../public/', import.meta.url)), {recursive: true});
writeFileSync(output, Buffer.concat([header, data]));
console.log(`Original 120 BPM score: ${duration}s, stereo ${sampleRate} Hz → ${output}`);
