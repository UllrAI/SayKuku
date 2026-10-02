import {C, FONT} from '../theme';

// The app's bird (Lucide Bird, ISC) exactly as in SayKuku.svg.
const BIRD = ['M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20', 'm20 7 2 .5-2 .5', 'M10 18v3', 'M14 17.75V21', 'M7 18a6 6 0 0 0 3.84-10.61'];

/** Draws the flat mark stroke by stroke; `draw` runs from 0 to 1. */
export const Bird = ({size, draw = 1, color = C.brand}: {size: number; draw?: number; color?: string}) =>
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round">
    {BIRD.map((d, i) => {
      const local = Math.max(0, Math.min(1, draw * 1.6 - i * 0.15));
      return <path key={d} d={d} pathLength={1} strokeDasharray="1 1" strokeDashoffset={1 - local} />;
    })}
    <circle cx="16" cy="7" r="0.85" fill={color} stroke="none" opacity={draw >= 0.9 ? 1 : 0} />
  </svg>;

export const Wordmark = ({size, dot = 1, color = C.text}: {size: number; dot?: number; color?: string}) =>
  <span style={{fontFamily: FONT.ui, fontWeight: 700, fontSize: size, letterSpacing: -0.035 * size, color, lineHeight: 1, display: 'inline-flex', alignItems: 'baseline'}}>
    SayKuku
    <span style={{display: 'inline-block', width: size * 0.17, height: size * 0.17, borderRadius: '50%', marginLeft: size * 0.03, background: C.brand, transform: `scale(${dot})`}} />
  </span>;
