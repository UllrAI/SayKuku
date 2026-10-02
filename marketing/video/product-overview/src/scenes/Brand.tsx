import {AbsoluteFill} from 'remotion';
import type {Copy, Lang} from '../copy';
import {C, FONT, T, inExpo, lerp, outExpo, out, pop, ramp, smooth} from '../theme';
import {Bird, Wordmark} from '../ui/Brand';
import {display, Slam} from '../ui/Fx';

// Background / ink pairs for the four hits; the last one returns to ink for the wipe.
const PALETTE = [[C.coral, C.ink], [C.ink, C.cream], [C.paper, C.coral], [C.ink, C.coral]];

/** 17.5–19.5 s: what Voice Agent does, one word per beat. */
export const Verbs = ({f, copy, lang}: {f: number; copy: Copy; lang: Lang}) => {
  const i = Math.min(3, T.verbHits.filter(at => f >= at).length - 1), at = T.verbHits[i];
  const [bg, ink] = PALETTE[i], collapse = inExpo(f, 1150, T.finaleWipe);
  return <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
    <div style={{position: 'absolute', inset: -60, background: bg}} />
    <div style={{position: 'absolute', top: 70, fontFamily: FONT.ui, fontWeight: 600, fontSize: 30, letterSpacing: 6, color: ink, opacity: 0.55 * (1 - collapse)}}>FN FN · VOICE AGENT</div>
    <div style={{transform: `scale(${1 - collapse}) translateY(${(1 - out(f, at, at + 10)) * 30}px)`, filter: collapse > 0 ? `blur(${collapse * 10}px)` : undefined}}>
      <Slam key={at} f={f} at={at} from={1.5} style={{...display(lang, lang === 'zh' ? 300 : 260), color: ink}}>{copy.verbs[i]}</Slam>
    </div>
    {collapse > 0.6 && <div style={{position: 'absolute', width: 40, height: 40, borderRadius: '50%', background: C.coral, transform: `scale(${ramp(collapse, 0.6, 1)})`}} />}
  </AbsoluteFill>;
};

/** 19.5–24 s: paper floods out from the dot; the mark draws itself; the dot lands on the beat. */
export const Finale = ({f, copy, lang}: {f: number; copy: Copy; lang: Lang}) => {
  const wipe = outExpo(f, T.finaleWipe, T.finaleWipe + 26), dot = f < T.dotPop ? 0 : pop(f, T.dotPop, 380, 12);
  const drift = smooth(f, T.finaleWipe, 1440);
  const fin = copy.finale;
  return <AbsoluteFill>
    <div style={{position: 'absolute', inset: -60, background: C.ink}} />
    <div style={{position: 'absolute', inset: -60, background: `radial-gradient(ellipse at 50% 42%, #FFFFFF 0%, ${C.paper} 45%, #F1E9DC 100%)`, clipPath: `circle(${wipe * 1260}px at 1020px 600px)`}}>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', transform: `scale(${lerp(1.04, 1, drift)})`}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 34, marginTop: -30}}>
          <div style={{transform: `scale(${lerp(0.8, 1, out(f, 1172, 1210))})`}}><Bird size={218} draw={ramp(f, 1174, 1222)} /></div>
          <div style={{overflow: 'hidden', padding: '12px 30px 22px 0'}}>
            <div style={{transform: `translateY(${(1 - outExpo(f, 1186, 1216)) * 280}px)`, opacity: f >= 1186 ? 1 : 0}}><Wordmark size={200} dot={dot} /></div>
          </div>
        </div>
        <div style={{height: 150, marginTop: 26}}>
          <Slam f={f} at={1248} from={1.12} style={{...display(lang, lang === 'zh' ? 92 : 104), color: C.text}}>{fin.line}</Slam>
        </div>
        <div style={{display: 'flex', alignItems: 'center', gap: 28, marginTop: 10, fontFamily: FONT.ui, opacity: ramp(f, 1284, 1296), transform: `translateY(${(1 - out(f, 1284, 1310)) * 24}px)`}}>
          <span style={{fontSize: 44, fontWeight: 600, color: C.brand, letterSpacing: 0.5}}>{fin.url}</span>
        </div>
        <div style={{marginTop: 22, fontFamily: FONT.ui, fontSize: 28, color: '#8A8076', opacity: ramp(f, 1300, 1314), letterSpacing: 0.3}}>{fin.meta}</div>
      </AbsoluteFill>
    </div>
  </AbsoluteFill>;
};
