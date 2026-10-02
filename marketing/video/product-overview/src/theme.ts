import {spring} from 'remotion';
import timeline from './timeline.json';

export const T = timeline;
const FPS = T.fps;

// Brand: warm paper, ink and the app's coral (KukuColor.coral).
export const C = {
  ink: '#13100D',
  ink2: '#211C17',
  paper: '#FDF9F3',
  cream: '#F3ECE1',
  muted: '#9A9083',
  coral: '#ED412E',
  brand: '#D9410A',
  success: '#349368',
  text: '#1C1B19',
  textSecondary: '#6E6A64',
  surface: '#FDFCFA',
  line: '#E8E2D8',
  selection: '#C9DCF6',
};

export const FONT = {
  display: '"Source Serif 4 Variable", "Noto Serif SC", serif',
  ui: '"Inter Variable", "Noto Sans SC", sans-serif',
};

export const clamp = (x: number) => Math.max(0, Math.min(1, x));
export const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
export const ramp = (f: number, a: number, b: number) => clamp((f - a) / (b - a));
export const smooth = (f: number, a: number, b: number) => {const p = ramp(f, a, b); return p * p * (3 - 2 * p);};
export const out = (f: number, a: number, b: number) => 1 - (1 - ramp(f, a, b)) ** 3;
export const outExpo = (f: number, a: number, b: number) => {const p = ramp(f, a, b); return p === 1 ? 1 : 1 - 2 ** (-10 * p);};
export const inExpo = (f: number, a: number, b: number) => {const p = ramp(f, a, b); return p === 0 ? 0 : 2 ** (10 * p - 10);};
export const pop = (f: number, start: number, stiffness = 260, damping = 18) =>
  spring({frame: f - start, fps: FPS, config: {stiffness, damping, mass: 0.6}});
export const within = (f: number, [a, b]: number[]) => f >= a && f < b;

// Deterministic hash noise so every render of a frame is identical.
export const noise = (n: number) => {const x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x) - 0.5;};

/** Decaying camera shake after each impact frame. */
export const shake = (f: number, hits: [number, number][]) => {
  let x = 0, y = 0, r = 0;
  for (const [at, amount] of hits) {
    const t = f - at;
    if (t < 0 || t > 24) continue;
    const k = Math.exp(-t / 6) * amount;
    x += noise(f * 1.7 + at) * k; y += noise(f * 2.3 + at + 9) * k; r += noise(f * 3.1 + at + 4) * k * 0.02;
  }
  return `translate(${x}px, ${y}px) rotate(${r}deg)`;
};

/** A short white-hot flash that fades on impact. */
export const flash = (f: number, hits: number[], length = 10) =>
  Math.max(0, ...hits.map(at => (f >= at && f < at + length ? 1 - (f - at) / length : 0)));
