# SayKuku

> Just Say It...

软件名称与所有纯文本固定写作 `SayKuku`。句点只作为 Logo 组合中的视觉细节，不进入窗口标题、菜单、按钮、权限文案或无障碍文本。

Logo 组合可使用鸟形图标与带视觉句点的字标。图标固定使用 Lucide Bird 的线性造型，只调整品牌色、描边粗细、缩放和安全边距，不改变鸟形结构：

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  <path d="M16 7h.01"/>
  <path d="M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/>
  <path d="m20 7 2 .5-2 .5"/>
  <path d="M10 18v3"/>
  <path d="M14 17.75V21"/>
  <path d="M7 18a6 6 0 0 0 3.84-10.61"/>
</svg>
```

默认横向锁定关系：

```text
[Bird Icon] SayKuku.
```

App 图标不放文字，使用珊瑚红圆角底板与暖白 Lucide Bird 线稿；图形保持足够安全边距。菜单栏使用同一鸟形的缩小单色 template 版本，由 macOS 自动生成浅色、深色和按下态，不维护容易失配的手工黑白双份资源。打包资源位于 `Scripts/Resources/AppIcon.icns`。

---

# 0. 当前实现进度与界面基线

> 最后更新：2026-09-20。`✅ 已完成` 表示已经进入当前可运行 App；`🟡 交互原型完成` 表示界面和状态流已实现，但真实音频、模型、系统写回或持久化仍待接入；`⬜ 待实现` 表示尚未开始生产实现；`⏸ 后续版本` 表示不进入 MVP。

| 模块 | 状态 | 当前已经完成 | 下一步 |
| --- | --- | --- | --- |
| 原生 App 外壳与统一设计系统 | ✅ 已完成 | SwiftUI 原生窗口、固定侧栏、统一页面宽度、标题、Tab、卡片、间距、圆角与阴影 | 持续做逐页视觉回归 |
| App 图标与打包 | ✅ 已完成 | Lucide Bird 品牌母形、珊瑚底色与暖白线稿、1024 px 预览、ICNS、Bundle 图标、应用分类与签名脚本 | 正式发布时确定 Bundle ID，并替换为 Developer ID 签名与公证 |
| 菜单栏常驻入口 | ✅ 已完成 | 8.5 pt Lucide Bird 放置在 16 × 18 pt 状态项画布，使用原生 template 渲染自动适配明暗与按下态；包含 Voice Input、Voice Agent、显示主窗口、设置、状态与退出菜单 | 后续增加连接延迟与录音态图标 |
| 全局快捷键 | ✅ 已完成 | `⇧⌘D` Voice Input、`⇧⌘A` Voice Agent，通过 Carbon 注册且不需要任何隐私权限 | 增加可配置按键 |
| Fn Gesture Router | ✅ 已完成 | Hold Fn、Tap Fn、Double Fn、活动语音流程下 Esc 取消、组合键取消、超时恢复、冲突检测、系统 Fn 行为引导与全局快捷键 fallback；复用写回所需的辅助功能权限，不申请输入监控 | 增加真实设备与外接键盘回归测试 |
| 权限引导与麦克风测试 | ✅ 已完成 | 启动时缺失权限自动展示引导；麦克风与辅助功能实时状态、快捷开启、回到 App 自动复查；设置页可重新打开；AVAudioEngine 实时输入电平测试 | 增加多输入设备切换回归测试 |
| 首页与两种浮层 | ✅ 已完成 | Voice Input / Voice Agent 的真实录音、识别、自动执行与结果状态，以及跨桌面非激活浮层 | — |
| History | ✅ 已完成 | 本地加密历史、原始语音回放、筛选、星标和按期限清理 | — |
| Knowledge | ✅ 已完成 | 手动添加、模型抽取、PII 预过滤、分段、归一化、去重、实体/关系 Review 与加密存储 | — |
| Memory | ✅ 已完成 | Agent Session TTL、当天听写、纠错建议、用户确认后进入长期 Knowledge | — |
| Settings 与中英文 | ✅ 已完成 | 统一水平 Tab、语言、输入模式、隐私开关、菜单栏、登录项、快捷键状态和持久化 | — |
| Qwen Realtime / Omni | ✅ 已完成 | Realtime WebSocket、Omni 请求式 API、批处理音频 fallback、错误与超时 | — |
| 麦克风与系统写回 | ✅ 已完成 | 16kHz PCM 录音、可选 Semantic VAD、目标快照、写回前校验和 Accessibility 写回 | — |
| 本地隐私存储 | ✅ 已完成 | Keychain、AES-GCM 加密 History / Memory / Knowledge / Audio 与保留清理 | — |
| 截图 OCR 导入 | ⏸ 后续版本 | 仅保留产品设计 | MVP 后再评估 |

## 0.1 桌面端视觉与布局标准

当前所有一级页面使用同一套布局，不允许各页面自行定义内容宽度或第二套 Tab：

```text
默认窗口             1000 × 660 pt
最小窗口              860 × 580 pt
侧栏宽度              176 pt
右侧内容最大宽度      760 pt
页面水平边距           28 pt
控件圆角               8 pt
卡片圆角              12 pt
主卡片 / 浮层圆角      16 pt
```

右侧内容始终从同一条左侧基线开始；超宽窗口只在右侧留下弹性空间，不把内容居中漂移。所有二级导航统一使用顶部水平 `KukuPageTabs`：

```text
History    All / Voice Input / Voice Agent
Knowledge  All / People / Organizations / Projects / Terms
Memory     Corrections / Short-term / Long-term
Settings   General / Voice Input / Voice Agent / History / Context & Privacy / Qwen & API
```

Knowledge 与 Memory 是一级侧栏页面，不再重复出现在 Settings 内。设置卡片中的每一行必须撑满卡片宽度并左对齐；只有明确的右侧值、Picker 或 Toggle 才使用尾部对齐。

## 0.2 权限引导与输入测试标准

当麦克风或辅助功能任一权限缺失时，App 每次启动只展示一次应用内权限引导，不在页面出现前连续弹出多个系统对话框。用户明确点击后才触发对应系统授权：

```text
麦克风       Voice Input、Voice Agent 与输入电平测试
辅助功能     Fn 手势与向当前输入框写回文字
输入监控     不申请、不声明、不创建 CGEvent tap
```

权限引导与 Settings 使用同一个实时状态源。App 重新获得焦点时必须复查状态；设置页提供权限状态、快捷开启入口和重新打开完整引导的按钮。

辅助功能请求不得用轮询锁住按钮。发起系统提示后立即结束按钮忙碌态；回到 App 时只以 `AXIsProcessTrusted()` 的实际结果复查，不猜测“需要重开”。开发包优先使用本机 Apple Development 证书形成稳定、带 Team ID 的 designated requirement；没有证书时才回退 ad-hoc 签名并明确警告其 TCC 授权可能随重建失效。发布包使用 Developer ID 签名。

麦克风测试使用系统默认输入设备，只计算实时 RMS 输入电平和峰值。测试声音不保存、不上传、不回放；页面或引导关闭时立即停止音频引擎。

---

# 1. 产品核心

产品只有两个最高频入口：

```text
Fn
↓
Voice Input
我的声音就是键盘
```

```text
Fn Fn
↓
Voice Agent
我的声音是在告诉电脑做什么
```

用户不需要记忆“翻译快捷键”“改写快捷键”“总结快捷键”。

所有能力都收敛到这两个动作。

## 1.1 MVP 验证目标

MVP 不是只做一个语音输入 Demo，也不做成完整的电脑 Agent。

它需要同时验证三件事：

```text
Fn
→ 用户是否愿意把它当成日常输入方式

Fn Fn
→ 用户是否愿意把它当成当前上下文的 AI 入口

Knowledge
→ 人名、项目名、组织名和专业词是否真的能越用越准
```

因此 MVP 保留：

* Hold Fn / Tap Fn 二选一的 Voice Input，以及 Double Fn Voice Agent
* 当前选中文字、当前应用、窗口标题等轻量 Context
* Translate / Rewrite / Generate，并根据当前是否有选区自动写回原输入框
* 文本粘贴导入 Knowledge
* 实体抽取、归一化、去重、关系识别、用户确认
* 最近 Agent Session、词库和用户确认后的纠错记忆
* 本地 History：语音、输入转写和最终输出可回看，默认保留 30 天，星标记录永久保留

MVP 暂不提供：

* PDF、DOCX、XLSX 等文件解析
* 截图 OCR 导入
* Meeting、录音 Library、Speaker Diarization
* Calendar、Email、Files、Terminal 等高风险工具
* 多供应商和本地模型选择器

Knowledge 不是被砍掉，而是先把输入渠道收窄到“粘贴文本”，保留后续最有价值的数据模型和处理流程。

---

# 2. Fn 交互设计

> 实现状态：`✅ 已完成`。当前 App 已包含统一 Fn Gesture Router。普通组合键通过 Carbon 注册，不需要隐私权限；Fn 是纯修饰键，无法作为普通 HotKey 注册，因此在 Accessibility 已授权后使用 AppKit `NSEvent` 全局/本地 monitor。实现不创建 CGEvent tap，不调用 Input Monitoring API，也不声明相关权限。`NSEvent` 全局 monitor 只能观察事件，不能阻止系统同时执行 Fn / Globe 动作；设置页提供入口，引导将 macOS“按 Fn 键时”设为“无操作”。`⇧⌘D` 与 `⇧⌘A` 始终作为无权限 fallback。

## 2.1 用户可选择两种输入习惯

设置：

**语音输入方式**

○ 按住 Fn 说话，松开完成
○ 单击 Fn 开始，再次单击结束

**Voice Agent**

双击 Fn

这两个选项不能简单监听三个独立事件，需要统一做一个 `Fn Gesture Router`。

---

## 2.2 模式 A：Hold Fn 输入

### 普通输入

```text
按住 Fn
  ↓
出现极轻量 Listening UI
  ↓
说话
  ↓
松开 Fn
  ↓
Processing
  ↓
文字直接进入当前光标
```

为了兼容“双击 Fn”，建议：

```text
Fn Down
  ↓
先进入约 150ms 的 Pending
  ↓
持续按住
  ↓
确认 Hold
  ↓
Dictation
```

但音频可以从 Fn Down 就进入一个短暂的 pre-buffer，所以用户开口很快也不会漏掉第一个字。

如果用户只是快速敲了一下 Fn：

```text
Fn ↓ ↑
```

则不启动 Dictation。

如果紧接着第二次：

```text
Fn ↓ ↑  Fn ↓ ↑
```

则：

```text
Voice Agent
```

---

## 2.3 模式 B：单击 Fn 输入

这里必须处理单击/双击冲突。

```text
第一次 Fn
    ↓
Tap Pending ≈ 220–280ms
    │
    ├─ 没有第二次 Fn
    │       ↓
    │   Voice Input
    │
    └─ 出现第二次 Fn
            ↓
        Voice Agent
```

用户体验上不应该显示“等待双击”。

确定进入 Voice Input 后直接显示 Listening，并在 Pill 内实时回显已识别内容，不暴露短暂的内部准备状态。

输入结束可以：

```text
再次 Fn
```

或者允许用户配置：

```text
自动检测停顿结束
```

建议默认还是再次 Fn，VAD 自动停止作为可选项。

## 2.4 Fn Gesture Router 必须处理的边界

Router 不能只根据按下次数触发回调，而应维护明确状态：

```text
Idle
├── FirstTapPending
├── Prebuffering
├── Dictating
├── AgentListening
├── Processing
└── Previewing
```

必须满足：

* 用户按下 `Fn + ←/→`、`Fn + F1…F12` 或其他组合键时，立即取消语音手势并丢弃 pre-buffer。
* 快速单击未形成双击时，才按所选模式开始 Dictation。
* Hold 模式中第二次 Fn 进入 Agent 后，不得同时触发 Dictation。
* Tap Dictation 已在录音时，单击 Fn 优先结束当前录音，不再进入双击判断。
* Processing 期间再次触发时，默认取消上一次未提交任务，再开始新任务。
* Accessibility 被撤销、全局 monitor 失效、睡眠唤醒后，应恢复监听或给出明确错误。
* 外接键盘不产生 Fn 事件时，必须提供普通全局快捷键作为 fallback。

音频可以从 Fn Down 开始进入内存 pre-buffer，但只有手势确认后才允许发送网络。被识别为单击、双击或系统组合键之外的音频立即丢弃，不落盘。

---

# 3. 两套 UI 必须明显不同

> 实现状态：`✅ 已完成`。已接入真实录音、Qwen 转写、知识纠正和系统输入框写回。

## Voice Input

它不是一个“窗口”。

只需要极轻量状态反馈：

```text
● Listening…
```

说话时：

```text
◉ ～～～～～
```

松开后：

```text
◌ Processing…
```

成功后：

```text
✓
```

随后消失。

位置可以提供：

* 光标附近 Bubble
* 屏幕底部 Pill
* 刘海 / 顶部
* 固定浮窗

但默认建议使用 **光标附近 Bubble / 底部 Pill**。

用户应该感觉：

> 我只是换了一种打字方式。

而不是：

> 我打开了一个 AI App。

---

# 4. Voice Agent UI

> 实现状态：`✅ 已完成`。状态 Pill、按需 Context、Qwen 调用、目标校验与自动写回均已接入。

Double Fn 后，UI 仍然只是一层极轻的输入法式浮层，不打开自己的编辑器，也不承载结果管理。

例如用户选中了：

> 我们计划下周完成这一版，然后进行内部测试。

双击 Fn 后直接出现一个紧凑 Pill；波形与实时识别意图都在同一个容器内，不再增加第二行转写或独立面板。

用户：

> 翻译成英文，口语一点。

识别到意图后不再等待确认，同一个 Pill 直接进入执行状态：

```text
正在写入…
        ↓
✓ 已写入
```

随后浮层自动消失。结果直接进入用户正在使用的其他 App 输入框；SayKuku 不提供自己的编辑器，也不显示 Replace / Insert / Copy 等结果按钮。

### 确定性修改

例如：

> 翻译成英文
> 改短一点
> 修一下错别字

有选中文字时，识别意图后直接执行：

```text
Understand → Validate Target → Replace Selection
```

### 生成型操作

例如：

> 帮我回复他说周四上午可以。

没有选中文字时，识别意图后直接执行：

```text
Understand → Validate Target → Insert At Cursor
```

需要解释、总结等 Understand 能力时，MVP 也把结果写入当前光标，不建设独立阅读或对话界面。若用户只想阅读答案而不写入，应放到后续版本单独设计，而不是在 MVP 中加入一个半成品聊天面板。

### Action

例如：

> 打开 GitHub。
> 搜一下这家公司。
> 调用这个 Shortcut。
> 把这句话发到……

进入 Tool Calling。

## 4.1 自动写回安全规则

Agent 启动时必须创建 `TextTargetSnapshot`：

```text
TextTargetSnapshot
├── App PID / Bundle ID
├── Window ID / Title
├── Focused Element
├── Selected Range
├── Selected Text Hash
└── Captured At
```

模型返回以后、写回以前重新校验目标：

* 有选区，且应用、窗口、选区和原文均未变化：允许 Replace Selection。
* 无选区，且原 Focused Element 与光标仍有效：允许 Insert At Cursor。
* 目标已经变化或无法可靠校验：禁止写入目标，自动把最终文本复制到剪贴板；Pill 保持显示文本，并提供“复制”和“关闭”，不向用户暴露底层目标校验错误。

Agent 识别出意图后直接执行。文本操作必须先校验原输入目标，目标变化时不得写入，只能自动复制并展示兜底 Pill；打开 URL、搜索和 Shortcut 等动作直接执行。

---

# 5. Agent 的 Context

这是整个产品里比 ASR 更重要的一层。

每次 Agent 调用生成一个：

```text
VoiceContext
```

建议按优先级收集：

```text
Selected Text
      ↓
Focused Input / Current Paragraph
      ↓
Active App
      ↓
Window Title
      ↓
Current Document / URL
      ↓
Current Agent Session
      ↓
Recent Voice History
      ↓
Relevant Long-term Memory
```

Context 默认不常驻显示。聆听 Pill 只保留一个低强调的 scope 图标，点击后才打开轻量 Popover：

```text
本次使用的上下文
Safari                         ×
Selected text · 436 字          ×
Project · AniKuku               ×
```

用户需要时可以明确知道：

**AI 到底看到了什么。**

也允许点 `×` 去掉某个上下文。

这是隐私感和可控性非常重要的一步。

---

# 6. Voice Agent 第一版能力

第一阶段不需要做成万能电脑 Agent。

围绕文字与当前上下文做强。

### Transform

```text
翻译
改写
缩短
扩写
纠错
润色
改变语气
改变格式
Markdown 化
整理成列表
```

### Generate

```text
回复这段话
接着写
帮我写一句……
根据这个写……
```

### Understand

```text
解释一下
总结
这是什么意思
找出重点
有什么问题
```

MVP 中 Understand 的输出仍写入当前光标，不在 SayKuku 内部打开答案阅读器。

### Context Action

```text
打开 URL
搜索
运行 Shortcut
```

然后再逐步增加：

```text
MCP
Calendar
Email
Browser
Files
Terminal / Dev tools
```

不要第一版就做 Computer Use。

---

# 7. Agent 对话

Voice Agent 的界面是一次性 Command，但 Session 可以在后台连续。

第一次：

```text
Fn Fn

“帮我总结一下这篇文章。”
```

结果写入当前输入框，浮层立即消失，但后台保留一个带 TTL 的轻量 Session。

再次双击 Fn：

> 第二点详细讲一下。

继续当前 Context。

再说：

> 那这个和 MQTT 有什么关系？

继续。

可以形成：

```text
AgentSession
├── Context Snapshot
├── User Voice
├── Tool Calls
├── Assistant Response
└── Follow-ups
```

当用户：

* 切换到明显不同的任务
* 主动 Close
* 超过一定空闲时间

再结束 Session。

因此它实际上是：

> **悬浮在所有 Mac App 之上的意图输入层。**

而不是打开一个 ChatGPT 窗口或 SayKuku 自己的编辑器。

---

# 8. 热词 / 人名 / 组织知识

> 实现状态：`✅ 已完成`。列表、分类、搜索、手动添加、模型抽取、归一化、去重、关系 Review 与本地加密存储均已接入。

设置中单独做：

## Knowledge

不要简单叫 Dictionary。

因为后面装进去的不只是单词。

可以包含：

```text
People
Organizations
Projects
Products
Terminology
Custom Words
```

---

## 人名

例如：

```text
张越
Aliases:
- 张老师
- Visoar

Organization:
- UllrAI Lab

Role:
- Founder

Related:
- AniKuku
- BifroMQ
```

还可以保存：

```text
拼音
常见错误识别
英文名
简称
```

例如系统曾经识别：

```text
张月
```

用户改成：

```text
张越
```

系统可以建议：

> 是否将「张越」加入人名？

而不是偷偷写入。

---

# 9. 组织架构

可以直接创建：

```text
公司
├── 产品部
│   ├── 张越
│   └── 王涛
│
├── 技术部
│   ├── 李明
│   └── 陈晨
│
└── 项目
    ├── WorkBuddy
    └── AniKuku
```

它的价值不只是给 ASR 一个词典。

例如用户说：

> 把这个发给产品部的王涛。

Agent 可以理解：

```text
王涛
→ 人
→ 产品部
→ 当前组织
```

因此这里最好从一开始就是轻量 Entity Store，而不是：

```text
[String]
```

---

# 10. Knowledge 导入

MVP 只提供两种入口：

```text
＋ 手动添加
＋ 粘贴文本
```

### 手动

直接输入：

```text
张越
AniKuku
Apache BifroMQ
WorkBuddy
……
```

系统自动判断：

```text
Person
Organization
Product
Term
Unknown
```

用户确认即可。

---

## 粘贴文本导入

用户可以粘贴通讯录、项目名单、术语表或任意半结构化文本。例如：

```text
姓名：王涛
部门：产品部
职位：产品经理
手机号：186……

项目 AniKuku，负责人张越，也叫 Visoar。
```

不要直接把整段文本保存进 Knowledge Store。

流程应该是：

```text
粘贴文本
 ↓
分段 / 解析
 ↓
实体抽取
 ↓
归一化
 ↓
去重
 ↓
关系识别
 ↓
预览
 ↓
用户确认
 ↓
Knowledge Store
```

例如：

```text
姓名：王涛
部门：产品部
职位：产品经理
手机号：186……
```

我们真正需要的可能只是：

```text
王涛
Person

产品部
Organization Unit

王涛 → belongsTo → 产品部
```

**电话号码之类与识别无关的数据默认不要保存。**

模型只负责提议候选实体、别名和关系；本地代码负责确定性的归一化、索引和去重：

```text
Entity
├── id
├── type: Person | Organization | OrgUnit | Project | Product | Term | Unknown
├── canonicalName
├── normalizedKey
├── aliases[]
└── source

Relationship
├── fromEntityID
├── type: belongsTo | worksOn | owns | relatedTo
└── toEntityID
```

去重规则：

1. `normalizedKey` 完全相同或已有 Alias 命中：可建议合并。
2. 仅大小写、空格、常见分隔符不同：归一化后再比较，但保留用户确认的展示写法。
3. 只是名字相似、拼音相似或模型判断为同一实体：必须由用户确认，不自动合并。
4. 原文中的手机号、邮箱、地址等非 Voice 必需 PII 默认过滤。
5. 导入前必须展示 `New / Merge / Conflict / Ignored` 四类结果和对应原文证据。

Knowledge 抽取时，用户粘贴的文本一律视为不可信数据，其中的“忽略之前指令”、“删除记忆”等内容不得被当成系统指令执行。该请求只允许调用一个无副作用的 `propose_knowledge_import` tool，返回候选 JSON，不向 Agent ToolRegistry 开放任何外部工具。

每个候选实体或关系必须携带原文 evidence；无 evidence 的推断默认不入库。

这是“抽离”最有价值的部分：

> 从原始资料里抽取对 Voice 有价值的知识，而不是保存整份资料。

---

# 11. 截图录入

> 实现状态：`⏸ 后续版本`。不进入 MVP，当前 App 未实现入口。

这是非常适合 Mac 的功能，但不进入 MVP。

后续实现时，截图 OCR 和 PDF / DOCX / XLSX 解析都应转换为统一的 `ImportedText`，然后复用第 10 节的实体抽取、归一化、去重和 Review 流程，不另建一套 Knowledge pipeline。

后续用户可以直接：

```text
拖一张企业通讯录截图
```

系统 OCR 后：

```text
发现：

12 个人名
4 个部门
3 个项目名称
21 个可能的专业词汇
```

出现 Review：

```text
✓ 张越       Person
✓ 王涛       Person
✓ 产品中心   Department
✓ AniKuku    Product
□ 山东省……   Organization
```

用户确认：

```text
Import 18 items
```

而不是一句：

> 已加入知识库。

---

# 12. 短期记忆

> 实现状态：`✅ 已完成`。Memory 页面使用真实 Agent Session、当天听写、TTL、纠错学习与持久化数据。

Short-term Memory 的目标是：

**让我不用重复刚才说过的话。**

例如：

```text
最近 Agent Session
当前页面
最近几次 Dictation
最近提到的人
当前 Project
```

生命周期可以是：

```text
当前 Session
几十分钟
当天
```

根据类型不同自动失效。

例如：

> “他刚才说的那个方案。”

需要最近 Context 才能理解。

但一天以后没有必要继续保存这个指代。

---

# 13. 长期记忆

Long-term Memory 只保存真正稳定的东西：

```text
常用人名
组织关系
项目
产品名称
专业术语
固定拼写
语言习惯
常见纠错
用户明确要求记住的信息
```

以及：

```text
AniKuku
不是 Anikuku / Ani Kuku

BifroMQ
B / M / Q 大小写固定
```

---

# 14. Correction Memory

我认为这一层甚至比“LLM Memory”更重要。

记录：

```text
ASR:
work body

用户最终：
WorkBuddy
```

或者：

```text
ASR:
张月

用户：
张越
```

形成：

```text
Recognition Correction
```

累计几次以后：

> 经常把「张越」识别为「张月」，是否加入识别词库？

用户确认后进入长期 Knowledge。

这会让产品产生非常直观的：

> **越用越准。**

---

# 15. 不要把几千个人名全部塞给模型

真正的 pipeline 应该是：

```text
Audio
 ↓
ASR / Omni
 ↓
Raw Transcript
 ↓
Context Retrieval
 ↓
Candidate Entities
 ↓
Recognition Correction
 ↓
Final Text
```

例如原始结果：

> 明天让张月和王涛参加。

系统结合：

```text
当前组织
最近联系人
部门
名字相似度
历史纠正
```

只拿 Top-K 候选：

```text
张越
张玥
王涛
```

进行校正。

这样不会因为姓名库里有 5000 人，就让模型乱改名字。

---

# 16. Dictation 与 Agent 必须严格分开

这是一个很重要的产品原则。

## Fn Dictation

目标：

> **忠实输入。**

只能做：

```text
识别纠错
标点
口头语适度处理
热词修正
格式整理
```

不要擅自改变意思。

---

## Fn Fn Agent

目标：

> **执行意图。**

允许：

```text
改写
翻译
生成
删除
总结
调用工具
```

这样用户才会形成稳定信任：

> Fn 说什么就写什么。

> Fn Fn 才会“帮我做事情”。

---

# 17. Settings 信息架构

> 实现状态：`✅ 已完成`。界面结构、设置持久化、Keychain API Key 和真实 Qwen 连接测试均已接入。

Settings 不再使用第二套左侧导航。所有设置统一使用页面顶部水平 Tab：

```text
General | Voice Input | Voice Agent | History | Context & Privacy | Qwen & API
```

Knowledge 与 Memory 保持为一级侧栏目的地，不在 Settings 中重复。MVP 不提供 Advanced 空壳页面。

## Voice Input

```text
输入方式
○ Hold Fn
○ Tap Fn

自动停止
语言
文本整理程度
输入位置
```

## Voice Agent

```text
Double Fn

允许的工具
连续对话
```

## Qwen & API

```text
地域
- 北京
- 新加坡

API Key
- 输入 Key

Realtime 模型版本
- qwen3.5-omni-flash-realtime（默认）
- qwen3.5-omni-flash-realtime-2026-03-15

处理模型版本
- qwen3.8-omni-flash（默认）
- qwen3.5-omni-plus
- qwen3.5-omni-flash

测试连接
```

MVP 支持用户填写自己的 Qwen API Key。两个模型版本都使用下拉选择，只展示 App 已验证支持的 Qwen 型号或快照版本，不允许自由输入任意 model ID。Voice Input 默认使用 Qwen3.5 Omni Realtime，Voice Agent 与批处理 fallback 使用 Qwen3.8 Omni Flash。

## History

```text
自动清理
- 1 天
- 7 天
- 30 天（默认）
- 90 天
- 永久

保存原始语音（默认开启）
```

History 是输入记录，不是编辑器或录音资料库。每条记录包含触发模式、目标 App、时间、原始语音（若开启）、输入转写和最终写回文本。用户可以播放原始语音、查看输入与输出、加星标或取消星标；星标记录不参与自动清理。

History 默认仅保存在本机。关闭“保存原始语音”后，新记录只保留转写与最终输出；修改保留期限后，后台清理任务按新规则执行，但不删除任何星标记录。`AXSecureTextField`、密码管理器、银行应用与隐私浏览窗口永不写入 History。

## Context & Privacy

明确列：

```text
✓ Selected Text
✓ Current App
✓ Window Title
□ Clipboard
□ Browser Page
□ Recent Dictation
```

再提供：

```text
Never Access Apps
```

例如：

```text
1Password
银行 App
Private Browser
```

默认排除敏感应用是合理的。

MVP 数据规则：

* Context 只在用户触发 Fn Fn 时采集，不后台持续扫描。
* Voice Input 只发送音频和听写 instruction，默认不携带窗口内容。
* Voice Agent 发送前可从聆听 Pill 的 scope 图标查看实际 Context，并删除任意一项；Context 不常驻占用界面。
* `AXSecureTextField`、密码管理器、银行应用和隐私浏览窗口为硬性阻断，不仅是可配置开关。
* 原始音频先进入内存预缓冲；成功输入后，仅在“保存原始语音”开启且目标非敏感环境时加密存入本地 History。
* History 默认保留 30 天，可选 1 / 7 / 30 / 90 天或永久；星标记录不自动删除。
* History 与 Memory 分离：History 保存可回看的输入/输出记录，Memory 只保存明确的短期 Session、纠错与用户确认的长期知识。
* 诊断日志只记录状态、延迟、字符数和错误码，不重复记录原始语音、转写文本和 Context 内容。
* Short-term Memory 必须有 TTL；长期 Knowledge 只由用户确认后写入。

---

# 18. MVP 模型选型与技术架构

> 实现状态：`✅ 已完成`。App 已接入 Qwen3.5 Omni Realtime WebSocket 与 Qwen3.8 Omni Chat Completions，并在 Realtime 失败时使用完整内存录音执行一次批处理 fallback。

## 18.1 官方型号与发布状态

截至 2026-09-20，MVP 使用两个已在百炼官方模型目录和 API 文档中明确列出的型号：

```text
qwen3.8-omni-flash
qwen3.5-omni-flash-realtime
```

`qwen3.5-omni-flash-realtime` 支持 WebSocket 和 WebRTC，可持续接收麦克风音频并输出文本；`qwen3.8-omni-flash` 通过 Chat Completions / Responses 接收完整音频、文本和其他多模态输入。`qwen3.8-omni-flash` 没有 Realtime API，因此不把不存在的 Realtime 型号放进设置。

这两个型号都非常新。MVP 将已支持的 model ID 集中为一个简单列表，供设置页下拉选择，不建设远程配置或通用供应商系统。加入新型号或快照版本前必须完成基本回归测试。

官方资料：

* [Qwen3.8-Omni-Flash 模型说明](https://help.aliyun.com/zh/model-studio/qwen3-8-omni-flash)
* [Qwen Omni 非实时调用](https://help.aliyun.com/zh/model-studio/qwen-omni)
* [Qwen Omni Realtime 调用](https://help.aliyun.com/zh/model-studio/realtime)
* [百炼 Omni 模型目录](https://help.aliyun.com/zh/model-studio/omni/)

## 18.2 两个模型的分工

### `qwen3.5-omni-flash-realtime`

它是 MVP 的实时语音入口：

* 官方支持 WebSocket / WebRTC；macOS MVP 使用 WebSocket，避免为单机客户端引入 WebRTC 会话和媒体协商复杂度。
* WebSocket 接收实时音频块，适合按住说话和点击开停；MVP 暂不发送摄像头画面。
* 支持 Manual 模式：客户端在松开 Fn 后显式 `commit`，与 Hold Fn 交互完全对齐。
* 支持 Server VAD / Semantic VAD，可用于 Tap Fn 的可选自动停止。
* MVP 禁用独立 `input_audio_transcription`，通过严格听写 instruction 让主模型直接输出文本，避免叠加 ASR 调用。
* 仅启用文本输出，不生成音频；录音结束后通过 `response.text.delta / done` 增量展示和取得最终结果。

MVP 使用：

```text
Fn / Fn Fn Down
→ AudioCapture 生成 16-bit mono PCM
→ WebSocket append audio chunks
→ Fn Up / Tap Stop
→ input_audio_buffer.commit
→ response.create
→ response.text.delta（停止后增量预览）
→ response.text.done（最终候选文本）
```

Hold / Tap 都优先使用 Manual 模式。Semantic VAD 仅在用户开启“自动停止”时启用。

普通 Fn 使用 Realtime 主模型的严格听写响应；最终文本到达前的 delta 只能展示，不能提前写入目标 App。听写 instruction 要求忠实保留措辞和语言、只补自然标点，并仅把明确的数字、日期、时间、金额、百分比、单位、电话和编号转成阿拉伯数字。

### `qwen3.8-omni-flash`

它是 MVP 的理解、生成与结构化处理模型：

* 输入支持文本、图片、音频和视频，仅输出文本。
* 支持 Chat Completions 和 Responses。
* 支持 Function Calling；Knowledge 候选结果仍须本地 Schema 校验和重试，不能把模型输出当作可信数据库写入。
* 官方发布文章标称 1M Token 上下文，并介绍网联搜索和 Responses Session 缓存；不同地域的帮助中心当前仍有能力表差异。MVP 不依赖网联搜索、超长上下文或服务端 Session 缓存，必须以用户所选地域的连接测试和合同测试为准。
* 默认开启高强度思考；产品必须按任务显式设置 `reasoning_effort`，不使用默认 `xhigh`。
* 它是请求式 API：即使文本输出可流式返回，也不能替代持续上传麦克风音频的 Realtime 链路。

MVP 使用：

```text
Voice Agent
→ 完整 WAV + Selected Text / App / Window / Session / Top-K Knowledge
→ qwen3.8-omni-flash 一次完成转写与理解
→ Transcript + Intent + Proposed Text / Tool Call
→ Validate Target
→ Replace Selection / Insert At Cursor
```

```text
Knowledge Paste
→ 本地分段和 PII 预过滤
→ qwen3.8-omni-flash Function Call
→ Candidate Entities / Aliases / Relationships / Evidence
→ 本地归一化与去重
→ User Review
→ Knowledge Store
```

`reasoning_effort` 建议：

```text
none
→ 听写失败时的批处理 fallback、简单翻译、明确格式转换

low
→ 普通 Rewrite / Generate、Knowledge 实体抽取

medium
→ 涉及多段 Context、关系识别或 Tool Calling 的任务
```

MVP 不开放 `xhigh`，避免普通语音操作出现不必要的延迟和输出 Token。

## 18.3 为什么要同时使用两个

只用 `qwen3.8-omni-flash`：

* 必须在录音结束后上传整段音频，不能边说边发。
* 听写启动延迟更高，无法很好支撑 Fn 的“像键盘一样即时”。

只用 `qwen3.5-omni-flash-realtime`：

* 可以完成持续语音交互和工具调用，但 Realtime 会话的核心优化目标是低延迟交互。
* Knowledge 抽取、严格的关系 JSON、长文本分段、多上下文 Agent 和复杂修改更适合请求式模型的 reasoning、结构化重试与可观测流水线。

所以 MVP 采用：

> **Qwen3.5 Omni Realtime 负责直接听写，Qwen3.8 Omni 负责直接理解 Agent 音频与批处理。**

Voice Input 和 Voice Agent 各自只发起一次模型调用。普通 Fn Dictation 只调用 Realtime，再用本地 Knowledge Top-K 进行确定性纠错；Fn Fn 不再先做 ASR，而是把音频和 Context 一次提交给 Qwen3.8 Omni。

Realtime 连接失败但内存中仍有完整录音时，可以用 `qwen3.8-omni-flash` 作一次批处理 fallback。重试完成或失败后立即释放音频，不落盘。

## 18.4 具体架构

MVP 只实现 Qwen，不做多供应商设置页，也不做为了“以后可能换模型”而层层抽象的通用 SDK。

但音频、上下文、存储和 UI 不应直接依赖百炼网络对象。保留两个能力边界即可：

```text
RealtimeVoiceClient
├── connect
├── appendAudio
├── commit
├── cancel
└── textEvents

ReasoningClient
├── respondToAudio
├── transcribeAudio
└── extractKnowledge
```

核心模块：

```text
App
│
├── FnGestureRouter
├── AudioCapture
├── QwenVoiceEngine
│   ├── QwenRealtimeClient        // qwen3.5-omni-flash-realtime
│   └── QwenOmniClient            // qwen3.8-omni-flash
│
├── ContextCollector
│   └── TextTargetSnapshot
│
├── KnowledgePipeline
│   ├── TextChunker
│   ├── EntityExtractor
│   ├── Normalizer
│   ├── Deduplicator
│   └── ImportReview
│
├── KnowledgeStore
│   ├── Entity
│   ├── Alias
│   └── Relationship
│
├── MemoryStore
│   ├── Session
│   └── Corrections
├── HistoryStore
│   ├── Entry
│   ├── AudioAsset
│   ├── Star
│   └── RetentionCleaner
│
├── AgentRuntime
│   └── ToolRegistry
│
├── TextInteraction
│   ├── GetSelection
│   ├── ValidateTarget
│   ├── ReplaceSelection
│   └── InsertAtCursor
│
└── UI
    ├── DictationOverlay
    ├── AgentIntentOverlay
    ├── History
    ├── Settings
    └── KnowledgeImport
```

## 18.5 Qwen 配置

MVP 只需要四项：

* 地域：北京或新加坡，由 App 自动匹配对应 API 地址。
* API Key：用户填写，保存在本机 Keychain。
* Realtime 模型版本：默认 `qwen3.5-omni-flash-realtime`，可选固定快照 `qwen3.5-omni-flash-realtime-2026-03-15`。
* 处理模型版本：默认 `qwen3.8-omni-flash`，可选 `qwen3.5-omni-plus`、`qwen3.5-omni-flash`。

提供一个简单的“测试连接”按钮即可。首版不做自定义 Base URL、账号体系、复杂密钥状态、安全策略页面或详细账单展示。

## 18.6 MVP 技术验收指标

```text
Fn UI 首次反馈 P95             < 100 ms
Realtime 连接已就绪时，松开到首个结果 Token P95  < 1.5 s
短句听写完成 P95              < 2.0 s
Voice Agent 首个结果 Token P95     < 2.5 s
支持应用的插入成功率             > 98%
Replace 目标错位率                  = 0
Fn 系统组合键误触发率            = 0
Knowledge 未经确认写入率         = 0
```

数字是 MVP 目标而不是官方模型承诺。开发前必须先对北京和新加坡地域做真实网络 spike，根据目标用户地理位置确定默认地域。

兼容性矩阵至少覆盖：

```text
TextEdit / Notes / Mail
Safari / Chrome
Slack / VS Code
Microsoft Word
Terminal
Secure Text Field
```

开发顺序中必须先做一个语音模型 spike，不直接假设 Realtime 的任意文本输出都等于忠实 ASR。用同一批至少 200 条带人工真值的音频比较：

```text
A. qwen3.5-omni-flash-realtime + 严格听写 instruction
B. qwen3.8-omni-flash 直接处理整段音频，reasoning_effort=none
```

测试集覆盖普通中文、中英混说、人名项目名、数字、标点、长句、环境噪声和不同麦克风。除 CER / WER 外，必须单独统计：

* 人名和专有词 exact match。
* 数字、否定词、时间的语义级错误。
* 模型擅自改写、摘要或删除内容的次数。
* 首字延迟、完成延迟和单分钟成本。

默认选择 A；B 只作为 Realtime 失败后的单次 fallback。如果两者都达不到门槛，应暂停语音方案并更新 PRD，不能为了维持“只支持两个模型”而降低忠实度标准。

---

# 19. 从 0 构建还是 Fork

我的建议非常明确：

## 新建自己的 Repo，从 0 建产品架构，但不要从 0 重写基础设施。

也就是：

> **Greenfield + selective reuse**

而不是 Fork 某个项目后一路裁剪。

原因在于我们现在的核心产品模型已经和这些项目不同。

Pindrop 当前除了 Dictation，还有 Voice Notes、Meeting、Library、Notes、Diarization、Stats、Models、MCP 等一整套系统；它使用 Swift/SwiftUI + SwiftData，架构已经非常完整。

如果直接 Fork：

```text
Pindrop
 ↓
删除 Meeting
删除 Notes
删除 Library
删除 Stats
重构 Dictation
加入 Fn Router
加入 Agent
加入 Context
加入 Memory
重写 UI
```

最后很可能变成：

> 先花大量精力理解和拆别人的产品，再把它变成自己的产品。

这会形成很大的 **negative code / pruning debt**。

---

# 20. Pindrop 应该怎么用

不是 Fork。

而是重点参考或选择性复用这些 MIT 代码：

```text
Audio Capture
Permissions
Accessibility insertion
Menu bar lifecycle
Floating overlay
Context Engine / Secure Field 过滤
Settings patterns
Updater
对应单元测试
```

Pindrop 是 MIT License，而且目前工程结构已经把 Services、Transcription、Models、UI 等模块拆得比较清楚，所以适合当工程参考。

但不要移植它的大型 `AppCoordinator`。只参考生命周期和协调责任，具体复用应限定在边界清晰、依赖可控、有对应测试的小型服务。

---

# 21. 全局快捷键与 Fn 的开源实现对照

本轮对实现做了源码级对照，而不是把“全局快捷键”笼统地等同于“输入监控”：

| 项目 | 实现方式 | 权限结论 |
| --- | --- | --- |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Carbon `RegisterEventHotKey` | 普通组合快捷键无需隐私权限，也可用于 Mac App Store |
| [Looped Whisper](https://github.com/loopedautomation/whisper/blob/main/Sources/Whisper/Hotkeys/FnKeyMonitor.swift) | `.listenOnly` CGEvent tap 监听 Fn | 需要 Input Monitoring |
| [VoiceInk](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Shortcuts/Coordination/ShortcutMonitor.swift) | `.defaultTap` active CGEvent tap | 使用 Accessibility，可识别单独 Fn |
| [RedWhisper](https://github.com/redoyan/RedWhisper/blob/main/voxtape.py) | active Quartz event tap | 使用 Accessibility，可识别 Fn flags |

SayKuku 因此采用两层策略：`⇧⌘D` 与 `⇧⌘A` 使用 Carbon，永远不依赖隐私权限；单独 Fn / Fn Fn 在 Accessibility 已授权后使用 `NSEvent.addGlobalMonitorForEvents`，并用 local monitor 覆盖 App 自身前台事件。应用不创建 CGEvent tap，也不申请 Input Monitoring。

## 21.1 Looped Whisper 更值得参考的部分

Looped Whisper 的产品方向和我们更接近。

它已经有：

```text
Fn / Globe
Hold-to-talk
Double-tap
Selected text
Voice instruction
Rewrite in place
Vocabulary
Learning writing style
```

Fn 不能作为普通 global hotkey 注册。参考实现中，passive listen-only tap 会触发 Input Monitoring，active tap 则使用 Accessibility；但为彻底避免 event tap 带来的权限歧义，SayKuku 最终采用 AppKit 全局/本地 event monitor，并且仅在 Accessibility 已经授权后安装。全局 monitor 无法吞掉 macOS 自身的 Fn / Globe 动作，因此当系统把它设为切换输入法、Emoji 或听写时，App 明确提示用户在系统键盘设置中改为“无操作”，而不是暗中修改系统偏好或重新引入 event tap。

这部分代码/设计特别值得参考：

```text
Fn detection
Rewrite selection
Vocabulary
Style / correction learning
```

但它当前把 Hold Fn 和 Double-tap Fn 作为互斥配置，没有实现本 PRD 要求的“Hold / Tap Dictation 与 Double Fn Agent 同时存在”。因此 `FnKeyMonitor` 可作为底层事件检测参考，`FnGestureRouter` 必须自己设计和测试。

它也是 MIT。

但我也不会直接 Fork 它。

因为：

```text
它接近我们的 Interaction
但还不是我们的 Product Architecture
```

我们还需要：

```text
Agent Session
Context Engine
Knowledge Graph
Memory
Import
Screenshot extraction
Tool Runtime
Agent UI
```

最终仍然会经历大规模重构。

---

# 22. VoiceInk

把它当作：

```text
成熟产品 UX Reference
失败路径 / 边界情况 Reference
Knowledge Import / Correction Learning 的产品 Reference
```

不要作为代码底座。

当前项目是 GPLv3。

如果我们的产品以后可能闭源或采用不同商业授权，引入 GPL 派生代码会给授权策略带来明显约束。

因此：

```text
可以研究交互、需求和边界情况
不要复制代码进 Core
```

---

# 23. VibeTyping

可以看：

```text
InputMethodKit
Audio
VAD
原生输入法生命周期
```

当前仓库只在 README 中写了“MIT License”，但根目录没有完整 LICENSE 文件。授权未由作者补齐前，只作技术参考，不复制实现。

它当前的 VAD 也是固定 RMS 阈值和静音计时器，适合理解流程，不作为生产 VAD 底座。

但我们的主路线不建议 InputMethodKit。

因为产品已经不是：

> 一个系统输入法。

而是：

> 一个能读取 Context、操作 Selection、调用 Tool 的全局 Voice Agent。

Accessibility + Event Tap 反而更自由。

---

# 24. 可以直接采用的基础库

有些东西完全没必要自己造。

例如获取当前选中文字，可以先用 MIT 的 `SelectedTextKit` 做跨应用 POC。它已经封装 Accessibility、菜单 Copy、快捷键模拟等多种 fallback，但会涉及焦点、剪贴板和模拟键盘副作用，通过目标应用兼容性测试后再决定是否正式依赖。

普通可配置快捷键也可以采用 `KeyboardShortcuts`；它是 MIT，并且提供原生 SwiftUI 设置组件。Fn 属于特殊 modifier，使用 Accessibility 保护下的 AppKit `NSEvent` monitor 单独处理。

因此最终代码关系更推荐：

```text
Our App
│
├── Apple frameworks
│   ├── AVFoundation
│   ├── Accessibility
│   ├── Vision
│   └── SwiftUI
│
├── Small MIT dependencies
│   ├── SelectedTextKit
│   └── KeyboardShortcuts
│
├── Qwen APIs
│   ├── qwen3.5-omni-flash-realtime
│   └── qwen3.8-omni-flash
│
└── Learn / selectively port
    ├── Pindrop
    └── Looped Whisper
```

而不是：

```text
Fork Pindrop
└── 魔改成我们的产品
```

---

# 25. MVP 应该砍到这里

第一版需要把下面几个体验做到极好：

```text
Fn
→ Voice Input
→ qwen3.5-omni-flash-realtime 直接听写
→ 准确进入当前光标
```

```text
Fn Fn
→ Voice Agent
→ qwen3.8-omni-flash 直接接收语音并理解与执行
→ 理解 selected text / current app
→ Translate / Rewrite / Generate
→ 校验目标后自动 Replace Selection / Insert At Cursor
```

以及：

```text
Knowledge
→ 手动添加
→ 粘贴文本
→ 实体 / 别名 / 关系抽取
→ 归一化 / 去重 / 冲突标记
→ 用户确认后入库
```

和：

```text
Memory
→ 最近上下文
→ 人名/术语
→ 用户纠正学习
```

和：

```text
History
→ 原始语音 / 输入转写 / 最终输出
→ 默认 30 天自动清理
→ 星标永久保留
```

先不要做：

```text
PDF / DOCX / XLSX 导入
截图 OCR 导入
Meeting
录音管理
大而全 Library
Speaker Diarization
统计面板
复杂 Workflow Builder
Agent Marketplace
全电脑自动化
多模型 / 多供应商选择器
```

因为这些都不是验证这个产品最核心价值所需要的。

第一阶段真正应该验证的是一句话：

> **用户会不会开始习惯：Fn 是键盘，Fn Fn 是 AI。**
