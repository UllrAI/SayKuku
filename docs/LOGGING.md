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
Dictation trace: stop=manual result=completed total=1460ms mic=95ms connect=620ms route=realtime saveRecording=6ms upload=0ms firstText=480ms finalText=1350ms refine=410ms(changed) insert=95ms(verified)
```

| 字段 | 含义 |
| --- | --- |
| `stop` | 录音怎么结束：`manual` 手动、`autoStop` 实时识别判断说完、`limit` 到时长上限、`deviceChange` 音频设备变化 |
| `result` | `completed` 已写入或动作已执行、`copied` 改为复制卡片、`shown` Agent 回答或确认卡片、`failed`、`cancelled` |
| `total` | 停止录音到结果出现（写入完成、卡片出现或失败） |
| `mic` | 按下快捷键到麦克风开始录音 |
| `connect` | 麦克风开始到实时连接就绪；与说话时间重叠，停止时还没就绪则不记录 |
| `route` | `realtime` 实时识别、`batch` 只用整段识别、`fallback` 实时失败后改用整段识别 |
| `saveRecording` | 保存录音和 History；识别要等它完成 |
| `upload` | 停止后等待实时连接就绪并发完剩余音频 |
| `firstText` | 发出 commit 到第一段实时文字；文字在 commit 前已开始返回时不记录 |
| `finalText` | 发出 commit 到最终实时文字 |
| `batch` | 整段识别请求（含一次重试） |
| `refine` | 轻度整理的文本模型润色；括号里是 `changed`、`unchanged` 或保留初稿的原因（如 `timeout`） |
| `agent` | Voice Agent 请求 |
| `insert` | 写入目标 App，含写入后的校验等待，所以比文字实际出现略晚；括号里是 `verified` 或 `deliveredUnverified` |
| `action` | Voice Agent 的动作 |
| `error` | 失败时的错误类型 |

## 常用查询

开发包把 `com.saykuku.dev` 换成正式包的 `com.saykuku.app`。在 zsh 里用 `/usr/bin/log`，`log` 是 shell 内建命令。

```bash
# 最近一天每次录音的汇总
/usr/bin/log show --last 1d --style compact \
  --predicate 'subsystem == "com.saykuku.dev" AND eventMessage CONTAINS " trace: "'

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
