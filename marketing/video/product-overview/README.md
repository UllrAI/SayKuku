# SayKuku 产品宣传片 · Product Overview

24 秒横版宣传片，中文、英文各一版，1920 × 1080、60 fps，由 Remotion 渲染。画面和原创配乐共用 `src/timeline.json` 一份时间轴，按键、落字、转场和品牌亮相都卡在 120 BPM 的拍点上。

## 使用

需要 Node.js 22+、Python 3.10+（NumPy、SciPy）和 FFmpeg。在本目录运行：

```bash
npm ci
python3 -m pip install -r scripts/requirements.txt
npm run audio       # 生成 public/score.wav，并校准到 -14 LUFS / 真峰值 ≤ -1 dBTP
npm run typecheck
npm run studio      # 预览，左侧切换 SayKuku-zh / SayKuku-en
```

导出：

```bash
npm run render      # 两个语言版本
npm run poster      # 两张海报（3.13 秒按下 Fn 的那一帧）
npm run storyboard  # 两张关键帧分镜图
```

成品在仓库根目录 `Dist/marketing/`，不进 Git：`SayKuku-Film-zh-1080p.mp4`、`SayKuku-Film-en-1080p.mp4`。编码为 H.264、yuv420p、Rec.709，AAC 立体声 48 kHz。

`remotion.config.ts` 在 macOS 用 ANGLE，在其他系统用 SwiftShader（`swangle`），没有 GPU 的 Linux 也能渲染 Three.js 画面。

## 分镜

| 时间 | 画面 | 声音 |
| --- | --- | --- |
| 0–3 s | 「想法很快。」砸入；「打字太慢。」逐字敲出；光标缩成一个点，坠向 Fn 键 | 暗色铺底、打字声、起音和军鼓滚奏 |
| 3–5.5 s | Fn 键微距，按下的那一帧就是 Drop：底部透出珊瑚色光，冲击环和震屏；「按一下 Fn，直接说。」和听写胶囊 | 冲击、底鼓律动进入 |
| 5.5–9 s | 说出的话以大字飘向镜头，录音结束后被吸进光标，整句落进邮件；胶囊依次为正在听、正在识别、已输入 | 每个词一个音，落字时一记重音 |
| 9–12 s | 聊天、笔记、提交说明三连切，每两拍落一次字；标题「说完，字就落在光标处。」 | 每次落字一个亮音和军鼓 |
| 12–14 s | 同一个 Fn 键连按两次，计数 1、2；「连按两次 Fn，说出你的要求。」；胶囊出现珊瑚色 sparkle | 停拍，两次按键各一记重击 |
| 14–17.5 s | 选中一句草稿，说「改得客气一点」；胶囊依次为正在理解、正在执行，原文逐字变形为改写结果，显示已完成和撤销 | 律动回归，铺垫到改写完成 |
| 17.5–19.5 s | 改写、翻译、起草、提问，每拍一个词，底色在珊瑚、墨色、纸色间切换 | 四下顿停重击，停在 A 大调属和弦 |
| 19.5–24 s | 中心的珊瑚点扩成纸色画面，鸟形标识一笔画出，字标升起，橙红圆点在拍点落下；口号、网址和使用条件 | 转 D 大调，钟音琶音，渐弱收尾 |

演示界面标注「界面为功能示意，非实际录屏」。不代表实际识别或模型响应速度。

## 真实性

- 浮层胶囊按 `OverlayPills.swift` 和 `Theme.swift` 的比例还原：36 pt 高、24 pt 按钮，听写为取消、波形、状态、确认；Agent 多一个珊瑚色 sparkle；结果为对勾、已输入或已完成，以及撤销。状态文案取自 `Localizable.xcstrings`。
- 录音时输入框里没有实时文字。飘起的大字表示说话的声音，录音结束、识别后才落进光标。
- 连按两次是同一枚键按两次，画面里没有并排的两个 Fn 键。
- Agent 无需选中文字；本片演示的是选中后改写这一种用法。「改写、翻译、起草、提问」与官网口径一致：选中文字可改写或翻译，不选也能起草、提问。
- 使用条件与 `marketing/strategy/positioning.md` 一致：macOS 14+，App 免费开源，自备 Qwen API Key。

## 源码

| 文件 | 作用 |
| --- | --- |
| `src/timeline.json` | 唯一时间轴，画面与 `scripts/score.py` 共用 |
| `src/copy.ts` | 中英文案；同时用来预载字形 |
| `src/Film.tsx` | 场景编排、震屏、颗粒与暗角 |
| `src/KeyStage.tsx` | Three.js 键盘微距：键帽、相机、按压和透光；每帧直接渲染 |
| `src/scenes/` | 开场与按键、听写与蒙太奇、Agent、动词与收尾 |
| `src/ui/` | 胶囊、窗口、品牌标识、特效组件 |
| `scripts/score.py` | 原创配乐合成与响度校准，固定随机种子 |
| `scripts/storyboard.mjs` | 关键帧渲染与分镜拼图 |

## 依赖与许可

原创代码与合成配乐沿用仓库 Apache-2.0 许可。鸟形路径复用仓库 Lucide Bird，ISC 许可全文见 [Lucide notice](../../../Scripts/Resources/Licenses/Lucide.txt)。

字体通过 npm 安装，渲染结果不依赖本机字体：Source Serif 4、Inter、Noto Serif SC、Noto Sans SC，均为 SIL Open Font License 1.1，不随仓库分发。

Remotion 有自己的商业许可，不作为 Apache-2.0 代码复制进项目。个人、最多 3 名员工的营利组织以及非营利组织适用免费许可，其他营利组织商用需要 Company License，参见 [Remotion 许可](https://www.remotion.dev/license)。React、Three.js 为 MIT 许可，TypeScript 为 Apache-2.0。
