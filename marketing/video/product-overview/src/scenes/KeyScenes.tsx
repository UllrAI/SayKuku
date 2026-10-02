import {AbsoluteFill} from 'remotion';
import type {Copy, Lang} from '../copy';
import {keyOnScreen} from '../KeyStage';
import {C, T, flash, inExpo, lerp, out, pop, ramp, smooth} from '../theme';
import {display, Rings, Slam} from '../ui/Fx';
import {Pill} from '../ui/Pill';

const [PRESS] = T.keyPresses;

/** 0–3 s: a caret, two lines, then everything collapses into the Fn key. */
export const Hook = ({f, copy, lang}: {f: number; copy: Copy; lang: Lang}) => {
  const typed = T.typeTicks.filter(at => f >= at).length;
  const collapse = inExpo(f, 136, 160);
  const dive = inExpo(f, 158, PRESS), key = keyOnScreen(PRESS);
  const caretOn = f < 60 ? Math.floor(f / 15) % 2 === 0 : f >= 126 ? Math.floor((f - 126) / 15) % 2 === 0 : true;
  return <AbsoluteFill>
    {f < 160 && <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', transform: `scale(${1 - collapse})`, opacity: 1 - collapse, filter: collapse > 0 ? `blur(${collapse * 16}px)` : undefined}}>
      <div style={{display: 'flex', gap: lang === 'zh' ? 0 : 36, height: 190, alignItems: 'center', ...display(lang, 172), color: C.cream}}>
        {copy.hookA.map((word, i) => <Slam key={word} f={f} at={T.hookWords[i]} from={1.6}>{word}</Slam>)}
      </div>
      <div style={{...display(lang, 172), color: '#7D746A', height: 190, display: 'flex', alignItems: 'center'}}>
        {copy.hookB.slice(0, typed).join('')}
        <span style={{display: 'inline-block', width: 8, height: 150, marginLeft: 12, borderRadius: 4, background: C.coral, opacity: caretOn ? 1 : 0}} />
      </div>
    </AbsoluteFill>}
    {f >= 150 && f < PRESS + 2 && <div style={{
      position: 'absolute', width: 34, height: 34, borderRadius: '50%', background: C.coral, boxShadow: `0 0 40px 12px ${C.coral}`,
      left: lerp(960, key.x, dive) - 17, top: lerp(540, key.y, dive) - 17, transform: `scale(${lerp(0.4, 1, ramp(f, 150, 162)) * lerp(1, 0.5, dive)})`,
    }} />}
  </AbsoluteFill>;
};

const Glare = ({f, x, y}: {f: number; x: number; y: number}) => {
  const k = flash(f, T.keyPresses, 14);
  return k > 0 ? <AbsoluteFill style={{background: `radial-gradient(circle at ${x}px ${y}px, rgba(255,214,190,${k}) 0%, rgba(237,65,46,${k * 0.55}) 22%, transparent 60%)`, mixBlendMode: 'screen'}} /> : null;
};

/** 3–5.5 s: the press lands on the drop, the headline answers it. */
export const Press = ({f, copy, lang}: {f: number; copy: Copy; lang: Lang}) => {
  const key = keyOnScreen(f), leave = smooth(f, 296, 330);
  return <AbsoluteFill>
    <AbsoluteFill style={{background: 'linear-gradient(90deg, transparent 38%, rgba(10,9,8,0.82) 60%)', opacity: smooth(f, PRESS + 4, PRESS + 30) * (1 - leave)}} />
    <Rings f={f} hits={[PRESS]} x={key.x} y={key.y} />
    <Glare f={f} x={key.x} y={key.y} />
    <div style={{position: 'absolute', left: 1060, top: 300, transform: `translateX(${-leave * 1400}px)`, ...display(lang, 128)}}>
      <Slam f={f} at={PRESS} style={{color: C.cream, transformOrigin: 'left center'}}>{copy.press[0]}</Slam>
      <Slam f={f} at={PRESS + 24} style={{color: C.coral, transformOrigin: 'left center'}}>{copy.press[1]}</Slam>
      <div style={{marginTop: 54, transformOrigin: 'left center', transform: `scale(${pop(f, 222, 300, 22)})`, opacity: ramp(f, 222, 226), width: 'fit-content'}}>
        {f >= 222 && <Pill state="listening" text={copy.pill.listening} f={f} />}
      </div>
    </div>
  </AbsoluteFill>;
};

/** 12–14 s: the same key, pressed twice, wakes Voice Agent. */
export const Double = ({f, copy, lang}: {f: number; copy: Copy; lang: Lang}) => {
  const key = keyOnScreen(f), dive = inExpo(f, 806, 840);
  const presses = T.keyPresses.slice(1);
  return <AbsoluteFill style={{transform: `scale(${1 + dive * 2.5})`, opacity: 1 - dive, transformOrigin: `${key.x}px ${key.y}px`}}>
    <AbsoluteFill style={{background: 'linear-gradient(180deg, rgba(10,9,8,0.9) 0%, rgba(10,9,8,0.6) 30%, transparent 50%)'}} />
    <Rings f={f} hits={presses} x={key.x} y={key.y} />
    <Glare f={f} x={key.x} y={key.y} />
    <div style={{position: 'absolute', left: 0, right: 0, top: 84, textAlign: 'center', ...display(lang, 112)}}>
      <Slam f={f} at={726} style={{color: C.cream}}>{copy.double[0]}</Slam>
      <Slam f={f} at={780} style={{color: C.coral}}>{copy.double[1]}</Slam>
    </div>
    {presses.map((at, i) => f >= at && f < at + 28 && <div key={at} style={{
      position: 'absolute', left: key.x + 130, top: key.y - 210, ...display(lang, 96), color: C.coral,
      opacity: 1 - ramp(f, at + 14, at + 28), transform: `translateY(${-out(f, at, at + 28) * 50}px) scale(${lerp(1.5, 1, pop(f, at))})`,
    }}>{i + 1}</div>)}
    <div style={{position: 'absolute', left: 0, right: 0, bottom: 86, display: 'flex', justifyContent: 'center', transform: `scale(${pop(f, 792, 300, 22)})`, opacity: ramp(f, 792, 796)}}>
      {f >= 792 && <Pill state="agentListening" text={copy.pill.listening} f={f} />}
    </div>
  </AbsoluteFill>;
};
