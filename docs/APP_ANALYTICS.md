# Mac App 使用统计

Umami 站点：[SayKuku macOS](https://track.pixmiller.com/websites/d8745d55-b5c9-4ace-a137-4a90376456bf)。与[官网统计](../marketing/site/ANALYTICS.md)分开。仅正式版发送，默认开启；用户可在「设置 → 隐私 → 使用统计」关闭。

| 事件 | 触发时机 | 读数 |
| --- | --- | --- |
| `app_first_launch` | 某个随机安装 ID 首次成功上报 | 安装实例数；旧版升级后首次上报也算首次观测 |
| `app_launch` | 每次 App 进程启动；同一进程重新开启统计不重复 | 启动次数 |
| `app_active` | 当天首次完成语音输入或 Voice Agent 操作；以 UTC 日期去重 | 当日实际使用的安装实例数 |
| `voice_input_completed` | 文本写入成功或交付复制兜底 | 语音输入次数；`characters` 为最终交付文本的 Swift `String.count` |
| `voice_agent_completed` | 答案、写入或外部操作完成 | Agent 使用次数；答案或写入文本的 `characters`，其他操作为 0 |

完成事件的 `data` 中只有 `app_version` 和数值 `characters`；其他事件只有 `app_version`。所有事件都带同一安装实例的随机 UUID 作为 Umami Distinct ID。事件无文字、音频、API Key、目标 App 或窗口信息。Umami 根据请求 IP 估计国家；地域图展示的是请求所在国家，VPN 或代理会影响结果。

## 查看指标

- 安装实例：所选期间 `app_first_launch` 事件数。它是首次成功上报数，不等于下载量、安装完成数或自然人数。
- 每日活跃：按日查看 `app_active` 事件数。菜单栏常驻或单纯启动不会计入。
- 使用次数：分别查看 `voice_input_completed` 与 `voice_agent_completed` 事件数。
- 字符数：对上述两种完成事件的数值属性 `characters` 分别求和。不要把 Umami 默认的事件属性「值分布」当成字符总数；可用支持数值求和的报告或对 Umami 数据库做只读聚合。
- 地域：在 Mac App 站点的国家维度查看。按 `app_first_launch` 过滤可看新增安装实例来源；按 `app_active` 过滤可看实际使用来源。

统计请求异步发送，失败不影响功能；离线、关闭统计、被网络或内容拦截器阻止的事件不会计入。重试边界上的首次启动或日活事件可能重复，读数用于产品趋势评估，不用于计费。
