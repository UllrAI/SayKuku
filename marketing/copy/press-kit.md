# SayKuku 媒体资料与口径

官网媒体页：<https://say.anikuku.com/press/>。官方横向字标在 `../assets/brand/`；必须保留 `SayKuku.` 末尾的橙红点。

## 一句话

SayKuku 是免费的原生 Mac 语音工具：按 Fn 在光标处输入，连按两次 Fn 改写、翻译或提问；1.0.2 安装包 4.8 MB，使用时自备 Qwen API Key。

## 短介绍

Typeless 降低额度后，作者试了几款替代品，觉得都不顺手，于是 Vibe Coding 了 SayKuku。它让用户留在当前输入框，按 Fn 把话写到光标处；连按两次 Fn，则可用 Voice Agent 改写选区、翻译、提问或继续对话。SayKuku 是 macOS 15+ 原生应用，App 免费，通用安装包 4.8 MB；当前使用 Qwen3.8 Omni Flash 系列处理音频，用户需自行配置 API Key 并承担模型费用。源代码采用 Apache-2.0 许可，待仓库公开后开放下载。

## English

SayKuku is a free, native macOS voice app born after its maker tried alternatives when Typeless reduced its allowance. Press Fn to dictate at the cursor; double press Fn to rewrite selected text, translate, ask questions, or follow up. The macOS 15+ installer is 4.8 MB. Bring your own Qwen API key for cloud model use. The maker plans to open source the code after cleanup; it is not open source yet.

## 准确事实

| 项目 | 内容 |
| --- | --- |
| 系统与安装包 | macOS 15+，Apple 芯片与 Intel 通用；1.0.2 DMG 为 4,847,011 字节，约 4.8 MB |
| Fn | Voice Input，可在设置中选择按住或单击 |
| Fn Fn | Voice Agent，改写、翻译、提问、继续对话 |
| 记忆 | 手动添加、从粘贴文字中挑选、确认纠正后保存人名/项目/术语；可编辑删除 |
| 模型 | 默认使用 Qwen3.8 Omni Flash Realtime 听写及 Qwen3.8 Omni Flash 处理 Agent/批处理；直接处理音频，不是固定的纯 ASR 两段调用 |
| 费用 | App 免费；用户自备阿里云百炼 API Key，模型费用由自己的账号承担。当前北京地域默认实时模型音频输入 1 小时约 0.15 元，输出文字等另计 |
| 数据 | 音频与允许的上下文走所选 Qwen 地域；历史/记忆/可选录音为本机未额外加密文件；Key 在钥匙串 |
| 开源 | 源代码采用 Apache-2.0 许可；仓库公开后开放下载 |
| 官网 | https://say.anikuku.com/ |
| 安装包 | 1.0.2，官网版本区下载，R2 公开域名分发 |

费用估算：阿里云文档给出该模型音频输入每秒 7 Token、北京地域每百万输入音频 Token 6 元；3600 × 7 × 6 / 1,000,000 = 0.1512 元。输出文字、Agent 调用、其他地域、模型与可能的免费额度会改变实际账单。发布时以[模型说明](https://help.aliyun.com/zh/model-studio/qwen3-8-omni-flash-realtime)和[实时调用计费规则](https://help.aliyun.com/zh/model-studio/realtime)为准。

## 媒体或社区短介绍

我之前用 Typeless，额度降低后试了几款替代品，都不太顺手，就 Vibe Coding 了 SayKuku。按 Fn 可以把话写到当前光标；Fn Fn 能继续改写、翻译或提问。原生 Mac App，1.0.2 安装包 4.8 MB，App 免费；使用时自己配 Qwen API Key。代码整理后计划开源。下载和隐私说明在 say.anikuku.com。

## 真实演示分镜（正式安装包发布时录制）

1. 光标在无个人信息的示例输入框，按 Fn，说一句，展示实际转写与写回。
2. 选中刚写的句子，连按两次 Fn，说「短一点」，展示实际 Voice Agent 结果。
3. 对 Agent 继续说一句追问，说明 Fn Fn 并非只有改写。
4. 最后露出 macOS 15+、免费 App、自备 Qwen API Key 和权限说明入口。

不剪掉真实等待时间，也不使用真实聊天、联系人或 API Key 画面。
