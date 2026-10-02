import {useLayoutEffect, useRef} from 'react';
import {useDelayRender} from 'remotion';
import * as THREE from 'three';
import {RoundedBoxGeometry} from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import {C, T, clamp, lerp, out, smooth} from './theme';

const W = 1920, H = 1080, U = 2.2, CAP = 2.0;
type V3 = [number, number, number];

/** How far the Fn cap is pressed (0–1): a quick stroke, then a springy release. */
export const pressDepth = (f: number) => Math.max(0, ...T.keyPresses.map(at => {
  const t = f - at;
  if (t < 0 || t > 30) return 0;
  if (t < 3) return t / 3;
  if (t < 6) return 1;
  return Math.max(0, Math.exp(-(t - 6) / 4) * Math.cos((t - 6) / 3.2));
}));

/** Coral light leaking under the cap, peaking at each press. */
export const glow = (f: number) => Math.min(1.4, T.keyPresses.reduce((sum, at) => sum + (f >= at ? Math.exp(-(f - at) / 16) : 0), 0));

const look = (from: V3, to: V3, fov: number) => ({from, to, fov});
// One continuous camera per segment; frames are the only clock.
export const cameraAt = (f: number) => {
  if (f < 720) {
    const reveal = smooth(f, 130, 180), drift = out(f, 180, 300), whip = smooth(f, 296, 330) ** 2;
    const from: V3 = [lerp(lerp(-1.2, -0.9, reveal), -2.1, drift), lerp(lerp(-4.6, -3.7, reveal), -4.5, drift), lerp(lerp(5.4, 4.4, reveal), 5.6, drift)];
    const to: V3 = [lerp(0.15, 2.5, drift) + whip * 9, lerp(0.2, 0.7, drift), 0];
    return look(from, to, 36);
  }
  const push = smooth(f, 806, 840) ** 2.2;
  const from: V3 = [lerp(1.4, 0.4, smooth(f, 720, 806)), lerp(-3.4, -2.6, smooth(f, 720, 806)), lerp(lerp(8.4, 7.2, smooth(f, 720, 806)), 1.0, push)];
  return look(from, [lerp(0.9, 0, push), lerp(0.7, 0, push), 0], 36);
};

const makeCamera = (f: number) => {
  const {from, to, fov} = cameraAt(f);
  const camera = new THREE.PerspectiveCamera(fov, W / H, 0.05, 100);
  camera.up.set(0, 0, 1);
  camera.position.set(...from); camera.lookAt(...to); camera.updateMatrixWorld(); camera.updateProjectionMatrix();
  return camera;
};

/** Screen position of the Fn cap, so 2D effects stay pinned to the key. */
export const keyOnScreen = (f: number) => {
  const p = new THREE.Vector3(0, 0, 0.3).project(makeCamera(f));
  return {x: (p.x + 1) / 2 * W, y: (1 - p.y) / 2 * H};
};

const canvasTexture = (draw: (ctx: CanvasRenderingContext2D, size: number) => void) => {
  const size = 1024, canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  draw(canvas.getContext('2d')!, size);
  const map = new THREE.CanvasTexture(canvas);
  map.colorSpace = THREE.SRGBColorSpace; map.anisotropy = 8;
  return map;
};

const globe = (ctx: CanvasRenderingContext2D, x: number, y: number, r: number) => {
  ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke();
  ctx.beginPath(); ctx.ellipse(x, y, r * 0.45, r, 0, 0, Math.PI * 2); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(x - r, y); ctx.lineTo(x + r, y); ctx.stroke();
  for (const dy of [-0.5, 0.5]) {
    const half = Math.sqrt(1 - dy * dy) * r;
    ctx.beginPath(); ctx.moveTo(x - half, y + dy * r); ctx.lineTo(x + half, y + dy * r); ctx.stroke();
  }
};

// Legends follow the Mac layout: symbol top right, name bottom left.
const legend = (symbol: string, name: string, aspect: number) => canvasTexture((ctx, size) => {
  ctx.fillStyle = '#E9E6E1'; ctx.strokeStyle = '#E9E6E1'; ctx.lineWidth = 9; ctx.textBaseline = 'alphabetic';
  ctx.save(); ctx.scale(1 / aspect, 1);
  const width = size * aspect;
  if (name === 'fn') {
    ctx.font = '500 230px "Inter Variable"'; ctx.textAlign = 'right'; ctx.fillText('fn', width - 120, 300);
    globe(ctx, 210, size - 210, 82);
  } else {
    ctx.font = '400 150px "Inter Variable"'; ctx.textAlign = 'right'; ctx.fillText(symbol, width - 120, 250);
    ctx.font = '500 104px "Inter Variable"'; ctx.textAlign = 'left'; ctx.fillText(name, 110, size - 130);
  }
  ctx.restore();
});

const coralGlow = () => canvasTexture((ctx, size) => {
  const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  g.addColorStop(0, '#FF9A6E'); g.addColorStop(0.35, C.coral); g.addColorStop(1, '#ED412E00');
  ctx.fillStyle = g; ctx.fillRect(0, 0, size, size);
});

type Key = {group: THREE.Group; cap: THREE.Group};
const makeKey = (units: number, symbol: string, name: string): Key => {
  const w = CAP + (units - 1) * U, group = new THREE.Group(), cap = new THREE.Group();
  const body = new THREE.Mesh(new RoundedBoxGeometry(w, CAP, 0.42, 6, 0.16), new THREE.MeshPhysicalMaterial({color: '#1C1C1D', roughness: 0.5, metalness: 0.15, clearcoat: 0.35, clearcoatRoughness: 0.45}));
  body.position.z = 0.21; cap.add(body);
  const label = new THREE.Mesh(new THREE.PlaneGeometry(w - 0.08, CAP - 0.08), new THREE.MeshBasicMaterial({map: legend(symbol, name, w / CAP), transparent: true, toneMapped: false, opacity: 0.92}));
  label.position.z = 0.425; cap.add(label);
  group.add(cap);
  return {group, cap};
};

type Stage = {renderer: THREE.WebGLRenderer; scene: THREE.Scene; fn: Key; glowPlane: THREE.Mesh<THREE.PlaneGeometry, THREE.MeshBasicMaterial>; underLight: THREE.PointLight; sweep: THREE.SpotLight; env: THREE.WebGLRenderTarget};

const build = (canvas: HTMLCanvasElement): Stage => {
  const renderer = new THREE.WebGLRenderer({canvas, alpha: true, antialias: true, preserveDrawingBuffer: true});
  renderer.setSize(W, H, false); renderer.setPixelRatio(1);
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1;
  const scene = new THREE.Scene();

  // A small studio baked into an environment map gives the caps soft, believable highlights.
  const studio = new THREE.Scene(); studio.background = new THREE.Color('#0B0A09');
  const panels: [V3, V3, string, number][] = [[[-6, 4, 8], [8, 3, 1], '#FFF6EC', 3], [[7, -2, 4], [1, 8, 1], '#FFD9C2', 1.4], [[0, 8, 3], [10, 1, 2], '#FFFFFF', 1.2]];
  for (const [position, size, color, power] of panels) {
    const box = new THREE.Mesh(new THREE.BoxGeometry(...size), new THREE.MeshBasicMaterial({color: new THREE.Color(color).multiplyScalar(power)}));
    box.position.set(...position); box.lookAt(0, 0, 0); studio.add(box);
  }
  const pmrem = new THREE.PMREMGenerator(renderer), env = pmrem.fromScene(studio, 0.04); pmrem.dispose();
  studio.traverse(o => {if (o instanceof THREE.Mesh) {o.geometry.dispose(); (o.material as THREE.Material).dispose();}});
  scene.environment = env.texture;

  scene.add(new THREE.AmbientLight('#FFFFFF', 0.12));
  const key = new THREE.DirectionalLight('#FFF1E0', 1.6); key.position.set(-5, -3, 9); scene.add(key);
  const rim = new THREE.DirectionalLight('#FFC9A8', 0.9); rim.position.set(6, 6, 2); scene.add(rim);
  const sweep = new THREE.SpotLight('#FFFFFF', 0, 30, 0.35, 0.8); sweep.position.set(-6, -6, 8); scene.add(sweep, sweep.target);

  // Anodized deck with a recessed well around the keys.
  const deck = new THREE.Mesh(new RoundedBoxGeometry(40, 30, 0.6, 4, 0.2), new THREE.MeshPhysicalMaterial({color: '#2A2A2B', metalness: 0.85, roughness: 0.38}));
  deck.position.set(6, 6, -0.32); scene.add(deck);

  const layout: [number, string, string, number, number][] = [
    [1, '', 'fn', 0, 0], [1, '⌃', 'control', U, 0], [1, '⌥', 'option', 2 * U, 0], [1.3, '⌘', 'command', 3.15 * U, 0],
    [2.3, '⇧', 'shift', 0.65 * U, U], [1, 'Z', '', 2.3 * U, U], [1, 'X', '', 3.3 * U, U], [1, 'C', '', 4.3 * U, U],
    [1, '⇥', 'tab', 0.2 * U, 2 * U], [1, 'Q', '', 1.7 * U, 2 * U], [1, 'W', '', 2.7 * U, 2 * U],
  ];
  const keys = layout.map(([units, symbol, name, x, y]) => {
    const k = makeKey(units, symbol, name); k.group.position.set(x, y, 0); scene.add(k.group); return k;
  });

  const glowPlane = new THREE.Mesh(new THREE.PlaneGeometry(CAP * 2.4, CAP * 2.4), new THREE.MeshBasicMaterial({map: coralGlow(), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false, opacity: 0}));
  glowPlane.position.z = 0.02; scene.add(glowPlane);
  const underLight = new THREE.PointLight(C.coral, 0, 7, 1.6); underLight.position.set(0, 0, -0.05); scene.add(underLight);
  return {renderer, scene, fn: keys[0], glowPlane, underLight, sweep, env};
};

export const KeyStage = ({f, opacity = 1}: {f: number; opacity?: number}) => {
  const canvas = useRef<HTMLCanvasElement>(null), stage = useRef<Stage | null>(null);
  const {delayRender, continueRender, cancelRender} = useDelayRender();
  const ready = useRef<Promise<void> | null>(null);

  useLayoutEffect(() => {
    let disposed = false;
    // Legends are canvas text: wait for the face before drawing them.
    ready.current = document.fonts.load('500 100px "Inter Variable"', 'fncontrolptiomsh⌃⌥⌘⇧⇥ZXCQW').then(() => {
      if (!disposed) stage.current = build(canvas.current!);
    });
    return () => {
      disposed = true;
      const s = stage.current; stage.current = null; if (!s) return;
      s.scene.traverse(o => {
        if (!(o instanceof THREE.Mesh)) return;
        o.geometry.dispose(); const m = o.material as THREE.MeshBasicMaterial; m.map?.dispose(); m.dispose();
      });
      s.env.dispose(); s.renderer.dispose();
    };
  }, []);

  useLayoutEffect(() => {
    const handle = delayRender('Drawing the key');
    ready.current!.then(() => {
      const s = stage.current; if (!s) return continueRender(handle);
      const depth = pressDepth(f), light = glow(f);
      s.fn.cap.position.z = -0.24 * depth;
      s.glowPlane.material.opacity = clamp(light) * 0.95;
      s.glowPlane.scale.setScalar(1 + light * 0.25);
      s.underLight.intensity = light * 30;
      const pass = clamp((f - 134) / 70);
      s.sweep.intensity = f < 720 ? Math.sin(Math.PI * pass) * 60 : 0;
      s.sweep.target.position.set(lerp(-4, 8, pass), lerp(-2, 4, pass), 0);
      s.renderer.toneMappingExposure = f < 720 ? lerp(0.02, 1, smooth(f, 132, 176)) : 1;
      s.renderer.render(s.scene, makeCamera(f));
      s.renderer.getContext().finish();
      continueRender(handle);
    }).catch(cancelRender);
  }, [f, delayRender, continueRender, cancelRender]);

  return <canvas ref={canvas} width={W} height={H} style={{position: 'absolute', inset: 0, width: W, height: H, opacity}} />;
};
