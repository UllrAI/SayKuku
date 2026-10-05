import React, { useEffect, useLayoutEffect, useMemo, useState } from "react";
import {
  AbsoluteFill,
  Audio,
  continueRender,
  delayRender,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";
import { ThreeCanvas } from "@remotion/three";
import { useThree } from "@react-three/fiber";
import * as THREE from "three";
import { CUTS, PRESS_FRAMES } from "./beatmap-real";
const CORAL = "#ed412e";
const cl = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const p = (t: number, a: number, b: number) =>
  interpolate(t, [a, b], [0, 1], cl);
const ease = (x: number) => 1 - (1 - x) ** 3;
const mix = (a: number, b: number, x: number) => a + (b - a) * x;
const lineCN = "周五下午三点，和团队聊聊新设计。";
const lineEN =
  "Let’s get together this Friday at 3\nto talk about the new design.";
function shape(w: number, h: number, r: number, d: number) {
  const s = new THREE.Shape();
  s.moveTo(-w / 2 + r, -h / 2);
  s.lineTo(w / 2 - r, -h / 2);
  s.quadraticCurveTo(w / 2, -h / 2, w / 2, -h / 2 + r);
  s.lineTo(w / 2, h / 2 - r);
  s.quadraticCurveTo(w / 2, h / 2, w / 2 - r, h / 2);
  s.lineTo(-w / 2 + r, h / 2);
  s.quadraticCurveTo(-w / 2, h / 2, -w / 2, h / 2 - r);
  s.lineTo(-w / 2, -h / 2 + r);
  s.quadraticCurveTo(-w / 2, -h / 2, -w / 2 + r, -h / 2);
  return new THREE.ExtrudeGeometry(s, {
    depth: d,
    bevelEnabled: true,
    bevelSize: 0.025,
    bevelThickness: 0.025,
    bevelSegments: 3,
    curveSegments: 8,
    steps: 1,
  });
}
function Pane({
  tex,
  w = 8,
  h = 5.088,
  position = [0, 0.6, 0],
  rotation = [0, 0, 0],
  opacity = 1,
}: {
  tex: THREE.Texture;
  w?: number;
  h?: number;
  position?: [number, number, number];
  rotation?: [number, number, number];
  opacity?: number;
}) {
  const geo = useMemo(() => shape(w, h, 0.11, 0.07), [w, h]);
  return (
    <group position={position} rotation={rotation}>
      <mesh geometry={geo}>
        <meshStandardMaterial
          color="#bbc0c4"
          metalness={0.76}
          roughness={0.2}
          transparent
          opacity={opacity}
        />
      </mesh>
      <mesh position={[0, 0, 0.105]}>
        <planeGeometry args={[w - 0.025, h - 0.025]} />
        <meshBasicMaterial
          map={tex}
          transparent
          opacity={opacity}
          toneMapped={false}
        />
      </mesh>
    </group>
  );
}
function useAssets() {
  const [assets, setAssets] = useState<Record<string, THREE.Texture> | null>(
    null,
  );
  const [h] = useState(() => delayRender("Load verified SayKuku assets"));
  const { gl, scene, camera } = useThree();
  useEffect(() => {
    const loader = new THREE.TextureLoader();
    Promise.all(
      [
        ["home", "app-home.png"],
        ["key", "v2/fn.png"],
        ["glow", "v2/glow.png"],
      ].map(async ([k, url]) => {
        const tx = await loader.loadAsync(staticFile(url));
        tx.colorSpace = THREE.SRGBColorSpace;
        tx.anisotropy = 4;
        if (k === "home") {
          tx.repeat.set(1, 636 / 660);
          tx.offset.set(0, 0);
        }
        return [k, tx] as const;
      }),
    ).then((x) => setAssets(Object.fromEntries(x)));
  }, []);
  useLayoutEffect(() => {
    if (assets) {
      gl.render(scene, camera);
      continueRender(h);
    }
  }, [assets, h, gl, scene, camera]);
  return assets;
}
function useNote(t: number) {
 const stage=t<3.85?0:t<4.683?1:t<8.3?2:3;
 const cursor=Math.floor(t*3)%2===0;
 const defocus=(t>=1.4&&t<2.35)||(t>=5&&t<5.65);
  const texture = useMemo(() => {
    const c = document.createElement("canvas");
    c.width = 1600;
    c.height = 980;
    const x = c.getContext("2d")!;
    x.fillStyle = "#f9f8f5";
    x.fillRect(0, 0, 1600, 980);
    x.fillStyle = "#eeede9";
    x.fillRect(0, 0, 1600, 100);
    ["#ed756a", "#e9bc63", "#6ab982"].forEach((col, i) => {
      x.fillStyle = col;
      x.beginPath();
      x.arc(45 + i * 34, 47, 10, 0, 7);
      x.fill();
    });
    x.fillStyle = "#56534e";
    x.font = '27px "Noto Sans CJK SC",sans-serif';
    x.fillText("灵感随记", 680, 57);
    x.fillStyle = "#9d978e";
    x.font = '25px "Noto Sans CJK SC",sans-serif';
    x.fillText("今天的想法", 120, 210);
    x.fillStyle = "#292724";
    x.font = 'bold 58px "Noto Sans CJK SC",sans-serif';
    x.fillText("下一件想做的事", 120, 310);
    x.fillStyle = "#7d776e";
    x.font = '24px "Noto Sans CJK SC",sans-serif';
    x.fillText("想法不必等到你腾出双手。", 120, 376);
    x.strokeStyle = "#dedbd5";
    x.lineWidth = 2;
    x.beginPath();
    x.moveTo(120, 421);
    x.lineTo(1475, 421);
    x.stroke();
    x.font = '46px "Noto Sans CJK SC",sans-serif';
    if (t >= 3.85) {
      if (t < 8.3) {
        if (t >= 4.683 && t < 8.3) {
          x.fillStyle = "#c9dcf6";
          x.fillRect(
            112,
            464,
            Math.min(1330, x.measureText(lineCN).width + 20),
            71,
          );
        }
        x.fillStyle = "#292724";
        x.fillText(lineCN, 120, 518);
      } else {
        x.font = "47px Arial,sans-serif";
        x.fillStyle = "#292724";
        lineEN.split("\n").forEach((s, i) => x.fillText(s, 120, 518 + i * 76));
      }
    }
    if ((t < 3.85 || t >= 8.3) && Math.floor(t * 3) % 2 === 0) {
      const end =
        t < 3.85 ? 120 : 120 + x.measureText(lineEN.split("\n")[1]).width;
      x.fillStyle = CORAL;
      x.fillRect(end + 6, t < 3.85 ? 470 : 550, 3, 58);
    }
    x.fillStyle = "#bbb6ae";
    x.font = '22px "Noto Sans CJK SC",sans-serif';
    x.fillText("文本场景示意", 120, 900);
    let source = c;
    if ((t >= 1.4 && t < 2.35) || (t >= 5.0 && t < 5.65)) {
      const b = document.createElement("canvas");
      b.width = 1600;
      b.height = 980;
      const bc = b.getContext("2d")!;
      bc.filter = "blur(3px)";
      bc.drawImage(c, 0, 0);
      source = b;
    }
    const texture = new THREE.CanvasTexture(source);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = 4;
    return texture;
  }, [stage,cursor,defocus]);
  useEffect(() => () => texture.dispose(), [texture]);
  return texture;
}
function Rig() {
  const t = useCurrentFrame() / 60;
  const { camera } = useThree();
  let a: [number, number, number], q: [number, number, number];
  if (t < 1.4) {
    const k = ease(p(t, 0, 1.4));
    a = [mix(4.2, 0.7, k), mix(2.2, 1.5, k), mix(8.6, 9.8, k)];
    q = [0, 0.6, 0];
  } else if (t < 2.35) {
    const k = ease(p(t, 1.4, 2.3));
    a = [mix(-2.6, -2.1, k), mix(1.4, 1.7, k), mix(3.9, 4.8, k)];
    q = [-3.0, -0.7, 1.4];
  } else if (t < 4.683) {
    const k = ease(p(t, 2.35, 4.5));
    a = [mix(-1.5, 0.1, k), mix(1.35, 1.25, k), mix(9.7, 9.3, k)];
    q = [0, 0.5, 0];
  } else if (t < 5.65) {
    const k = ease(p(t, 4.683, 5.02));
    a = [mix(-1.3, -2.4, k), mix(1.5, 0.9, k), mix(8.0, 4.8, k)];
    q = [mix(-1, -3, k), mix(0.2, -1.05, k), mix(0.5, 1.4, k)];
  } else if (t < 6.566) {
    const k = ease(p(t, 5.65, 6.566));
    a = [mix(-2.4, -1, k), mix(0.9, 1.5, k), mix(4.8, 9, k)];
    q = [mix(-3, 0, k), mix(-1.05, 0.5, k), mix(1.4, 0, k)];
  } else if (t < 9.383) {
    const k = ease(p(t, 6.566, 9.383));
    a = [mix(0.7, 0, k), mix(1.8, 0.9, k), mix(9.3, 8.4, k)];
    q = [0, 0.6, 0];
  } else if (t < 12.183) {
    const k = ease(p(t, 9.383, 12.183));
    a = [mix(1.5, 0.1, k), mix(1.0, 0.8, k), mix(7.2, 8.7, k)];
    q = [0.1, 0.5, 0];
  } else {
    a = [0, 1.5, 10];
    q = [0, 0.6, 0];
  }
  useLayoutEffect(() => {
    camera.position.set(...a);
    camera.lookAt(...q);
    camera.rotation.z =
      t < 1.4
        ? -0.04
        : t >= 1.4 && t < 2.35
          ? -0.035
          : t >= 4.683 && t < 6.566
            ? 0.025
            : 0;
    camera.updateProjectionMatrix();
  }, [t]);
  return null;
}
function World() {
  const f = useCurrentFrame(),
    t = f / 60;
  const assets = useAssets();
  const note = useNote(t);
  const keyGeo = useMemo(() => shape(1.8, 1.8, 0.19, 0.32), []);
  const down = PRESS_FRAMES.some((fr) => f >= fr && f < fr + 6);
  const starGeo = useMemo(
    () =>
      new THREE.BufferGeometry().setFromPoints(
        Array.from(
          { length: 90 },
          (_, i) =>
            new THREE.Vector3(
              Math.sin(i * 57) * 18,
              Math.cos(i * 19) * 7,
              Math.sin(i * 33) * 14 - 6,
            ),
        ),
      ),
    [],
  );
  if (!assets) return null;
  return (
    <>
      <Rig />
      <color attach="background" args={["#071015"]} />
      <fog attach="fog" args={["#071015", 16, 38]} />
      <ambientLight intensity={0.75} />
      <directionalLight position={[1, 7, 6]} intensity={2.4} color="#f4ece0" />
      <pointLight position={[-5, 1, 4]} color="#f38765" intensity={48} />
      <pointLight position={[5, 1, 1]} color="#a2d9e5" intensity={45} />
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -2.4, 0]}>
        <planeGeometry args={[100, 100]} />
        <meshStandardMaterial color="#0b1a20" metalness={0.8} roughness={0.3} />
      </mesh>
      <sprite position={[0, 1, -4]} scale={[13, 10, 1]}>
        <spriteMaterial
          map={assets.glow}
          color="#517c86"
          transparent
          opacity={0.22}
          depthWrite={false}
          blending={THREE.AdditiveBlending}
        />
      </sprite>
      <points geometry={starGeo}>
        <pointsMaterial
          map={assets.glow}
          color="#b1c9cf"
          size={0.12}
          transparent
          opacity={0.3}
          depthWrite={false}
        />
      </points>
      {t < 1.4 ? (
        <Pane tex={assets.home} rotation={[0, -0.04, 0]} />
      ) : t < 12.183 ? (
        <Pane
          tex={note}
          w={8.8}
          h={5.39}
          position={[0.25, 0.7, -0.2]}
          rotation={[0, 0.015, 0]}
        />
      ) : (
        <Pane
          tex={assets.home}
          w={7.5}
          h={4.77}
          position={[0, 0.55, -5]}
          rotation={[0, -0.15, 0]}
          opacity={0.12}
        />
      )}
      {t >= 1.4 && t < 6.566 && (
        <group
          position={[-3.15, down ? -1.71 : -1.58, 1.7]}
          rotation={[-Math.PI / 2, 0, -0.055]}
        >
          <mesh geometry={keyGeo}>
            <meshStandardMaterial
              color={down ? "#a53c2b" : "#263238"}
              metalness={0.58}
              roughness={0.25}
            />
          </mesh>
          <mesh position={[0, 0, 0.365]}>
            <planeGeometry args={[1.7, 1.7]} />
            <meshBasicMaterial
              map={assets.key}
              transparent
              toneMapped={false}
            />
          </mesh>
          <mesh position={[0, 0, -0.08]}>
            <boxGeometry args={[1.95, 1.95, 0.15]} />
            <meshStandardMaterial
              color="#849095"
              metalness={0.75}
              roughness={0.2}
            />
          </mesh>
        </group>
      )}
    </>
  );
}
function Wave({ f }: { f: number }) {
  return (
    <div
      style={{
        width: 22,
        height: 15,
        display: "flex",
        alignItems: "center",
        gap: 2.5,
      }}
    >
      {[0, 1, 2, 3, 4].map((i) => (
        <div
          key={i}
          style={{
            width: 2,
            borderRadius: 2,
            height:
              4 +
              11 *
                (0.5 + 0.5 * Math.sin(f * 0.16 + i * 0.9)) *
                (1 - Math.abs(i - 2) * 0.18),
            background: CORAL,
          }}
        />
      ))}
    </div>
  );
}
function Pill() {
  const f = useCurrentFrame(),
    t = f / 60;
  let state = "";
  let agent = false;
  if (t >= 1.88 && t < 3.45) state = "listening";
  else if (t >= 3.45 && t < 4.05) state = "processing";
  else if (t >= 4.05 && t < 4.58) state = "inserted";
  else if (t >= 5.15 && t < 7.2) {
    state = "listening";
    agent = t >= 5.383;
  } else if (t >= 7.2 && t < 7.65) state = "understand";
  else if (t >= 7.65 && t < 8.45) state = "running";
  else if (t >= 8.45 && t < 11.7) state = "done";
  if (!state) return null;
  const listen = state === "listening",
    success = state === "inserted" || state === "done";
  const width = listen
    ? 208
    : state === "inserted"
      ? 139
      : state === "done"
        ? 135
        : state === "running"
          ? 214
          : 145;
  const label = listen
    ? "正在听…"
    : state === "processing"
      ? "正在识别…"
      : state === "understand"
        ? "正在理解…"
        : state === "running"
          ? "正在执行 · 翻译成英文"
          : state === "inserted"
            ? "已输入"
            : "已完成";
  return (
    <div
      style={{
        position: "absolute",
        left: "50%",
        bottom: 98,
        width: width * 3,
        height: 108,
        transform: "translateX(-50%)",
        filter:
          "drop-shadow(0 14px 24px #0007) drop-shadow(0 0 26px #ffb09018)",
      }}
    >
      <div
        style={{
          width,
          height: 36,
          transform: "scale(3)",
          transformOrigin: "left top",
          background:
            "linear-gradient(150deg,rgba(248,246,241,.95),rgba(226,226,219,.90))",
          borderRadius: 36,
          padding: "0 8px",
          boxSizing: "border-box",
          border: "0.4px solid #ffffffbb",
          display: "flex",
          alignItems: "center",
          gap: 8,
          color: success ? "#615e59" : "#1c1b19",
          fontFamily: 'Arial,"Noto Sans CJK SC",sans-serif',
          fontSize: 13,
          fontWeight: 600,
        }}
      >
        {listen ? (
          <>
            <div
              style={{
                width: 24,
                height: 24,
                borderRadius: 24,
                background: "#0000000c",
                display: "grid",
                placeItems: "center",
                color: "#625e59",
                fontSize: 12,
              }}
            >
              ×
            </div>
            <div style={{ display: "flex", gap: 4, alignItems: "center" }}>
              <div style={{ width: 16, color: CORAL, fontSize: 18 }}>
                {agent ? "✦" : ""}
              </div>
              <Wave f={f} />
            </div>
            <span style={{ whiteSpace: "nowrap" }}>{label}</span>
            <div style={{ flex: 1 }} />
            <div
              style={{
                width: 24,
                height: 24,
                borderRadius: 24,
                background: "#d93826",
                color: "white",
                display: "grid",
                placeItems: "center",
                fontSize: 12,
              }}
            >
              ✓
            </div>
          </>
        ) : success ? (
          <>
            <span style={{ color: "#349368", fontSize: 15 }}>✓</span>
            <span>{label}</span>
            <div style={{ flex: 1 }} />
            <span style={{ color: "#c73321" }}>撤销</span>
          </>
        ) : (
          <>
            <span
              style={{
                color: state === "processing" ? "#777" : CORAL,
                fontSize: 18,
                transform: `rotate(${f * 8}deg)`,
                width: 18,
              }}
            >
              {state === "processing" ? "◌" : "✦"}
            </span>
            <span style={{ whiteSpace: "nowrap" }}>{label}</span>
            <div style={{ flex: 1 }} />
            <span
              style={{
                width: 24,
                height: 24,
                borderRadius: 24,
                background: "#0000000c",
                display: "grid",
                placeItems: "center",
                fontSize: 12,
              }}
            >
              ×
            </span>
          </>
        )}
      </div>
    </div>
  );
}
const Bird = () => (
  <svg width="120" height="120" viewBox="0 0 64 64">
    <path
      d="M10 49 31 17C39 5 51 15 50 27 49 41 38 46 14 43M27 25C40 38 28 44 14 43M28 46v8m10-10v10m12-30h5"
      fill="none"
      stroke={CORAL}
      strokeWidth="3.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <circle cx="42" cy="21" r="2.2" fill={CORAL} />
  </svg>
);
export function PromoReal() {
  const f = useCurrentFrame(),
    t = f / 60;
  const cut = CUTS.filter((x) => x <= f).at(-1) || 0;
  const flash = Math.max(0, 0.085 - (f - cut) * 0.028);
  const title =
    t < 1.4
      ? "让想法，脱口而出。"
      : t < 2.35
        ? "按一下 Fn。"
        : t < 4.683
          ? "说完，就写入。"
          : t < 6.566
            ? "连按两次 Fn。"
            : t < 9.383
              ? "选中，开口，直接改写。"
              : "说出想法，直接写入。";
  return (
    <AbsoluteFill
      style={{
        background: "#071015",
        color: "#f7f3eb",
        fontFamily: '"Noto Sans CJK SC",Arial,sans-serif',
        overflow: "hidden",
      }}
    >
      <ThreeCanvas
        width={1920}
        height={1080}
        dpr={0.8}
        camera={{ fov: 46, near: 0.05, far: 80 }}
        gl={{ alpha: false, antialias: true }}
      >
        <World />
      </ThreeCanvas>
      <AbsoluteFill
        style={{
          pointerEvents: "none",
          background:
            "linear-gradient(0deg,#03101599,transparent 25%,transparent 75%,#03101544)",
        }}
      />
      {t < 12.183 && (
        <>
          <div
            style={{
              position: "absolute",
              left: 70,
              top: 48,
              fontSize: 25,
              fontWeight: 700,
              color: "#f6eee1",
            }}
          >
            SayKuku<span style={{ color: CORAL }}>.</span>
          </div>
          <div
            style={{
              position: "absolute",
              right: 70,
              top: 53,
              fontSize: 18,
              color: "#9aacb0",
            }}
          >
            JUST SAY IT.
          </div>
          <div
            style={{
              position: "absolute",
              left: 75,
              bottom: 32,
              fontSize: 41,
              fontWeight: 650,
              letterSpacing: -1,
              textShadow: "0 4px 24px #000",
            }}
          >
            {title}
          </div>
          <div
            style={{
              position: "absolute",
              right: 70,
              bottom: 40,
              fontSize: 16,
              color: "#9bacaf",
            }}
          >
            {t < 1.4 ? "官网开发版真实界面" : "按产品源码还原的交互演示"}
          </div>
          <Pill />
          {t >= 6.566 && t < 7.2 && (
            <div
              style={{
                position: "absolute",
                right: 95,
                top: 198,
                color: "#fff6ee",
                fontSize: 38,
                padding: "18px 30px",
                borderLeft: `4px solid ${CORAL}`,
                background: "#081519d9",
              }}
            >
              “翻译成英文。”
            </div>
          )}
        </>
      )}
      {t >= 12.183 && (
        <AbsoluteFill
          style={{
            alignItems: "center",
            justifyContent: "center",
            opacity: ease(p(t, 12.183, 12.6)),
            transform: `scale(${mix(1.12, 1, ease(p(t, 12.183, 12.8)))})`,
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 20,
              fontFamily: "Arial,sans-serif",
              fontSize: 145,
              fontWeight: 800,
              letterSpacing: -7,
            }}
          >
            <Bird />
            SayKuku<span style={{ color: CORAL, marginLeft: -22 }}>.</span>
          </div>
          <div
            style={{
              width: 650,
              height: 2,
              background:
                "linear-gradient(90deg,transparent,#e66545,#ffd8bb,transparent)",
              boxShadow: "0 0 22px #f76a4488",
              marginTop: 27,
            }}
          />
          <div style={{ fontSize: 41, marginTop: 36 }}>
            下一句话，交给 Kuku。
          </div>
          <div style={{ fontSize: 28, marginTop: 39, color: "#e0cbc0" }}>
            say.anikuku.com
          </div>
          <div
            style={{
              position: "absolute",
              bottom: 65,
              fontSize: 19,
              color: "#aab1af",
            }}
          >
            macOS 14+ · 自备 Qwen API Key · 模型调用按账号计费
          </div>
        </AbsoluteFill>
      )}
      <AbsoluteFill
        style={{ background: "#f7f0e8", opacity: flash, pointerEvents: "none" }}
      />
      <Audio src={staticFile("score-final.wav")} />
    </AbsoluteFill>
  );
}
