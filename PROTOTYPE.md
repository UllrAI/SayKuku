# SayKuku. macOS App

这是一个使用 SwiftUI / AppKit 构建的 macOS 原生语音输入应用。它将核心体验收敛为：

- `Fn`：轻量 Voice Input，进入 Listening 后实时回显转写，完成写入后自动消失；目标不可写时自动复制并保留操作 Pill。
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

## 功能

- Home：极简入口、Voice Input / Voice Agent 单浮层、动态波形、按需 Context 与自动写回成功态。
- History：查看原始语音、输入转写和最终输出；按 1 / 7 / 30 / 90 天或永久保留，星标不自动清理。
- Knowledge：分类、搜索、手动添加、文本粘贴、实体抽取、New / Merge / Conflict / Ignored 审核。
- Memory：Correction 建议、Short-term TTL、Long-term 确认数据。
- Settings：中英文界面（默认跟随系统）、Hold / Tap Fn、历史保留策略、Context & Privacy、Qwen & API。

SayKuku. 本身不提供编辑器；Voice Input 与 Voice Agent 的结果都通过 Accessibility 校验后写入其他 App 的当前输入框。应用使用 Qwen Realtime 做流式听写，Qwen Omni 做 Agent 与 Knowledge 处理；API Key 保存在 Keychain，History、Memory、Knowledge 和原始语音均加密保存在本机。首次使用需在设置中填写对应地域的 Qwen API Key，并授予麦克风与辅助功能权限。
