import {AbsoluteFill} from 'remotion';
import type {Copy, Lang} from '../copy';
import {C, T, flash, noise, out, pop, ramp, smooth} from '../theme';
import {Pill, type PillState} from '../ui/Pill';
import {VoiceWords} from '../ui/Voice';
import {Caret, Window} from '../ui/Window';
import {Landed} from './Typing';

const MORPH = [T.agentLand - 20, T.agentLand + 8];

/** Rewrites the selection in place: a coral scramble sweeps left to right. */
const Morph = ({f, from, to}: {f: number; from: string; to: string}) => {
  const target = [...to], source = [...from], pool = [...new Set([...from, ...to].filter(ch => ch.trim()))];
  const span = MORPH[1] - MORPH[0];
  return <>{target.map((ch, i) => {
    const reveal = MORPH[0] + (i / target.length) * span;
    if (f >= reveal) return <span key={i}>{ch}</span>;
    if (f >= reveal - 8) return <span key={i} style={{color: C.coral}}>{pool[Math.floor((noise(i * 7 + Math.floor(f / 2)) + 0.5) * pool.length)]}</span>;
    return <span key={i}>{source[i] ?? ''}</span>;
  })}</>;
};

const agentPill = (f: number): PillState =>
  f >= T.agentLand + 10 ? 'done' : f >= T.agentRun ? 'running' : f >= T.agentUnderstand ? 'understanding' : 'agentListening';

/** 14–17.5 s: select a rough line, say how it should read, and it is rewritten in place. */
export const Agent = ({f, copy, lang}: {f: number; copy: Copy; lang: Lang}) => {
  const a = copy.agent, enter = out(f, 840, 862), listen = smooth(f, 856, 872) * (1 - smooth(f, T.agentUnderstand, T.agentUnderstand + 20));
  const state = agentPill(f), left = 340, top = 230;
  const pillPoint = {x: left + 300, y: top + 700};
  const label = {agentListening: copy.pill.listening, understanding: copy.pill.understanding, running: copy.pill.running, done: copy.pill.done}[state as 'done'];
  return <AbsoluteFill style={{opacity: 1 - ramp(f, 1044, 1050)}}>
    <AbsoluteFill style={{perspective: 2200, transform: `scale(${1.18 - 0.18 * enter})`}}>
      <div style={{position: 'absolute', left, top, transform: `rotateY(${6 - 6 * smooth(f, 840, 1000)}deg) scale(${1 - listen * 0.05})`, opacity: 1 - listen * 0.6, filter: listen > 0 ? `blur(${listen * 5}px)` : undefined}}>
        <Window title={a.app} width={1240} height={660}>
          <div style={{padding: '30px 50px', display: 'flex', flexDirection: 'column', height: 596, boxSizing: 'border-box'}}>
            <div style={{fontSize: 22, color: '#958E85', marginBottom: 18}}>{a.peer}</div>
            <div style={{alignSelf: 'flex-start', background: '#EFEBE5', borderRadius: 26, padding: '16px 28px', fontSize: 34}}>{a.bubble}</div>
            <div style={{flex: 1}} />
            <div style={{minHeight: 96, borderRadius: 30, border: `2px solid ${C.line}`, display: 'flex', alignItems: 'center', padding: '16px 32px', fontSize: 36, lineHeight: 1.45, boxSizing: 'border-box'}}>
              {f < MORPH[0]
                ? <span style={{background: C.selection, borderRadius: 4, padding: '2px 2px'}}>{a.selected}</span>
                : f < MORPH[1] ? <span><Morph f={f} from={a.selected} to={a.result} /></span>
                : <span><Landed f={f} at={MORPH[1]}>{a.result}</Landed><Caret f={f} height={36} /></span>}
            </div>
          </div>
        </Window>
      </div>
      <div style={{position: 'absolute', left: left + 50, top: top + 694, transformOrigin: 'left center', transform: `scale(${state === 'done' ? 0.9 + 0.1 * pop(f, T.agentLand + 10) : 1})`}}>
        <Pill state={state} text={label} undo={state === 'done' ? copy.pill.undo : undefined} f={f} />
      </div>
    </AbsoluteFill>
    <VoiceWords f={f} lang={lang} words={a.command} at={T.commandWords} fly={[T.agentUnderstand, T.agentUnderstand + 22]} target={pillPoint} rows={1} size={lang === 'zh' ? 150 : 128} y={430} />
    <AbsoluteFill style={{background: '#FFF4EC', opacity: flash(f, [840], 12) * 0.9}} />
  </AbsoluteFill>;
};
