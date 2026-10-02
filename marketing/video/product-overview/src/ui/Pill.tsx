import React from 'react';
import {C, FONT} from '../theme';

// Point sizes from Theme.swift (36 pt pill, 24 pt buttons, 8 pt spacing), scaled up for 1080p.
const S = 2.4;
const pt = (n: number) => n * S;

export type PillState = 'listening' | 'agentListening' | 'transcribing' | 'understanding' | 'running' | 'inserted' | 'done';

const Icon = ({d, size, color, width = 2.2}: {d: string; size: number; color: string; width?: number}) =>
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>;
const XMARK = 'M6 6l12 12M18 6L6 18';
const CHECK = 'M5 12.5l4.5 4.5L19 7';

export const Sparkle = ({size, color = C.coral, rotate = 0, scale = 1}: {size: number; color?: string; rotate?: number; scale?: number}) =>
  <svg width={size} height={size} viewBox="0 0 24 24" style={{transform: `rotate(${rotate}deg) scale(${scale})`}}>
    <path d="M12 2.5C12.6 8 16 11.4 21.5 12C16 12.6 12.6 16 12 21.5C11.4 16 8 12.6 2.5 12C8 11.4 11.4 8 12 2.5Z" fill={color} />
  </svg>;

const Circle = ({fill, children}: {fill: string; children: React.ReactNode}) =>
  <div style={{width: pt(24), height: pt(24), borderRadius: '50%', background: fill, display: 'grid', placeItems: 'center', flexShrink: 0}}>{children}</div>;

const Waveform = ({f}: {f: number}) =>
  <div style={{width: pt(22), height: pt(15), display: 'flex', alignItems: 'center', justifyContent: 'center', gap: pt(2)}}>
    {[0, 1, 2, 3, 4].map(i => {
      const envelope = 1 - Math.abs(i - 2) / 2 * 0.42;
      const level = 0.35 + 0.65 * Math.abs(Math.sin(f * 0.21 + i * 1.3) * Math.sin(f * 0.077 + i * 0.6));
      return <span key={i} style={{width: pt(2.4), height: pt(3) + pt(12) * level * envelope, borderRadius: pt(2), background: C.coral}} />;
    })}
  </div>;

const Spinner = ({f}: {f: number}) =>
  <svg width={pt(16)} height={pt(16)} viewBox="0 0 24 24" style={{transform: `rotate(${Math.floor(f / 4) * 45}deg)`}}>
    {Array.from({length: 8}, (_, i) =>
      <line key={i} x1="12" y1="3" x2="12" y2="7.5" stroke={C.textSecondary} strokeWidth="2.4" strokeLinecap="round" opacity={0.25 + 0.75 * ((8 - i) % 8) / 8} transform={`rotate(${-i * 45} 12 12)`} />)}
  </svg>;

const Label = ({children, color = C.text}: {children: React.ReactNode; color?: string}) =>
  <span style={{fontFamily: FONT.ui, fontSize: pt(12.5), fontWeight: 600, color, whiteSpace: 'nowrap', letterSpacing: 0.1}}>{children}</span>;

/** The floating overlay pill, following RecordingPill, DictationPill and AgentPill. */
export const Pill = ({state, text, undo, f}: {state: PillState; text: string; undo?: string; f: number}) => {
  const listening = state === 'listening' || state === 'agentListening';
  const result = state === 'inserted' || state === 'done';
  return <div style={{
    height: pt(36), minWidth: listening ? pt(208) : undefined, boxSizing: 'border-box', padding: `0 ${pt(8)}px`,
    display: 'flex', alignItems: 'center', gap: pt(8), borderRadius: pt(18),
    background: 'rgba(250, 248, 245, 0.92)', border: '1px solid rgba(255,255,255,0.7)',
    boxShadow: '0 1px 0 rgba(255,255,255,0.8) inset, 0 0 0 1px rgba(0,0,0,0.06), 0 18px 40px rgba(0,0,0,0.28), 0 4px 10px rgba(0,0,0,0.12)',
  }}>
    {listening && <>
      <Circle fill="rgba(0,0,0,0.05)"><Icon d={XMARK} size={pt(11)} color={C.textSecondary} /></Circle>
      <div style={{display: 'flex', alignItems: 'center', gap: pt(4)}}>
        <div style={{width: pt(16), display: 'grid', placeItems: 'center'}}>{state === 'agentListening' && <Sparkle size={pt(13)} />}</div>
        <Waveform f={f} />
      </div>
      <Label>{text}</Label>
      <div style={{flex: 1}} />
      <Circle fill={C.coral}><Icon d={CHECK} size={pt(12)} color="#fff" width={2.8} /></Circle>
    </>}
    {state === 'transcribing' && <><Spinner f={f} /><Label>{text}</Label><div style={{flex: 1, minWidth: pt(8)}} /><Circle fill="rgba(0,0,0,0.05)"><Icon d={XMARK} size={pt(11)} color={C.textSecondary} /></Circle></>}
    {(state === 'understanding' || state === 'running') && <>
      <div style={{width: pt(18), display: 'grid', placeItems: 'center'}}>
        <Sparkle size={pt(14)} rotate={(f % 96) / 96 * 180} scale={0.76 + 0.24 * (0.5 - 0.5 * Math.cos((f % 96) / 96 * Math.PI * 2))} />
      </div>
      <Label>{text}</Label><div style={{flex: 1, minWidth: pt(8)}} />
      <Circle fill="rgba(0,0,0,0.05)"><Icon d={XMARK} size={pt(11)} color={C.textSecondary} /></Circle>
    </>}
    {result && <>
      <div style={{paddingLeft: pt(2), display: 'flex', alignItems: 'center', gap: pt(6)}}>
        <Icon d={CHECK} size={pt(14)} color={C.success} width={2.8} /><Label color={C.textSecondary}>{text}</Label>
      </div>
      {undo && <><div style={{flex: 1, minWidth: pt(14)}} /><span style={{paddingRight: pt(4)}}><Label color="#C73321">{undo}</Label></span></>}
    </>}
  </div>;
};
