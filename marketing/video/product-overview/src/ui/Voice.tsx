import {AbsoluteFill} from 'remotion';
import type {Lang} from '../copy';
import {C, clamp, inExpo, lerp, out, ramp} from '../theme';
import {display} from './Fx';

// Rough advance widths (in ems) are enough to space words; each word is centered on its slot.
const em = (ch: string) => /[\u3000-\u9fff\uff00-\uffef]/.test(ch) ? 1.02 : /[A-Z]/.test(ch) ? 0.62 : ch === ' ' ? 0.22 : /[a-z0-9]/.test(ch) ? 0.47 : 0.24;
const width = (word: string, size: number) => [...word].reduce((sum, ch) => sum + em(ch), 0) * size;

/**
 * Spoken words drift toward the viewer while you talk, then pour into `target`.
 * They stand for the voice, not for live text: the app writes only after recording ends.
 */
export const VoiceWords = ({f, lang, words, at, fly, target, rows = 2, size = 104, y = 540}: {
  f: number; lang: Lang; words: string[]; at: number[]; fly: [number, number]; target: {x: number; y: number}; rows?: number; size?: number; y?: number;
}) => {
  const gap = size * (lang === 'zh' ? 0.12 : 0.26), perRow = Math.ceil(words.length / rows);
  const slots = words.map((word, i) => {
    const row = Math.floor(i / perRow), line = words.slice(row * perRow, (row + 1) * perRow);
    const total = line.reduce((sum, w) => sum + width(w, size), 0) + gap * (line.length - 1);
    const before = line.slice(0, i - row * perRow).reduce((sum, w) => sum + width(w, size) + gap, 0);
    return {x: 960 - total / 2 + before + width(word, size) / 2, y: y + (row - (rows - 1) / 2) * size * 1.3};
  });
  const latest = at.filter(a => f >= a).length - 1;
  return <AbsoluteFill style={{perspective: 1400}}>
    {words.map((word, i) => {
      if (f < at[i]) return null;
      const enter = out(f, at[i], at[i] + 16), gone = inExpo(f, fly[0] + i * 3, fly[1]);
      const x = lerp(slots[i].x, target.x, gone), yy = lerp(slots[i].y, target.y, gone), hot = i === latest && gone === 0;
      return <div key={word} style={{
        position: 'absolute', left: x, top: yy, ...display(lang, size), color: hot ? C.paper : C.cream,
        opacity: clamp(enter * 1.4) * (1 - ramp(gone, 0.75, 1)),
        transform: `translate(-50%, -50%) translate3d(0, ${(1 - enter) * 40}px, ${(1 - enter) * 500}px) scale(${lerp(1, 0.12, gone)})`,
        filter: enter < 1 || gone > 0 ? `blur(${(1 - enter) * 14 + gone * 6}px)` : undefined,
        textShadow: hot ? '0 0 38px rgba(237,65,46,0.55)' : undefined,
      }}>{word}</div>;
    })}
  </AbsoluteFill>;
};
