# SayKuku 品牌宣传片

20 秒中文横版宣传片，1920 × 1080、60 fps，由 Remotion 渲染。文案与品牌参考 SayKuku 官网：深墨色开场、暖白界面、橙红色强调，最后回到暖白品牌画面。键帽使用 Three.js 实时几何与摄影棚光照；界面采用原生文字、统一圆角裁切和透视动画，避免低分辨率文字贴图与圆角露底。结尾使用与 App 同源的矢量鸟形、清晰字标和橙红圆点，不做立体化。

原创 120 BPM 电子配乐由脚本合成，无外部音乐或音效采样。底鼓、切分贝斯、十六分音符琶音与鼓组过门配合镜头节奏；3、8、10、15.5 秒的段落切换有重拍，3、8.5、9 秒的按键动作有短音效。

## 使用

需要 Node.js 22+。在本目录运行：

```bash
npm ci
npm run audio
npm run typecheck
npm run studio
```

导出视频与海报：

```bash
npm run render
npm run poster
```

成品位于仓库根目录 `Dist/marketing/`，不进入 Git。导出使用 H.264、Rec.709、yuv420p 和 AAC 立体声。`remotion.config.ts` 配置 ANGLE 渲染器与 PNG 帧，确保材质和细字清晰。音轨 `public/score.wav` 可重新生成，无需 Python、网络或付费 API。

## 分镜

| 时间 | 内容 |
| --- | --- |
| 00–03 | Fn 键帽特写；让想法，脱口而出 |
| 03–08 | 按一下 Fn，说话就能输入；文字落在当前光标处 |
| 08–10 | 连按两次 Fn，唤起语音助手；两次按键与节拍同步 |
| 10–15.5 | 双击 Fn，说出要求；说明不选文字也能提问、起草，画面展示选区翻译示例 |
| 15.5–20 | 平面品牌标识、Just Say It、下载网址与使用条件 |

界面为功能示意，画面标注“功能示意 · 非实际录屏”。示例不包含真实用户数据，不表示实际识别或模型响应速度。功能与费用说明以仓库 `README.md`、`marketing/strategy/positioning.md` 和官网为准。

## 依赖与许可

原创代码与合成配乐沿用仓库 Apache-2.0 许可。鸟形路径复用仓库 Lucide Bird；ISC 许可全文见 [Lucide notice](../../Scripts/Resources/Licenses/Lucide.txt)。字体使用本机 Avenir Next / Helvetica Neue / PingFang SC，不分发字体文件；其他系统渲染可能因字体不同而略有变化。

Remotion 有自身商业许可，不作为 Apache-2.0 代码复制进项目。个人、最多 3 名员工的营利组织及非营利组织可适用免费许可；其他营利组织的商业使用需要 Company License。参见 [Remotion 许可](https://www.remotion.dev/license)。React、Three.js 为 MIT；TypeScript 为 Apache-2.0。
