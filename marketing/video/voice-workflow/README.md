# SayKuku 语音工作流演示 · Voice Workflow

15 秒，1920 × 1080，原生 60 fps。Remotion + Three.js；原创 128 BPM 配乐。

本版只借鉴参考视频的镜头、节奏和空间感，内容完全围绕 SayKuku：真实开发版首页、一次 Fn 听写、同一个 Fn 键连按两次、选中文本就地翻译、完成和撤销。

## 运行

需要 Node.js 22+、Python 3.11+、FFmpeg 和 Remotion Chrome Headless Shell。中文建议安装 Noto Sans CJK SC。

```sh
npm ci
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r scripts/requirements.txt
npm run audio
npm run typecheck
npx remotion browser ensure
npm run studio
npm run render
```

最终输出：
- `out/SayKuku-final.mp4`：H.264 + AAC-LC192kb/s，48kHz立体声，默认音轨、faststart
- `out/SayKuku-final-soundtrack.mp3`：独立音轨

受限云环境若无法枚举网卡、但支持 localhost，可用：

```sh
NODE_OPTIONS="--require=$PWD/scripts/loopback-fallback.cjs" npm run render
```

此脚本仅对不可用的网卡枚举提供 loopback 回退，不改变权限或网络设置。

## 编辑位置

- `src/PromoReal.tsx`：3D 舞台、单个 Fn 实体键、相机、文本场景和真实结构的浮动胶囊
- `src/beatmap-real.ts`：60fps、128BPM、镜头切点与按键瞬态
- `src/index.tsx`：composition
- `public/app-home.png`：官网真实开发版首页；画面裁去顶部屏幕共享指示器
- `public/v2/fn.png`、`public/v2/glow.png`：按键标签与舞台光晕
- `public/score-final.wav`：无第三方采样的原创配乐
- `scripts/make_score_final.py`：读取同一 beatmap 的音轨生成器，需要 NumPy、SciPy 和 FFmpeg
- `scripts/mux-compatible.sh`：兼容音轨与独立 MP3 导出

## 工作流与真实性

1. 真实开发版首页短暂展示
2. 单个 Fn 键按下、释放，出现按源码比例还原的 208×36 听写胶囊
3. 听取过程中输入区域保持空白；录音结束、识别后才出现文字
4. 选中同一输入区域的文字
5. 同一个 Fn 键完成两次清楚的按下、释放；没有并列的两个 Fn 键
6. 同一胶囊增加珊瑚色 sparkle，随后显示理解、执行状态
7. 翻译替换原选区，显示“已完成”和“撤销”
8. 品牌与网址结束

演示假定已启用自动 Agent 写回。没有展示不存在的剪贴板看板、虚构任务卡片、记忆仪表盘或翻译答案大卡片。中性文本窗口是用于说明输入的场景，并非另一款产品的录屏。浮动 UI 是依据公开 SwiftUI 源码还原的交互动画，影片中有明确标注；它不是安装后实录。

macOS14+，用户需要自己的 Qwen API Key，模型调用按账号计费。

## 渲染与音乐

动画由帧数确定性驱动，Fn 点击音与实际按下帧一致。3D以0.8像素比软件WebGL抗锯齿渲染，字幕和胶囊以完整1080p输出。独立音轨便于在视频预览没有播放声音时直接核对。

来源和具体代码依据见 `SOURCE-BASIS.md`。参考视频音频未被复制或采样。

## 源码与复现

本目录为 15 秒工作流版本，与相邻 `../product-overview/` 的 24 秒产品宣传片独立运行。两个版本的 composition、配乐和依赖锁文件不混用。

音频是生成物，不提交 WAV、MP3 或最终 MP4。`npm run audio` 从共享 beatmap 和固定种子生成 `public/score-final.wav` 与分析 JSON；首次 studio、preview、render 发现缺少 WAV 时也会自动生成。编辑 beatmap 或音频代码后请重新运行 `npm run audio`。已安装音频依赖的 Python 环境须保持激活。

原始交付版音轨在 NumPy 2.3.5、SciPy 1.17.0、FFmpeg 7.1.5 下生成；不同 FFmpeg 版本可能产生轻微样本差异。图像、音乐与标识来源见 `SOURCE-BASIS.md`。原创代码及合成配乐沿用仓库 Apache-2.0 许可；鸟形路径的 Lucide ISC notice 见 [许可证](../../../Scripts/Resources/Licenses/Lucide.txt)。第三方依赖保留各自许可，Remotion 商业使用须单独核对其许可条件。
