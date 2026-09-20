# SayKuku. macOS Prototype

这是一个完全使用 SwiftUI / AppKit 构建的 macOS 原生交互原型。它将 PRD 中的核心产品模型收敛为两种明确不同的体验：

- `Fn`：轻量 Voice Input，经历 Ready → Listening → Processing → Success 后自动消失。
- `Fn Fn`：轻量 Voice Agent，只显示一个就地变形的意图确认 Pill，确认后自动安全写回。

## 运行

```bash
swift run SayKuku
```

也可以生成可直接打开的 `.app`：

```bash
Scripts/package-app.sh
open Build/SayKuku.app
```

## 原型覆盖

- Home：极简入口、Voice Input / Voice Agent 单浮层、动态波形、按需 Context 与自动写回成功态。
- History：查看原始语音、输入转写和最终输出；按 1 / 7 / 30 / 90 天或永久保留，星标不自动清理。
- Knowledge：分类、搜索、手动添加、文本粘贴、实体抽取、New / Merge / Conflict / Ignored 审核。
- Memory：Correction 建议、Short-term TTL、Long-term 确认数据。
- Settings：中英文界面（默认跟随系统）、Hold / Tap Fn、历史保留策略、Context & Privacy、Qwen & API。

SayKuku. 本身不提供编辑器；Voice Input 与 Voice Agent 的结果都写入其他 App 的当前输入框。网络、麦克风、系统级 Fn Event Tap 与 Accessibility 写入尚未接入；当前交付用于验证 UI、信息架构、动效节奏与主流程。
