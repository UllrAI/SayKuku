import React, {useLayoutEffect, useRef} from 'react';
import {AbsoluteFill, Html5Audio, spring, staticFile, useCurrentFrame, useDelayRender} from 'remotion';
import * as THREE from 'three';
import {RoundedBoxGeometry} from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';

const ORANGE = '#D65024';
const CREAM = '#FCF8F1';
const INK = '#292621';
const FONT = '"Helvetica Neue", "PingFang SC", sans-serif';
type V3 = [number, number, number];
const clamp = (x: number) => Math.max(0, Math.min(1, x));
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
const ramp = (f: number, a: number, b: number) => clamp((f - a) / (b - a));
const ease = (f: number, a: number, b: number) => {const p = ramp(f, a, b); return p * p * (3 - 2 * p);};
const enter = (f: number, start: number, duration = 54) => spring({frame: f - start, fps: 60, config: {damping: 28, stiffness: 120}, durationInFrames: duration});
const pulse = (f: number, start: number) => Math.sin(Math.PI * ramp(f, start, start + 22));
const BIRD = ['M16 7h.01', 'M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20', 'm20 7 2 .5-2 .5', 'M10 18v3', 'M14 17.75V21', 'M7 18a6 6 0 0 0 3.84-10.61'];
const round = (w: number, h: number, d: number, radius: number) => new RoundedBoxGeometry(w, h, d, 6, radius);
const texture = (w: number, h: number, draw: (ctx: CanvasRenderingContext2D) => void) => {
  const canvas = document.createElement('canvas'); canvas.width = w; canvas.height = h;
  draw(canvas.getContext('2d')!);
  const map = new THREE.CanvasTexture(canvas); map.colorSpace = THREE.SRGBColorSpace; map.anisotropy = 16;
  return map;
};
type Stage = {
  renderer: THREE.WebGLRenderer; scene: THREE.Scene; camera: THREE.PerspectiveCamera;
  single: THREE.Group; pair: THREE.Group; faces: THREE.Group[]; environment: THREE.WebGLRenderTarget;
};
const makeKey = () => {
  const key = new THREE.Group();
  const base = new THREE.Mesh(round(2.4, 2.4, .38, .28), new THREE.MeshPhysicalMaterial({color: '#A69E92', metalness: .75, roughness: .34, envMapIntensity: .9}));
  base.position.z = -.19; key.add(base);
  const stem = new THREE.Mesh(new THREE.BoxGeometry(1.65, 1.65, .38), new THREE.MeshStandardMaterial({color: '#27241E', metalness: .6, roughness: .3}));
  stem.position.z = -.27; key.add(stem);
  const face = new THREE.Group(); key.add(face);
  const top = new THREE.Mesh(round(2.28, 2.28, .22, .26), new THREE.MeshPhysicalMaterial({color: '#F1EADF', metalness: .06, roughness: .42, clearcoat: .32, clearcoatRoughness: .3}));
  top.position.z = .04; face.add(top);
  const map = texture(1024, 1024, ctx => {
    ctx.fillStyle = '#3D3933'; ctx.font = `400 265px ${FONT}`; ctx.fillText('fn', 158, 453);
    ctx.strokeStyle = '#716A60'; ctx.lineWidth = 8; ctx.beginPath(); ctx.arc(207, 777, 46, 0, Math.PI * 2); ctx.stroke();
    ctx.beginPath(); ctx.ellipse(207, 777, 20, 46, 0, 0, Math.PI * 2); ctx.moveTo(161, 777); ctx.lineTo(253, 777); ctx.stroke();
  });
  const label = new THREE.Mesh(new THREE.PlaneGeometry(2.12, 2.12), new THREE.MeshBasicMaterial({map, transparent: true, toneMapped: false}));
  label.position.z = .155; face.add(label);
  return {key, face};
};
const KeyStage = ({f}: {f: number}) => {
  const canvas = useRef<HTMLCanvasElement>(null); const stage = useRef<Stage | null>(null);
  const {delayRender, continueRender} = useDelayRender();
  useLayoutEffect(() => {
    const renderer = new THREE.WebGLRenderer({canvas: canvas.current!, alpha: true, antialias: true, preserveDrawingBuffer: true, powerPreference: 'high-performance'});
    renderer.setSize(1920, 1080, false); renderer.setPixelRatio(1);
    renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = .82;
    const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(39, 1920 / 1080, .1, 100);
    const studio = new THREE.Scene(); studio.background = new THREE.Color('#33312E');
    const lights: [V3, V3, string, number][] = [
      [[-6, 6, 7], [7, 4, 1], '#FFF8EE', 5], [[6, 2, 3], [1, 7, 1], '#F8E6CE', 4],
      [[0, 7, -5], [8, 1, 3], '#FFFFFF', 4], [[-4, -3, 3], [4, .4, 1], '#E4DDD5', 2],
    ];
    lights.forEach(([position, size, color, intensity]) => {
      const box = new THREE.Mesh(new THREE.BoxGeometry(...size), new THREE.MeshBasicMaterial({color: new THREE.Color(color).multiplyScalar(intensity)}));
      box.position.set(...position); box.lookAt(0, 0, 0); studio.add(box);
    });
    const generator = new THREE.PMREMGenerator(renderer), environment = generator.fromScene(studio, .08, .1, 100); generator.dispose();
    studio.traverse(obj => {if (obj instanceof THREE.Mesh) {obj.geometry.dispose(); (obj.material as THREE.Material).dispose();}});
    scene.environment = environment.texture;
    scene.add(new THREE.AmbientLight('#FFFFFF', .75));
    const main = new THREE.DirectionalLight('#FFF4E5', 1.25); main.position.set(-3, 6, 7); scene.add(main);
    const rim = new THREE.PointLight('#E7B68D', 12, 20); rim.position.set(6, -2, 4); scene.add(rim);
    const one = makeKey(), a = makeKey(), b = makeKey();
    const single = new THREE.Group(), pair = new THREE.Group(); single.add(one.key); pair.add(a.key, b.key); scene.add(single, pair);
    a.key.position.set(-1.5, 0, 0); a.key.rotation.y = .05;
    b.key.position.set(1.5, 0, -.1); b.key.rotation.y = -.04;
    stage.current = {renderer, scene, camera, single, pair, faces: [one.face, a.face, b.face], environment};
    return () => {
      stage.current = null;
      scene.traverse(obj => {if (obj instanceof THREE.Mesh) {obj.geometry.dispose(); const mat = obj.material as THREE.MeshBasicMaterial; mat.map?.dispose(); mat.dispose();}});
      environment.dispose(); renderer.dispose();
    };
  }, []);
  // Render the current frame directly; no second React root or animation clock.
  useLayoutEffect(() => {
    const s = stage.current; if (!s) return;
    const handle = delayRender('Drawing the key animation');
    const move = ease(f, 0, 165), double = ease(f, 480, 530) * (1 - ease(f, 565, 615));
    s.camera.position.set(lerp(.75, .12, move) + double * 1.1, lerp(1.45, .3, move) + double * 1.1, lerp(10.4, 12.4, move) - double * 2.8);
    s.camera.lookAt(0, .05, 0); s.camera.updateProjectionMatrix();
    const into = ease(f, 167, 219), away = ease(f, 446, 488);
    s.single.visible = f < 488;
    s.single.position.set(lerp(2.7, -.75, into), lerp(.1, -2.2, into) - away * 4, -away * 3);
    s.single.rotation.set(lerp(lerp(-.4, -.2, ease(f, 0, 150)), -.1, into), lerp(lerp(-.72, -.26, ease(f, 0, 150)), .12, into), lerp(-.16, .08, into));
    s.single.scale.setScalar(lerp(1.7, .64, into));
    s.pair.visible = f >= 478 && f < 624;
    s.pair.position.set(.65, -.1, 0); s.pair.rotation.set(-.16, -.12 + ease(f, 480, 600) * .3, -.1);
    s.pair.scale.setScalar(enter(f, 478, 40) * (1 - ease(f, 578, 624)));
    [169, 499, 529].forEach((at, i) => {s.faces[i].position.z = -pulse(f, at) * .07;});
    s.renderer.render(s.scene, s.camera); s.renderer.getContext().finish(); continueRender(handle);
  }, [f, delayRender, continueRender]);
  return <canvas ref={canvas} width={1920} height={1080} style={{position: 'absolute', width: 1920, height: 1080, zIndex: 2}} />;
};
const Recording = ({f}: {f: number}) => {
  const p = enter(f, 211) * (1 - ease(f, 401, 437));
  return <div style={{position: 'absolute', left: 1140, top: 860, zIndex: 2, display: 'flex', alignItems: 'center', gap: 26, padding: '17px 26px', borderRadius: 23, background: '#2D2923', border: '1px solid #51483B', boxShadow: '0 12px 35px #0003', opacity: p, transform: `translateY(${(1 - p) * 20}px)`}}>
    <span style={{width: 7, height: 7, background: ORANGE, borderRadius: '50%'}} />
    <div style={{display: 'flex', height: 26, gap: 4, alignItems: 'center'}}>{Array.from({length: 13}, (_, i) => <span key={i} style={{width: 3, height: 5 + 21 * Math.sin(i / 12 * Math.PI) * (.65 + .35 * Math.sin(f * .14 + i * .8)), borderRadius: 2, background: '#E57950'}} />)}</div>
    <span style={{fontFamily: FONT, fontSize: 19, color: '#D5CAB9'}}>正在聆听</span>
  </div>;
};
const Reveal = ({f, start, children, style = {}}: {f: number; start: number; children: React.ReactNode; style?: React.CSSProperties}) => {
  const p = enter(f, start, 50);
  return <div style={{opacity: ramp(f, start, start + 16), transform: `translateY(${(1 - p) * 32}px)`, filter: `blur(${(1 - p) * 4}px)`, ...style}}>{children}</div>;
};
const BirdMark = ({size = 34}: {size?: number}) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={ORANGE} strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round">{BIRD.map((d, i) => <path key={i} d={d} />)}</svg>;
const Window = ({f, agent = false}: {f: number; agent?: boolean}) => {
  const start = agent ? 596 : 180; const ending = agent ? ease(f, 902, 959) : ease(f, 446, 495);
  const p = enter(f, start, 54); const count = Math.floor(ramp(f, 225, 368) * 19);
  const a = '周五下午三点，', b = '和团队聊聊新设计。'; const reply = enter(f, 690, 40);
  const tilt = lerp(-5, 1.3, ease(f, start + 35, agent ? 900 : 446));
  return <div style={{position: 'absolute', left: 798, top: 282, width: 830, height: 534, zIndex: 1, fontFamily: FONT, color: INK, perspective: 1800, opacity: ramp(f, start, start + 18) * (1 - ending)}}>
    <div style={{width: '100%', height: '100%', borderRadius: 24, border: '1px solid #FFFFFF70', background: '#FCFAF5', overflow: 'hidden', boxSizing: 'border-box', boxShadow: '0 5px 0 #B9AD9C, 0 22px 45px #00000028, 0 55px 110px #00000018', transform: `translate3d(${(1 - p) * 145 + ending * 550}px, ${(1 - p) * 48}px, ${-ending * 250}px) rotateY(${tilt - ending * 25}deg) rotateZ(-1.5deg) scale(${.94 + .06 * p - ending * .14})`, transformOrigin: 'center center'}}>
      <div style={{height: 59, borderBottom: '1px solid #E9E3D9', display: 'flex', alignItems: 'center', gap: 28, padding: '0 30px', color: '#9B9286', fontSize: 15}}>
        <div style={{display: 'flex', gap: 8}}>{['#D6C9B8', '#DACDBA', '#CBCDBA'].map(color => <span key={color} style={{width: 8, height: 8, borderRadius: '50%', background: color}} />)}</div>
        {agent ? 'Voice Agent' : '备忘录'}
      </div>
      <div style={{padding: '33px 52px'}}>
        <div style={{fontSize: 16, color: '#968C7F', marginBottom: 20}}>{agent ? '示例：翻译选中的文字' : '灵感随记'}</div>
        {agent ? <>
          <span style={{fontSize: 27, fontWeight: 450, background: '#EEDCCA80', padding: '3px 4px', borderRadius: 4}}>周五下午三点，和团队聊聊新设计。</span>
          <div style={{display: 'flex', justifyContent: 'flex-end', marginTop: 30}}><div style={{padding: '18px 27px', borderRadius: '24px 24px 6px 24px', background: '#F0E6D9', fontSize: 23}}>把这段话翻成英文。</div></div>
          <div style={{marginTop: 30, padding: '19px 25px 24px', borderRadius: 17, background: '#F2EEE6', opacity: reply, transform: `translateY(${(1 - reply) * 18}px)`}}>
            <div style={{fontSize: 13, fontWeight: 550, color: ORANGE, marginBottom: 14, letterSpacing: .6}}>KUKU</div>
            <div style={{fontSize: 24, lineHeight: 1.5}}>Let’s meet this Friday at 3<br />to talk about the new design.</div>
          </div>
        </> : <>
          <div style={{fontSize: 30, fontWeight: 550}}>下一件想做的事</div>
          <div style={{fontSize: 29, lineHeight: 1.85, marginTop: 48, minHeight: 108}}>
            <div>{a.slice(0, Math.min(count, a.length))}{count <= a.length && <span style={{display: 'inline-block', width: 2, height: 29, background: ORANGE, marginLeft: 7, verticalAlign: '-4px'}} />}</div>
            <div>{b.slice(0, Math.max(0, count - a.length))}{count > a.length && <span style={{display: 'inline-block', width: 2, height: 29, background: ORANGE, marginLeft: 7, verticalAlign: '-4px'}} />}</div>
          </div>
          <div style={{fontSize: 15, color: '#A1988B', marginTop: 65}}>文字输入到当前光标处</div>
        </>}
      </div>
      <div style={{position: 'absolute', bottom: 0, height: 43, left: 0, right: 0, display: 'flex', justifyContent: 'flex-end', alignItems: 'center', paddingRight: 37, color: ORANGE, fontSize: 13, borderTop: '1px solid #E9E3D9'}}>{agent ? 'Fn Fn · Voice Agent' : 'Fn · 语音输入'}</div>
    </div>
  </div>;
};
const Overlay = ({f}: {f: number}) => {
  const final = ease(f, 931, 984);
  return <AbsoluteFill style={{fontFamily: FONT, color: CREAM, zIndex: 3, pointerEvents: 'none'}}>
    <div style={{position: 'absolute', left: 96, top: 70, display: 'flex', gap: 10, alignItems: 'center', opacity: 1 - final}}><BirdMark /><span style={{fontSize: 29, fontWeight: 650, letterSpacing: -1.2}}>SayKuku<span style={{display: 'inline-block', width: 6, height: 6, borderRadius: '50%', marginLeft: 2, background: ORANGE}} /></span></div>
    {f < 180 && <div style={{position: 'absolute', left: 130, top: 337, opacity: 1 - ease(f, 150, 180)}}>
      <Reveal f={f} start={13} style={{fontSize: 86, fontWeight: 550, lineHeight: 1.34, letterSpacing: -3}}>让想法，<br /><span style={{color: '#E57950'}}>脱口而出。</span></Reveal>
      <Reveal f={f} start={46} style={{fontSize: 25, color: '#A69E92', marginTop: 30}}>Mac 上的语音输入与语音助手</Reveal>
    </div>}
    {f >= 180 && f < 480 && <div style={{position: 'absolute', left: 130, top: 355, opacity: 1 - ease(f, 445, 480)}}>
      <Reveal f={f} start={194} style={{fontSize: 21, color: '#E57950', marginBottom: 26}}>Fn · 语音输入</Reveal>
      <Reveal f={f} start={202} style={{fontSize: 61, fontWeight: 500, lineHeight: 1.42, letterSpacing: -2}}>按一下 Fn，<br />说话就能输入。</Reveal>
      <Reveal f={f} start={230} style={{fontSize: 25, color: '#A69E92', marginTop: 30}}>文字落在当前光标处。</Reveal>
    </div>}
    {f >= 480 && f < 600 && <div style={{position: 'absolute', left: 0, top: 173, width: '100%', textAlign: 'center', opacity: 1 - ease(f, 571, 600)}}><Reveal f={f} start={487} style={{fontSize: 66, fontWeight: 500, letterSpacing: -2}}>连按两次 Fn，唤起语音助手。</Reveal></div>}
    {f >= 600 && f < 955 && <div style={{position: 'absolute', left: 130, top: 355, opacity: 1 - ease(f, 902, 955)}}>
      <Reveal f={f} start={612} style={{fontSize: 21, color: '#E57950', marginBottom: 26}}>Fn Fn · Voice Agent</Reveal>
      <Reveal f={f} start={623} style={{fontSize: 61, fontWeight: 500, lineHeight: 1.42, letterSpacing: -2}}>双击 Fn，<br />说出你的要求。</Reveal>
      <Reveal f={f} start={652} style={{fontSize: 25, color: '#A69E92', marginTop: 30}}>不选文字，也能提问、起草。</Reveal>
    </div>}
    {f >= 951 && <Reveal f={f} start={961} style={{position: 'absolute', left: 516, top: 361}}><BirdMark size={180} /></Reveal>}
    {f >= 951 && <div style={{position: 'absolute', left: 744, top: 327, color: INK}}>
      <Reveal f={f} start={961} style={{fontFamily: '"Avenir Next", sans-serif', fontSize: 129, fontWeight: 700, letterSpacing: -6}}>SayKuku<span style={{display: 'inline-block', width: 16, height: 16, borderRadius: '50%', marginLeft: 3, background: ORANGE}} /></Reveal>
      <Reveal f={f} start={977} style={{fontSize: 41, color: '#81756A', marginTop: 6}}>Just Say It.</Reveal>
      <Reveal f={f} start={999} style={{fontSize: 35, marginTop: 35, letterSpacing: -.5}}>下一句话，交给 Kuku。</Reveal>
      <Reveal f={f} start={1024} style={{fontSize: 26, color: ORANGE, marginTop: 33}}>say.anikuku.com <span style={{paddingLeft: 20}}>↗</span></Reveal>
      <Reveal f={f} start={1048} style={{fontSize: 19, color: '#91867A', marginTop: 35, lineHeight: 1.9}}>macOS 15+ · 免费开源<br />自备 Qwen API Key，模型调用费用由你的 Qwen 账号承担。</Reveal>
    </div>}
    {f >= 218 && f < 926 && <div style={{position: 'absolute', right: 96, bottom: 50, fontSize: 16, color: '#827C72', opacity: ramp(f, 218, 240) * (1 - ease(f, 900, 926))}}>功能示意 · 非实际录屏</div>}
  </AbsoluteFill>;
};
export const SayKukuFilm = () => {
  const f = useCurrentFrame(); const light = ease(f, 931, 984);
  return <AbsoluteFill style={{background: '#171612', overflow: 'hidden'}}>
    <Html5Audio src={staticFile('score.wav')} />
    <AbsoluteFill style={{background: 'radial-gradient(ellipse at 68% 46%, #36312A 0%, #1C1A16 46%, #12110F 100%)'}} />
    <AbsoluteFill style={{opacity: light, background: 'radial-gradient(ellipse at 32% 45%, #FFFFFF 0%, #FCF8F1 48%, #EFE8DC 100%)'}} />
    <div style={{position: 'absolute', left: 1050, top: 742, width: f < 923 ? 570 : 600, height: 85, background: '#070503', borderRadius: '50%', filter: 'blur(45px)', opacity: f < 180 ? .28 : 0, transform: 'rotate(-8deg)'}} />
    {f < 624 && <KeyStage f={f} />}
    {f >= 180 && f < 495 && <Window f={f} />}
    {f >= 596 && f < 959 && <Window f={f} agent />}
    {f >= 211 && f < 450 && <Recording f={f} />}
    <Overlay f={f} />
  </AbsoluteFill>;
};
