# 产品资料与实现依据

查阅日期：2026-10-01。

## 官方来源

- 产品介绍：https://say.anikuku.com/
- 官方媒体页：https://say.anikuku.com/press/
- 真实开发版首页：https://say.anikuku.com/assets/app-home.png
- 听取、识别、完成状态胶囊：https://github.com/UllrAI/SayKuku/blob/main/Sources/SayKuku/UI/OverlayPills.swift
- 浮动窗口、定位及答案面板：https://github.com/UllrAI/SayKuku/blob/main/Sources/SayKuku/UI/FloatingOverlayController.swift
- 颜色、间距、36pt胶囊高度、24pt按钮：https://github.com/UllrAI/SayKuku/blob/main/Sources/SayKuku/DesignSystem/Theme.swift
- 五条波形的结构：https://github.com/UllrAI/SayKuku/blob/main/Sources/SayKuku/DesignSystem/DesignSystem.swift
- 听写提交、自动Agent写回、就地替换：https://github.com/UllrAI/SayKuku/blob/main/Sources/SayKuku/Voice/VoiceWorkflow.swift
- 中文字符串：https://github.com/UllrAI/SayKuku/blob/main/Sources/SayKuku/Resources/Localizable.xcstrings

官网媒体页明确区分开发版真实截图和营销说明图。本片首页来自真实截图；其余功能操作是依据上述源码制作的动画，没有冒充实录。

## 关键状态忠实性

- 录音中没有直播听写文本。录音提交以后才识别并写入
- Fn连按两次是同一枚物理键的两个按下/释放周期
- 第二次Fn使同一监听胶囊出现珊瑚色sparkle
- 翻译是写入动作。已启用自动写回时，在原选区替换文本，结束显示“已完成 · 撤销”
- 不把翻译误画成问答使用的440pt答案大面板
- 源码的中性色与珊瑚色用于UI，场景照明不改变实际产品布局

## 参考形式

https://x.com/okooo5km/status/2104884349841846515

完整文件确认15秒/60fps。视觉参考仅用于相机运动、实体按键、空间光照与节奏。音频的节奏统计支持约128BPM；本片音乐由本项目独立合成，没有使用参考视频的音频或画面。

品牌鸟形标记和末尾珊瑚点保留官方特征。依赖项遵循各自许可证；Remotion组织使用条件见 https://www.remotion.dev/license 。

## 交付资源清单

- `public/app-home.png`：与仓库 `marketing/assets/screenshots/quick-start.png` 相同的官方开发版首页。
- `public/v2/fn.png`、`public/v2/glow.png`：本项目制作的 Fn 键标签和径向光晕纹理，保留原相对路径以复现最终画面；`v2` 仅为历史资源目录名，不代表另一套 composition。
- `src/PromoReal.tsx`：最终演示动画及官方鸟形标记；仅保留最终 composition。
- `scripts/make_score_final.py`：固定随机种子 410128 的原创音轨合成器，无第三方采样；`src/beatmap-real.ts` 同时驱动视觉与音乐关键帧。

未包含参考视频文件、参考音轨、历史试做 composition、缓存或下载的第三方素材。系统字体不随源码分发，不同机器需安装相同字体以接近原始画面。
