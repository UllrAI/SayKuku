import React from 'react';
import {AbsoluteFill} from 'remotion';
import {C, FONT, clamp, lerp, out, pop, ramp} from '../theme';
import type {Lang} from '../copy';

/** Display type: Source Serif for Latin, Noto Serif SC Black for Chinese. */
export const display = (lang: Lang, size: number): React.CSSProperties => ({
  fontFamily: FONT.display, fontSize: size, fontWeight: lang === 'zh' ? 900 : 800, fontVariationSettings: '"opsz" 60',
  letterSpacing: lang === 'zh' ? 0.02 * size : -0.025 * size, lineHeight: 1.08, whiteSpace: 'pre',
});

/** Text that punches in on its frame: overshoot scale, blur to sharp. */
export const Slam = ({f, at, children, style, from = 1.35}: {f: number; at: number; children: React.ReactNode; style?: React.CSSProperties; from?: number}) => {
  if (f < at) return null;
  const p = pop(f, at, 320, 20), sharp = ramp(f, at, at + 7);
  return <div style={{...style, opacity: clamp((f - at + 1) / 3), transform: `scale(${lerp(from, 1, p)})`, filter: sharp < 1 ? `blur(${(1 - sharp) * 10}px)` : undefined}}>{children}</div>;
};

/** Expanding coral shock rings centered on an impact point. */
export const Rings = ({f, hits, x, y, color = C.coral}: {f: number; hits: number[]; x: number; y: number; color?: string}) =>
  <svg width={1920} height={1080} style={{position: 'absolute', inset: 0, pointerEvents: 'none'}}>
    {hits.flatMap(at => [0, 5].map(delay => {
      const t = f - at - delay;
      if (t < 0 || t > 42) return null;
      const p = out(t, 0, 42);
      return <circle key={`${at}-${delay}`} cx={x} cy={y} r={lerp(60, delay ? 760 : 1100, p)} fill="none" stroke={color} strokeWidth={lerp(delay ? 6 : 14, 0.5, p)} opacity={(1 - p) * (delay ? 0.5 : 0.9)} />;
    }))}
  </svg>;

/** Horizontal motion blur for whip pans; SVG filter so it stays one pass. */
export const Whip = ({id, amount, children}: {id: string; amount: number; children: React.ReactNode}) => {
  if (amount < 0.5) return <AbsoluteFill>{children}</AbsoluteFill>;
  return <AbsoluteFill style={{filter: `url(#${id})`}}>
    <svg width="0" height="0" style={{position: 'absolute'}}><filter id={id} x="-20%" y="0" width="140%" height="100%"><feGaussianBlur stdDeviation={`${amount} 0`} /></filter></svg>
    {children}
  </AbsoluteFill>;
};

/** Film grain and vignette that tie 3D, UI and type into one image. */
export const Finish = ({f, strength = 1}: {f: number; strength?: number}) =>
  <AbsoluteFill style={{pointerEvents: 'none'}}>
    <AbsoluteFill style={{background: 'radial-gradient(ellipse at 50% 50%, transparent 62%, rgba(0,0,0,0.42) 100%)', opacity: strength}} />
    <svg width={1920} height={1080} style={{position: 'absolute', inset: 0, mixBlendMode: 'overlay', opacity: 0.22 * strength}}>
      <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed={f % 12} stitchTiles="stitch" /><feColorMatrix type="saturate" values="0" /></filter>
      <rect width="100%" height="100%" filter="url(#grain)" />
    </svg>
  </AbsoluteFill>;

export const Disclaimer = ({text, opacity}: {text: string; opacity: number}) =>
  <div style={{position: 'absolute', right: 56, bottom: 40, fontFamily: FONT.ui, fontSize: 19, color: 'rgba(243,236,225,0.55)', opacity, letterSpacing: 0.2}}>{text}</div>;
