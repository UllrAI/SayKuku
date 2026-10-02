import {AbsoluteFill, Html5Audio, staticFile, useCurrentFrame} from 'remotion';
import {COPY, glyphs, type Lang} from './copy';
import {useFonts} from './fonts';
import {KeyStage} from './KeyStage';
import {Agent} from './scenes/Agent';
import {Finale, Verbs} from './scenes/Brand';
import {Double, Hook, Press} from './scenes/KeyScenes';
import {LandCaption, Montage, Speak} from './scenes/Typing';
import {T, ramp, shake, within} from './theme';
import {Disclaimer, Finish} from './ui/Fx';

const S = T.scenes;
// Impacts that move the camera, with how hard each one hits.
const HITS: [number, number][] = [
  [T.keyPresses[0], 34], [T.keyPresses[1], 20], [T.keyPresses[2], 26], [T.dictationLand, 10],
  ...T.montageLands.map(at => [at, 8] as [number, number]), [T.agentLand, 10],
  ...T.verbHits.map(at => [at, 20] as [number, number]), [T.finaleWipe, 14],
];

// Dark stage with a faint warm haze that drifts, so empty space never looks flat.
const Backdrop = ({f}: {f: number}) =>
  <div style={{position: 'absolute', inset: -60, background: `radial-gradient(ellipse at ${42 + 10 * Math.sin(f / 240)}% ${58 + 6 * Math.cos(f / 300)}%, #2C221B 0%, #15110E 55%, #0A0908 100%)`}} />;

export const Film = ({lang}: {lang: Lang}) => {
  const f = useCurrentFrame(), copy = COPY[lang], props = {f, copy, lang};
  useFonts(glyphs(copy));
  const ui = Math.min(ramp(f, 226, 240) * (1 - ramp(f, 712, 720)) + ramp(f, 846, 860) * (1 - ramp(f, 1040, 1050)), 1);
  return <AbsoluteFill style={{background: '#0A0908', overflow: 'hidden'}}>
    <Html5Audio src={staticFile('score.wav')} />
    <AbsoluteFill style={{transform: shake(f, HITS)}}>
      <Backdrop f={f} />
      {(within(f, [130, S.press[1]]) || within(f, S.double)) && <KeyStage f={f} />}
      {within(f, S.hook) && <Hook {...props} />}
      {within(f, S.press) && <Press {...props} />}
      {within(f, S.speak) && <Speak {...props} />}
      {within(f, S.montage) && <Montage {...props} />}
      {within(f, [T.dictationLand, S.montage[1]]) && <LandCaption {...props} />}
      {within(f, S.double) && <Double {...props} />}
      {within(f, S.agent) && <Agent {...props} />}
      {within(f, S.verbs) && <Verbs {...props} />}
      {within(f, S.finale) && <Finale {...props} />}
    </AbsoluteFill>
    <Disclaimer text={copy.disclaimer} opacity={ui} />
    <Finish f={f} strength={f >= S.verbs[0] ? 0.25 : 1} />
  </AbsoluteFill>;
};
