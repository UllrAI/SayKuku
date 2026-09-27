# SayKuku 媒体资料与口径

官网媒体页：<https://say.anikuku.com/press/>。官方横向字标在 `../assets/brand/`；必须保留 `SayKuku.` 末尾的橙红点。

## 一句话

SayKuku 是 Mac 上的语音工具：按 Fn 说话输入，连按两次 Fn 唤起 Voice Agent，继续改写、提问或翻译。

## 短介绍

想到一句话时，光标已经在输入框里。SayKuku 让你按 Fn 说完，文字就尝试写回当前光标；连按两次 Fn，Voice Agent 可以按你的语音要求改写选区、翻译、回答问题或继续对话。原生 macOS 15+，目前使用 Qwen 云端模型，需要自己的 API Key。

## English

SayKuku is a native Mac voice app. Press Fn to dictate at the cursor. Double press Fn for Voice Agent to rewrite selected text, translate, ask questions, or keep going. The current build uses Qwen cloud processing and your own API key.

## 准确事实

| 项目 | 内容 |
| --- | --- |
| 系统 | macOS 15+ |
| Fn | Voice Input，可在设置中选择按住或单击 |
| Fn Fn | Voice Agent，改写、翻译、提问、继续对话 |
| 记忆 | 手动添加、从粘贴文字中挑选、确认纠正后保存人名/项目/术语；可编辑删除 |
| 模型 | 当前仅 Qwen，用户自备 API Key；后续供应商扩展不能写成现有功能 |
| 数据 | 音频与允许的上下文走所选 Qwen 地域；历史/记忆/可选录音为本机未额外加密文件；Key 在钥匙串 |
| 官网 | https://say.anikuku.com/ |
| 安装包 | 1.0.1，官网版本区下载，R2 公开域名分发 |

## 媒体或社区短介绍

我在做 SayKuku，起点是 Mac 上写消息时的一段小停顿：一句话已经想好，手还在敲第一个词。按 Fn 可以把话直接写到当前输入框；Fn Fn 是 Voice Agent，可继续改写、翻译或提问。官网有预设交互演示和完整隐私说明：say.anikuku.com。1.0.1 可以从官网版本区下载；如果你愿意聊使用场景，我最想知道你常在哪个 App 里输入，以及哪里最容易写回失败。

## 真实演示分镜（正式安装包发布时录制）

1. 光标在无个人信息的示例输入框，按 Fn，说一句，展示实际转写与写回。
2. 选中刚写的句子，连按两次 Fn，说「短一点」，展示实际 Voice Agent 结果。
3. 对 Agent 继续说一句追问，说明 Fn Fn 并非只有改写。
4. 最后露出 macOS 15+ 和权限说明入口，标注当前模型服务需要自己的 API Key。

不剪掉真实等待时间，也不使用真实聊天、联系人或 API Key 画面。
