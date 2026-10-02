import React from 'react';
import {AbsoluteFill} from 'remotion';
import type {Copy, Lang} from '../copy';
import {C, FONT, T, lerp, out, pop, ramp, smooth} from '../theme';
import {display, Slam, Whip} from '../ui/Fx';
import {Pill, type PillState} from '../ui/Pill';
import {VoiceWords} from '../ui/Voice';
import {Caret, Window} from '../ui/Window';

const LAND = T.dictationLand, COMMIT = T.dictationCommit;

/** Freshly inserted text: a warm wash that settles, so the landing reads at a glance. */
export const Landed = ({f, at, children, style}: {f: number; at: number; children: React.ReactNode; style?: React.CSSProperties}) => {
  const k = 1 - ramp(f, at, at + 36);
  return <span style={{...style, borderRadius: 6, padding: '0 4px', margin: '0 -4px', background: `rgba(237,65,46,${0.16 * k})`, boxShadow: `0 0 ${28 * k}px rgba(237,65,46,${0.35 * k})`, display: 'inline-block', transform: `scale(${1 + 0.04 * k})`, transformOrigin: 'left center'}}>{children}</span>;
};

const Row = ({label, value}: {label: string; value: string}) =>
  <div style={{height: 66, display: 'flex', alignItems: 'center', gap: 18, padding: '0 52px', borderBottom: `1px solid ${C.line}`, fontSize: 27}}>
    <span style={{color: '#958E85', minWidth: 90}}>{label}</span><span style={{fontWeight: 500}}>{value}</span>
  </div>;

const pillAt = (f: number, land: number, commit?: number): PillState =>
  f >= land ? 'inserted' : commit !== undefined && f >= commit ? 'transcribing' : 'listening';

/** 5.5–9 s: speak, and the sentence lands at the caret in Mail. */
export const Speak = ({f, copy, lang}: {f: number; copy: Copy; lang: Lang}) => {
  const enter = out(f, 330, 352), whip = (1 - enter) * 60 + smooth(f, 528, 540) * 60;
  const listen = smooth(f, 340, 360) * (1 - smooth(f, COMMIT, LAND - 4));
  const left = 340, top = 300, caret = {x: left + 54, y: top + 352};
  const state = pillAt(f, LAND, COMMIT);
  return <AbsoluteFill>
    <Whip id="speak" amount={whip}>
      <AbsoluteFill style={{perspective: 2200, transform: `translateX(${(1 - enter) * 1500 - smooth(f, 528, 540) * 1500}px)`}}>
        <div style={{position: 'absolute', left, top, transform: `rotateX(${lerp(4, 0, smooth(f, 340, 520))}deg) rotateY(${lerp(-9, 0, smooth(f, 340, 520))}deg) scale(${1 - listen * 0.05})`, opacity: 1 - listen * 0.6, filter: listen > 0 ? `blur(${listen * 5}px)` : undefined}}>
          <Window title={copy.mail.app} width={1240} height={660}>
            <Row label={copy.mail.to} value={copy.mail.toValue} />
            <Row label={copy.mail.subject} value={copy.mail.subjectValue} />
            <div style={{padding: '40px 54px', fontSize: 34, lineHeight: '60px'}}>
              <div>{copy.mail.greeting}</div>
              <div style={{height: 60, display: 'flex', alignItems: 'center'}}>
                {f >= LAND ? <><Landed f={f} at={LAND}>{copy.spoken.join(lang === 'zh' ? '' : ' ')}</Landed><Caret f={f} height={40} /></> : <Caret f={f} height={40} />}
              </div>
            </div>
          </Window>
        </div>
        <div style={{position: 'absolute', left: caret.x - 10, top: top + 440, transform: `scale(${f >= LAND ? pop(f, LAND, 300, 20) * 0.1 + 0.9 : 1})`, transformOrigin: 'left center'}}>
          <Pill state={state} text={copy.pill[state === 'transcribing' ? 'transcribing' : state === 'inserted' ? 'inserted' : 'listening']} undo={state === 'inserted' ? copy.pill.undo : undefined} f={f} />
        </div>
      </AbsoluteFill>
    </Whip>
    <VoiceWords f={f} lang={lang} words={copy.spoken} at={T.speakWords} fly={[COMMIT, LAND - 2]} target={caret} size={lang === 'zh' ? 104 : 96} y={500} />
  </AbsoluteFill>;
};

/** The caption that rides over the landing and the montage. */
export const LandCaption = ({f, copy, lang}: {f: number; copy: Copy; lang: Lang}) =>
  <div style={{position: 'absolute', top: 92, left: 0, right: 0, textAlign: 'center', opacity: 1 - ramp(f, 708, 720), ...display(lang, 92)}}>
    <Slam f={f} at={LAND + 6} style={{color: C.cream}} from={1.2}>{copy.land}</Slam>
  </div>;

const Chat = ({f, land, shot}: {f: number; land: number; shot: Copy['montage'][0]}) =>
  <div style={{padding: '30px 44px', display: 'flex', flexDirection: 'column', height: 456, boxSizing: 'border-box'}}>
    <div style={{fontSize: 22, color: '#958E85', marginBottom: 18}}>{shot.peer}</div>
    <div style={{alignSelf: 'flex-start', background: '#EFEBE5', borderRadius: 26, padding: '16px 28px', fontSize: 34}}>{shot.bubble}</div>
    <div style={{flex: 1}} />
    <div style={{height: 88, borderRadius: 44, border: `2px solid ${C.line}`, display: 'flex', alignItems: 'center', padding: '0 32px', fontSize: 38}}>
      {f >= land && <Landed f={f} at={land}>{shot.text}</Landed>}<Caret f={f} height={36} />
    </div>
  </div>;

const Notes = ({f, land, shot}: {f: number; land: number; shot: Copy['montage'][0]}) =>
  <div style={{padding: '44px 60px', background: '#FFFCF4', height: 456, boxSizing: 'border-box'}}>
    <div style={{fontSize: 46, fontWeight: 700, marginBottom: 26}}>{shot.title}</div>
    <div style={{fontSize: 40, display: 'flex', alignItems: 'center', height: 60}}>{f >= land && <Landed f={f} at={land}>{shot.text}</Landed>}<Caret f={f} height={38} /></div>
  </div>;

const Commit = ({f, land, shot}: {f: number; land: number; shot: Copy['montage'][0]}) =>
  <div style={{padding: '40px 50px', height: 456, boxSizing: 'border-box'}}>
    <div style={{display: 'inline-flex', gap: 10, alignItems: 'center', fontSize: 22, color: '#A8A29A', background: '#2C2A28', borderRadius: 10, padding: '8px 16px', marginBottom: 26}}>
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#A8A29A" strokeWidth="2" strokeLinecap="round"><circle cx="6" cy="6" r="2.5" /><circle cx="6" cy="18" r="2.5" /><circle cx="18" cy="8" r="2.5" /><path d="M6 8.5v7M18 10.5c0 4-6 3-11 5.5" /></svg>{shot.title}
    </div>
    <div style={{height: 160, borderRadius: 14, border: '2px solid #3A3835', padding: '22px 28px', fontSize: 36, fontFamily: FONT.ui, boxSizing: 'border-box'}}>
      {f >= land && <Landed f={f} at={land}>{shot.text}</Landed>}<Caret f={f} height={36} />
    </div>
  </div>;

/** 9–12 s: three apps, three landings, one per two beats. */
export const Montage = ({f, copy}: {f: number; copy: Copy}) => {
  const i = Math.min(2, Math.floor((f - 540) / 60)), start = 540 + i * 60, land = T.montageLands[i];
  const enter = out(f, start, start + 12), exit = smooth(f, start + 50, start + 60);
  const shot = copy.montage[i], tilt = [-8, 7, -5][i];
  const Body = [Chat, Notes, Commit][i];
  return <Whip id={`montage-${i}`} amount={(1 - enter) * 70 + exit * 70}>
    <AbsoluteFill style={{perspective: 2200}}>
      <div style={{position: 'absolute', left: 400, top: 320, transform: `translateX(${(1 - enter) * 1500 - exit * 1500}px) rotateY(${tilt * (1 - smooth(f, start, start + 60) * 0.5)}deg) rotateZ(${tilt * 0.12}deg)`}}>
        <Window title={shot.app} width={1120} height={520} dark={i === 2}><Body f={f} land={land} shot={shot} /></Window>
        <div style={{position: 'absolute', left: 40, top: 548, opacity: ramp(f, land, land + 3), transform: `scale(${f >= land ? 0.85 + 0.15 * pop(f, land) : 0.85})`, transformOrigin: 'left center'}}>
          {f >= land && <Pill state="inserted" text={copy.pill.inserted} undo={copy.pill.undo} f={f} />}
        </div>
      </div>
    </AbsoluteFill>
  </Whip>;
};
