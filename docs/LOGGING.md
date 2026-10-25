# 日志与耗时排查

SayKuku 只写 macOS 统一日志（`Logger`，见 `Sources/SayKuku/Log.swift`），不另存日志文件。日志里只有状态、耗时、错误类型、Bundle ID、状态码、请求 ID 和计数，**不含**听写文字、录音、Prompt 或 API Key。

## 哪些日志事后还查得到

| 级别 | 保存位置 | 用途 |
| --- | --- | --- |
| `error` / `notice`（`Logger.log`） | 写入磁盘，通常保留数天，量大时更早被轮换 | 每次录音的汇总、请求结果、写入结果、失败与取消 |
| `info` | 只在内存里留很短时间 | 只适合现场 `log stream` 观察 |
| signpost（category `Performance`） | 内存为主 | 用 Instruments 看按 Fn 到浮层出现的区间，见 [COMPATIBILITY.md](COMPATIBILITY.md) |

事后排查需要的信息一律用 notice 及以上级别记录。

## 每次录音的汇总

每次 Voice Input / Voice Agent 结束（写入、出卡片、失败或取消）时，category `Workflow` 会写一行汇总，同样的耗时也保存在对应 History 条目的 `timing` 字段，History 页标题行会显示「停止录音后用时」，悬停可看各阶段。

```
Dictation trace: id=… version=… build=… stop=manual result=completed total=1780ms mic=95ms connect=620ms route=realtime saveRecording=6ms upload=0ms firstText=480ms finalText=850ms refine=410ms(changed) insert=500ms(verified)
```

| 字段 | 含义 |
| --- | --- |
| `id` / `version` / `build` | 本次流程 ID、App 版本和构建号；仅记录在日志中 |
| `stop` | 录音怎么结束：`manual` 手动、`autoStop` 实时识别判断说完、`limit` 到时长上限、`deviceChange` 音频设备变化 |
| `result` | `completed` 已写入或动作已执行、`copied` 改为复制卡片、`shown` Agent 回答或确认卡片、`failed`、`cancelled` |
| `total` | 停止录音到结果出现（写入完成、卡片出现或失败） |
| `mic` | 按下快捷键到麦克风开始录音 |
| `connect` | 麦克风开始到实时连接就绪；与说话时间重叠，停止时还没就绪则不记录 |
| `route` | `realtime` 实时识别、`batch` 只用整段识别、`fallback` 实时失败后改用整段识别 |
| `saveRecording` | 保存录音和 History；识别要等它完成 |
| `upload` | 停止后等待实时连接就绪并发完剩余音频 |
| `firstText` | 发出 commit 到第一个实时文本片段，可能只是结构化响应的前缀，不等于用户已看到文字；文字在 commit 前已开始返回时不记录 |
| `finalText` | 发出 commit 到最终实时文字 |
| `batch` | 整段识别请求（含一次重试） |
| `refine` | 轻度整理的文本模型润色；括号里是 `changed`、`unchanged` 或保留初稿的原因（如 `timeout`） |
| `agent` | Voice Agent 请求 |
| `insert` | 写入目标 App，含写入前检查、剪贴板备份、写入后的校验等待和剪贴板恢复，不能直接当作文字出现前的延迟；括号里是 `verified` 或 `deliveredUnverified` |
| `action` | Voice Agent 的动作 |
| `error` | 失败时的错误类型 |

## 「正在识别」与写入校验

听写浮层的「正在识别」会一直显示到写入流程返回。这段时间既包括模型识别，也包括目标检查、写入和写入后的确认。校验分为两类：写入前检查目标 App、窗口、输入框和光标是否仍与录音开始时一致，避免贴错位置；写入后通过辅助功能读取输入框，确认内容符合预期。`deliveredUnverified` 表示写入操作已发出但无法确认，不能据此认定写入失败。

category `Workflow` 的 `Dictation checkpoint` 用同一个流程 `id` 记录以下事件，`afterStop` 均为停止录音后的累计毫秒数：

| `event` | 含义 |
| --- | --- |
| `recognitionReady` | 首轮识别完成，包括可能的整段识别回退 |
| `textReady` | 可选二次整理结束，接下来进行本地格式处理和 History 更新 |
| `writeStarted` | 开始写入目标 App |
| `writeFinished` | 写入、校验及剪贴板处理已返回 |
| `successStateSet` | 已设置成功状态；不是屏幕实际完成绘制的时间 |

category `TextInteraction` 的 `Text write begin`、`Text write milestone` 和 `Text write trace` 记录单次写入。写入 `id` 独立于流程 `id`；结合相邻的 `writeStarted`、时间和目标 `bundle` 定位。

| 写入字段 | 含义 |
| --- | --- |
| `validateTarget` / `pasteValidate` / `pasteRevalidate` | 初始目标检查、粘贴路径检查、粘贴前再次检查 |
| `axWritable` / `axSet` | 检查辅助功能是否支持直接写入、执行直接写入 |
| `axVerify` / `pasteVerify` | 直接写入或粘贴后的校验总耗时，包含原有轮询等待 |
| `axVerifyReads` / `pasteVerifyReads` | 对应校验中读取目标的累计耗时，是上一项的子集，不能重复相加 |
| `axAttempts` / `pasteAttempts` | 实际校验次数 |
| `axLengthMismatches` / `pasteLengthMismatches` | 因长度不符而跳过全文读取的次数 |
| `axFallbackCheck` / `pasteFallbackCheck` | 校验未通过后的原有状态检查 |
| `clipboardBackup` / `clipboardPrepare` | 备份原剪贴板、准备本次粘贴内容 |
| `clipboardItems` / `clipboardBytes` | 已备份的剪贴板项目数量、数据总字节数，不记录内容，也不额外读取剪贴板 |
| `pasteDelay` / `postPaste` | 原有粘贴前等待、发送 ⌘V 的耗时 |
| `clipboardRestoreDelay` / `clipboardRestore` | 原有恢复前等待、恢复剪贴板的耗时 |
| `axAcceptedAt` / `pastePostedAt` | 从开始写入到直接写入调用成功或 ⌘V 发出的累计时间，不代表文字已显示 |
| `axVerifiedAt` / `pasteVerifiedAt` | 从开始写入到首次读到预期全文的累计时间，只能作为文字已写入的观测时间 |
| `result` / `total` | 写入结果与总耗时；异常或取消退出记为 `interrupted`，结合流程错误或取消日志判断 |

只记录实际经过的阶段，缺失字段不表示零耗时。所有详细打点均为 `notice`，不记录听写文字、输入框值、剪贴板内容或 Prompt。新增打点需在安装包含这些改动的构建后才会产生；旧版本的历史日志无法补出这些细节。此次仅增加观测，不调整识别、写入路径、轮询次数或等待时长。

## 常用查询

开发包把 `com.saykuku.dev` 换成正式包的 `com.saykuku.app`。在 zsh 里用 `/usr/bin/log`，`log` 是 shell 内建命令。

```bash
# 最近一天每次录音的汇总
/usr/bin/log show --last 1d --style compact \
  --predicate 'subsystem == "com.saykuku.dev" AND eventMessage CONTAINS " trace: "'

# 最近一小时识别完成、写入开始、粘贴发出和校验完成的时间点
/usr/bin/log show --last 1h --style compact \
  --predicate 'subsystem == "com.saykuku.dev" AND (eventMessage CONTAINS " checkpoint: " OR eventMessage BEGINSWITH "Text write ")'

# 最近一天所有警告与错误
/usr/bin/log show --last 1d --style compact \
  --predicate 'subsystem == "com.saykuku.dev" AND messageType == error'

# 某次慢请求前后的完整经过（把时间换成汇总那一行的时间）
/usr/bin/log show --start "2026-10-22 10:24:00" --end "2026-10-22 10:25:00" --style compact \
  --predicate 'subsystem == "com.saykuku.dev"'

# 现场观察，包括 info
/usr/bin/log stream --level info --style compact --predicate 'subsystem == "com.saykuku.dev"'
```

`Qwen` category 里每次 HTTP 请求都有一行 `Chat request model=… HTTP … in … ms … request id …`，实时会话的日志带服务端 session ID；向阿里云反馈慢请求或错误时附上这两个 ID。
