import React from 'react';
import {C, FONT} from '../theme';

/** A neutral macOS-style window; one radius, border and clip so corners never leak. */
export const Window = ({title, width, height, dark = false, children}: {title: string; width: number; height: number; dark?: boolean; children: React.ReactNode}) =>
  <div style={{
    width, height, borderRadius: 26, overflow: 'hidden', position: 'relative', fontFamily: FONT.ui,
    background: dark ? '#1E1D1C' : C.surface, color: dark ? '#ECE8E2' : C.text,
    boxShadow: `0 0 0 1px ${dark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.10)'}, 0 50px 120px rgba(0,0,0,0.55), 0 16px 36px rgba(0,0,0,0.30)`,
  }}>
    <div style={{height: 64, display: 'flex', alignItems: 'center', padding: '0 26px', gap: 10, borderBottom: `1px solid ${dark ? '#2F2D2B' : C.line}`, background: dark ? '#252422' : '#F6F3EE'}}>
      {['#FF5F57', '#FEBC2E', '#28C840'].map(color => <span key={color} style={{width: 15, height: 15, borderRadius: '50%', background: color}} />)}
      <span style={{flex: 1, textAlign: 'center', marginRight: 75, fontSize: 21, fontWeight: 600, color: dark ? '#A8A29A' : '#7A746C'}}>{title}</span>
    </div>
    {children}
  </div>;

/** The text caret; blinks on the beat until text lands. */
export const Caret = ({f, height = 40, on = true}: {f: number; height?: number; on?: boolean}) =>
  <span style={{display: 'inline-block', width: 3, height, marginLeft: 3, verticalAlign: 'middle', borderRadius: 2, background: C.coral, opacity: on && Math.floor(f / 15) % 2 === 0 ? 1 : 0}} />;
