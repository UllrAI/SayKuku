# Typeless 本地样本研究与历史实验

研究日期：2026-10-24。本 PR 保留最新主线的中文优先单次 Realtime 与可选 Flash 流程，提交导出工具、研究报告和显式启用的评测入口，不恢复旧两阶段实现。

当前 `39dcc4b` 已重测 **batch 单次**：12 条私人录音全部完成，40 句合成音频完全匹配 30/40，均无请求错误；没有调用 Flash 二次整理。**Realtime 仍待开发 Workspace ID，尚未执行**，不能用 batch 成绩代替。下文 33/40 和约 13 秒来自旧本地实验，均不是本轮当前主线结果。

报告不包含私人对话全文、录音、数据库、凭证或具体用户目录。

## 范围与版本

本 PR 加入研究报告、只读导出工具、合成 fixture 测试及显式启用的单次录音评测入口。保留当前主线的中文优先单次 Realtime 与可选 Flash 二次整理流程，不恢复历史实验实现，也不修改 App 代码、模型选择、配置或旧测试。

| 版本 | 在本报告中的用途 |
| --- | --- |
| `cbf1e575136548373f83f30f3490ad8616432d82` | 旧实验基线；下文“旧基线”与原版输出均指它 |
| `cdf2e1489b5edbee46222d8d698fccf62d4a0e8a` | 本地历史实验快照，包含先识别再文本整理及其审查修复；未随本 PR 合入 |
| `39dcc4bce8d9a958dbc648a8da12e284542e5a2d` | 本 PR 对照的当前主线，已合入 #175、#177 等后续设计 |

旧实验的 40 句与 12 条录音结果不能作为当前主线的性能或质量结论。当前方案及其中文优先取舍以 [中文单次听写接入记录](DICTATION_SINGLE_PASS_CHINESE_2026-10-22.md)、[SinglePassDictation](../Sources/SayKuku/Qwen/SinglePassDictation.swift) 和 [DictationRefinement](../Sources/SayKuku/Qwen/DictationRefinement.swift) 为准。

## 一手数据与证据边界

Typeless 数据来自本机 SQLite 数据库及其 `Recordings` 目录。`refined_text` 可读，`debug_info` 内嵌的调试内容与 `audio_context` 为加密内容，本研究未解密，也没有获得 Typeless 的内部 prompt。

最终文本可以证明存储结果包含哪些词、段落和列表，不能单独证明原音中的哪些词被删除或改写。下文的格式统计是直接观察，关于清洗规则的解释是行为推断；Typeless 输出和机器逐字识别都不能代替人工回听的真值。

导出通过 SQLite 只读连接生成数据库快照，复制录音目录，再合并 `history` 与 `history_v2`。共享字段以新表为准，旧表独有的用户编辑、编辑状态与撤回标记仍保留；不透明字段留在数据库快照，JSONL 和 CSV 供检索。文件清单记录导出时间、缺失音频 ID、录音大小和 SHA-256，源文件与副本已核对一致。[导出实现](../Scripts/export-typeless.py)

## 导出覆盖与样本特征

时间范围为 UTC 2026-02-06 08:06:20 至 2026-10-23 13:50:44。

| 项目 | 数量 | 口径 |
| --- | ---: | --- |
| 去重后的全部历史 | 4,416 | `history_v2` 行数 |
| 有输出文本 | 3,600 | `refined_text` 非空 |
| 听写输出 | 3,581 | 有文本且 `mode = voice_transcript` |
| 翻译输出 | 16 | 有文本且 `mode = voice_translation` |
| 语音命令输出 | 3 | 有文本且 `mode = voice_command` |
| 关联本地 OGG 录音 | 4,410 | 顶层 `Recordings/*.ogg` |
| 录音目录递归文件 | 4,811 | 含调试片段，共 184,913,873 字节 |
| 无关联本地录音的历史 | 6 | 原记录保留，清单列出缺失 ID |
| 旧表记录 | 2,426 | 所有 ID 均已存在于新表，不重复计入 |

全部历史中，3,638 条状态为 `completed`，731 条为 `dismissed`，32 条为 `error`，15 条状态为空。“完成”与“有输出文本”不是同一口径。翻译模式与普通听写分开统计，避免把翻译行为误当成默认清洗规则。[一手来源：导出的数据库快照与清单；私人数据保存在仓库外]

对 3,581 条有文本的听写记录机械统计：

| 特征 | 条数 | 占比 |
| --- | ---: | ---: |
| 含空行 `\n\n` | 1,410 | 39.4% |
| 含行首编号项 | 403 | 11.3% |
| 同时含汉字和英文字母 | 2,374 | 66.3% |
| 含“好像/可能/我觉得/是不是/应该/如果”任一表达 | 1,532 | 42.8% |

2026-09-01 以后的 155 条有文本听写中，64 条含空行、20 条含编号项。段落组织、并列要求、中英混说和不确定语气值得优先检查；这些比例不是质量评分，也不能证明每个换行或列表都是 Typeless 自动生成的。[一手来源：`history_v2`，统计规则见文末]

## 样本提示的整理边界

| 观察 | 值得验证的能力 | 保真边界 |
| --- | --- | --- |
| 长需求常分成背景、问题与后续要求 | 按完整意思分段 | 不改变顺序、因果或主体 |
| 并列要求常使用编号项 | 区分独立项目与连续叙述 | 不增删项目，不给短消息强加列表 |
| 输出通常可以直接发送 | 清理口癖、重复起句与明确改口 | 不总结、扩写或补论据 |
| 推测、疑问和条件经常保留 | 保护不确定性与条件范围 | 不把建议改成决定、推测改成事实 |
| 中英技术词混用常见 | 保留原语言、术语与书写规则 | 不因清洗翻译或猜改名称 |
| 参考输出也有残留重复 | 回听后判断应保留的强调 | 不把复刻 Typeless 当成唯一标准 |

旧基线的指令一方面要求删除口头禅、偶发重复和废弃开头，另一方面禁止改写、增加未说出的词和 Markdown，并将换段绑定到显式口令。这可能压低句法修顺与结构整理的空间。但后续探针表明，放宽这些措辞也不足以稳定触发所需行为，不能把差距完全归因于 prompt 长度或措辞。这一分析针对 `cbf1e575`，不是对当前 `SinglePassDictation` 的结论。

## 旧基线上的历史实验

旧基线录音首轮 11 条成功、1 条超时，重试后补齐 12 条。完整基线中 9 条仍含“嗯/呃/哎”，没有自然空行或编号列表；首轮成功的 11 条中，5 条轻度整理与独立逐字识别结果完全相同。[本机历史证据：`before.json`、`before-complete.json`]

| 历史方案 | 观察 | 当时的处理 |
| --- | --- | --- |
| 增强 system、user 任务措辞或调整音频/文本顺序 | 前三条音频试验没有明显改善 | 继续区分指令与模型行为 |
| 音频识别与整理合并，思考力度 `low` | 能删口癖，但有独立开头、行动词或条件丢失 | 放弃该实验候选 |
| 固定逐字文本，再做文本整理 | 三条针对性探针保留上述信息，仍有等待代价 | 在旧基线上试验两阶段 |
| 固定逐字文本，思考预算 256 | 等待缩短，结构整理仍弱 | 历史候选采用预算 512 再评测 |

单次音频候选的疑点包括：样本 `f9aff849-…` 删除独立开头，`d50bfa80-…` 改变行动词，`3bade693-…` 丢失“如果”。文字变干净不能抵消这些风险。固定文本探针避免了重新识别带来的变化，但它的输入仍是机器识别，不是人工逐字稿。[本机历史证据：`after-low.json` 与文本探针]

`cdf2e148` 本地快照曾将批处理与 Realtime 改为先逐字识别，再调用同一个文本整理函数；逐字文本以 JSON 字符串作为数据传入。默认 Qwen3.8 文本整理使用预算 512，原样模式直接返回识别结果。该快照的审查还修复了 Realtime 整理结果缺少最终空白/无语音校验，以及旧 Omni 预设的流式兼容；真实合成文本探针发现 3.5 Flash 拒绝正数思考预算，遂按型号能力处理，并保留 SSE 服务错误。这些是旧实验的实现和修复历史，本 PR 不移植这些 App 改动。

## 历史评测结果及局限

以下数字比较的是 `cbf1e575` 旧基线与本地两阶段候选，使用北京地域、默认 `qwen3.8-omni-flash` 和同一套 40 句合成音频，**没有在当前主线上复跑**。

| 历史 40 句回归 | 旧基线 | 历史两阶段候选 |
| --- | ---: | ---: |
| 完全匹配参考文本 | 21/40（52.5%） | 33/40（82.5%） |
| 请求错误 | 0 | 0 |
| 空格规则失败 | 10 | 2 |
| 大小写规则失败 | 1 | 1 |
| 英文词保留规则失败 | 2 | 2 |
| 标点规则失败 | 0 | 1 |

这是固定开发集的完整匹配率，不是真实语音总体准确率，也不是独立盲测。第 01 条遗漏后半句的 iOS/API 内容，并出现不对应的人名和动作短语；第 28 条遗漏 meeting。未捕获这些请求内部本次识别阶段的 raw，不能将丢失全部归因于 ASR，也不能宣称全部语义保真。[本机历史证据：旧实验输出及 `mixed-two-stage.txt`]

| 历史 12 条真实录音开发样本 | 旧基线 | 历史两阶段候选 |
| --- | ---: | ---: |
| 请求成功 | 12/12 | 12/12 |
| 含“嗯/呃/哎” | 9 | 0 |
| 含自然空行 | 0 | 3 |
| 含编号列表 | 0 | 3 |

定性检查中，候选保留了上述三条样本的开头、行动词和“如果”，但 `0755c7e5-…` 等仍有“要/不要”的分歧，需回听。这些样本用于开发和选择方案，不是保留样本盲测或人工金标。诊断字段中的逐字结果也不是该次完整流程内部重新生成的 raw，不能直接用它归因编辑错误。[本机历史证据：`before-complete.json`、`after-two-stage.json`]

该批历史两阶段请求耗时中位数为 13.046 秒，最短 6.958 秒、最长 28.459 秒，包含识别与文本整理。没有匹配口径的旧基线耗时，因此不声称更快。这组数字不能与当前中文单次评测的耗时直接比较。私人目录保留带录音的三列对照 `comparison.html`；该文件和其中的录音、全文均不提交。

## 与当前主线 #175、#177 的对照

当前主线已经完成另一条路线。[#175](https://github.com/UllrAI/SayKuku/pull/175) 统一原样、轻度整理、二次整理三档并迁移既有偏好；[#177](https://github.com/UllrAI/SayKuku/pull/177) 按用户中文优先的选择，接入新的单次 Realtime 提示。当前实现和已记录评测比旧基线更新，应保留其产品取舍。

| 维度 | 历史本地实验 | 当前主线实现 |
| --- | --- | --- |
| Realtime 轻度整理 | 先逐字识别，再必经文本整理 | `SinglePassDictation` 在一次音频响应中生成 `negations`、`transcript`、`text`，只将 `text` 交给调用方 |
| 二次文本处理 | 轻度整理默认必经，同一 Omni 模型、预算 512 | 仅 `.refined` 档启用 `DictationRefinement`，固定使用 `qwen3.8-flash`，两秒截止，超时、错误或审核不通过时保留首次结果 |
| 批处理 | 先逐字音频识别，再文本整理 | 保留独立的纯文字批处理提示，不将 Realtime 结构化策略直接套用；选择二次整理时再走共享 refinement |
| 段落与列表 | 历史文本整理阶段允许生成结构 | 首次生成负责排版；当前 refinement 要求保留已有换行和列表，不创建或删除列表 |
| 证据重点 | 少量真人录音及 40 句旧开发集 | 中文与中英混合优先的冻结评测、可选二次抽样与生产接入检查；具体口径见现有文档 |

依据：[SinglePassDictation](../Sources/SayKuku/Qwen/SinglePassDictation.swift)、[DictationRefinement](../Sources/SayKuku/Qwen/DictationRefinement.swift)、[VoiceWorkflow](../Sources/SayKuku/Voice/VoiceWorkflow.swift)、[中文单次听写接入记录](DICTATION_SINGLE_PASS_CHINESE_2026-10-22.md)。`negations` 和 `transcript` 与 `text` 来自同一次生成，不能视作独立的保真证据；当前源码也明确了这一点。

现有中文记录注明，纯英文有已知退化，中英混合严格匹配也非各项均改善；用户按中文优先接受取舍。可选二次整理抽样既有修复也有引语重复被误删，不能宣称总能改善。这些已有结果与本报告的旧实验使用不同样本、路径和计分方式，不能横向排名。

Typeless 样本后续适合用来检查长录音分段、隐式列举、远距离改口与条件保留。若要改变当前流程，需在当前单次与可选二次两档上另建同音频对照，并按 [听写润色评测](DICTATION_POLISH_EVAL.md)、[中英混说评测](MIXED_LANGUAGE_EVAL.md) 和中文方案的既有口径验证。本 PR 提供研究材料、导出能力和新基线评测入口，不以旧成绩替代这项验证。

## 当前基线的新一轮实测

本轮目标是直接重放 `39dcc4b` 的生产单次路径，不使用旧实验的两阶段整理。新增 [显式启用的样本评测](../Tests/SayKukuTests/TypelessSampleEvalTests.swift) 复用生产 Realtime `connect/append/commit`，批处理单独复用 `transcribeAudio`；两者均使用 `.light`，不调用可选的 `DictationRefinement`。

| 数据集 | 生产路径 | 本轮状态 |
| --- | --- | --- |
| 12 条私人录音 | Realtime 单次 | 待执行，需要明确的开发 Workspace ID |
| 12 条私人录音 | 批处理单次 | 12/12 完成，0 请求错误 |
| 40 句固定合成音频 | Realtime 单次 | 待执行，参考文本只用于本地计分 |
| 40 句固定合成音频 | 批处理单次 | 40/40 完成，30/40 完全匹配，0 请求错误 |

两组已完成请求均为北京地域、`qwen3.8-omni-flash`、自动语言识别、优先数字、完整末尾标点、无目标 App/表达偏好/记忆，仅走 batch `.light`，报告显式记录基线 SHA。当前 batch 保留纯文字策略，与 Realtime 的 `SinglePassDictation` 结构化单次不是同一路径。

| 当前 batch 单次指标 | 12 条私人录音 | 40 句固定合成音频 |
| --- | ---: | ---: |
| 请求完成 / 请求错误 | 12/12 / 0 | 40/40 / 0 |
| 含“嗯/呃/哎” | 1 | 0 |
| 含空行 / 编号列表 | 0 / 0 | 0 / 0 |
| 完全匹配参考文本 | 不设人工金标 | 30/40（75.0%） |
| 总耗时中位数 | 3.997 秒 | 1.033 秒 |
| 总耗时范围 | 1.489–5.141 秒 | 0.835–2.823 秒 |

固定 40 句的规则失败数为：空格 2、大小写 1、英文词保留 2、标点 0；一条可以失败多项。私人录音的口癖、空行和列表只是机械特征，不是保真通过率；40 句完全匹配同样不是总体准确率或独立盲测。未做人工回听裁决，也没有依据把误差归因到单一阶段。[本机本轮证据：`latest-main-39dcc4b/private-batch.json`、`latest-main-39dcc4b/mixed-batch.json`]

本次本机开发/正式偏好及环境变量都未取得可用 Workspace ID；当前应用的 Realtime 配置使用工作空间专属主机。评测未猜测 ID、未修改 endpoint，也未以空配置发送 Realtime 请求。因此两组 Realtime 仍待配置后重放，连接、上传和提交等待时间也尚无本轮实测；batch 耗时不替代这些数据。[配置源码](../Sources/SayKuku/CoreModels.swift)

40 句的完全匹配和规则失败只作质量记录，不因文字不匹配让请求测试失败；私人录音不用与 Typeless 完全相同来硬断言通过。可选二次 Flash 本轮未测，以上结果不支持更改用户已选择的中文优先取舍。

## 可回听的匿名样本索引

这 12 条均为完成的普通听写，关联本地录音存在。选择依据是最终文本的任务特征，尚未回听时不能认定原音含特定口误。

| 匿名 ID | 秒数 | 检查维度 |
| --- | ---: | --- |
| `03e5dda2-905f-4670-aeac-412873e765f6` | 12.976 | 英文术语与后续要求分段 |
| `8d402365-a74b-4953-93fe-3194f64a5211` | 12.176 | 数字、配置要求与允许的代价 |
| `860ebe28-3f78-440d-abab-5d6d7c6c380b` | 16.704 | 多个并列问题 |
| `bc4072a4-e35b-47f4-b145-635f0e3b8171` | 23.984 | 现状、风险与不确定语气 |
| `0755c7e5-9c2f-4759-9ab2-5d52c426394b` | 23.808 | 命令作为正文、否定词分歧 |
| `d50bfa80-0f6c-43fa-8d38-8981c4f6be97` | 52.896 | 长需求、因果与限定条件 |
| `3bade693-c088-4225-b6c6-b830f9dab01f` | 18.224 | 两个并列方案与条件 |
| `03107acc-df24-498d-9d94-c26228cb566b` | 53.632 | 范围调整及三个后续要求 |
| `6deeaa7b-f167-4b5f-90b0-2607ef439be2` | 13.304 | 残留重复与未完成表达 |
| `616c635b-3e15-4c08-bca4-07f0716ca176` | 9.280 | 短句、否定与替代目标 |
| `f9aff849-2516-4e08-b0a6-63ccf679c542` | 25.744 | 开头、推测、条件与可能性 |
| `4be826d2-eb04-4fc0-9150-f0e854d934fa` | 52.000 | 产品名、背景及两项权限要求 |

回听应优先核对事实、数字、专有名词、动作、否定、条件、顺序与不确定性，再看重复删除、句法和结构。更接近 Typeless 排版不等于更忠实。真正的保留样本需与调 prompt 的样本分开；未完成的人工核对不能写成已通过。

## 本 PR 可复跑的工具与评测

导出仅使用 Python 标准库，不联网、不读 Keychain、不修改源数据库。输出路径应在仓库之外，且必须是一个不存在的新目录：

```bash
python3 -B Scripts/export-typeless.py \
  --output "$HOME/Documents/Typeless-private-export"
```

默认源为当前用户的 `Library/Application Support/Typeless`；可用 `--source` 指向另一份本地数据。导出包含 `typeless.db`、`Recordings/`、`history.jsonl`、`history.csv` 和 `manifest.json`。目录含私人文本与录音，应留在本机私人目录，不加入 Git 或 PR 附件。

合成 fixture 验证重叠 ID 去重、旧编辑字段保留、BLOB metadata 编码、缺失录音、嵌套录音与调试片段，以及源数据库字节不变：

```bash
python3 -B -m unittest discover -s Scripts/tests -v
git diff --check
```

当前单次重放要求提前准备 16 kHz 单声道 PCM16 WAV 和外部 JSON 数组。两种 transport 都先读取 `fmt ` 和 `data` chunk，校验 PCM 编码 1、单声道、16,000 Hz、16-bit；缺少格式或不符时在请求前记录错误，不将其他音频误标为 16 kHz。此前已完成的 12/40 条输入已另用 Python `wave` 核实格式正确，这项校验修复不改变其既有 batch 结果。

每项至少包含 `id`、`wav`，可选 `typeless`、`expected` 和旧 `verbatim`。`wav` 支持绝对路径或相对于 JSON 文件的路径；三个参考文本字段均不发给模型，旧 `verbatim` 也不是本轮内部 raw。

```json
[
  {
    "id": "anonymous-sample-id",
    "wav": "wav/sample.wav",
    "typeless": "可选：本机参考输出",
    "expected": "可选：固定评测参考文本"
  }
]
```

普通测试会跳过评测，不读样本、Keychain 或网络。真实重放读取开发版 Keychain，并将明确指定的 WAV 发给当前模型；输出报告应在仓库外。Realtime 不推断 Workspace ID，必须显式提供：

```bash
SAYKUKU_TYPELESS_EVAL=1 \
SAYKUKU_TYPELESS_TRANSPORT=realtime \
SAYKUKU_TYPELESS_SAMPLES="$HOME/Documents/Typeless-private-export/samples.json" \
SAYKUKU_TYPELESS_REPORT="$HOME/Documents/Typeless-private-export/current-realtime.json" \
SAYKUKU_TYPELESS_BASELINE_SHA=39dcc4bce8d9a958dbc648a8da12e284542e5a2d \
SAYKUKU_TEST_WORKSPACE_ID=your-development-workspace \
swift test --filter TypelessSampleEvalTests
```

批处理独立运行时将 `SAYKUKU_TYPELESS_TRANSPORT` 设为 `batch`，并选择另一个报告文件；它不要求 Realtime Workspace ID，也不作为 Realtime 失败后的静默回退。地域通过 `SAYKUKU_TEST_REGION` 选择，默认北京。`SAYKUKU_TYPELESS_LANGUAGE`、`SAYKUKU_TYPELESS_NUMBER_FORMAT` 默认分别为 `automatic`、`preferDigits`；`SAYKUKU_TYPELESS_DATASET` 默认 `private-recordings`，固定 40 句运行时应改为对应数据集名称。`SAYKUKU_TYPELESS_SOURCE` 可补充本机证据来源标签。

报告记录基线、数据集、传输方式、模型、语言、数字和标点配置；基线应由 `SAYKUKU_TYPELESS_BASELINE_SHA` 显式标记，未设置时写 `unspecified`，不推断代码版本。每条保存实际输出、错误、总耗时及 Realtime 各阶段耗时。Realtime 提交截止与生产 `VoiceWorkflow` 一致，为 `15 + 音频秒数 / 4` 秒，并以 `realtimeCommitTimeoutSeconds` 逐条记录；未提交的条目不填该字段。有 `expected` 时另记 `exactMatch` 和现有中英规则的失败项。每轮先清空旧结果，再逐条原子落盘；运行中尚无结果的条目不算成功，任一请求错误会在处理完其余样本后使测试失败。控制台只输出匿名 ID、进度与错误类型，全文留在私人报告。

旧两阶段实验的录音重放与旧预设 live probe 只存在于本地 `cdf2e1489b5edbee46222d8d698fccf62d4a0e8a` 快照，并依赖未提交的私人样本与开发环境。复核历史结果必须切到该快照并取得相应材料；当前新增入口重放的是新主线单次路径，不复现旧两阶段结果。

## 本 PR 的离线验证状态

- 输入校验修复前，相关 18 项 Swift 测试通过；修复后运行 `swift test --filter 'TypelessSample|SinglePassDictation|DictationRefinement'`，19 项测试、4 个 suite 通过，包括缺失格式、采样率、声道、编码与位深的拒绝检查，以及可变大小和奇数字节 padding chunk 的合法解析。默认 live 入口跳过，没有因此访问私人文件、Keychain 或网络。
- `python3 -B -m unittest discover -s Scripts/tests -v` 的 1 项合成导出 fixture 通过；`git diff --check` 通过，无新编译警告。
- 完整 suite **未通过**：输入校验修复前的 PR 候选运行 328 项测试、38 个 suite，记录 75 个 issue；独立无改动 `39dcc4b` 基线运行 325 项、36 个 suite，也记录相同 75 个 issue，49 个失败测试名称完全一致，没有候选独有失败。问题分布为 Voice workflow 56、Fn 14、Workflow timing 4、Microphone 1。[本机验证证据：`pr-full-tests.log`、`baseline-full-tests.log`]

对照时系统 Secure Input 为开启状态，Voice/Fn 中可见敏感目标检查阻止执行；不能将所有失败都归因为这一因素。Microphone、timing 等是同环境下基线也存在的失败。本 PR 没有修改 App 权限或模式来让 suite 通过；格式与截止修复后仅重跑上述相关离线检查，不宣称完整 suite 已绿。

## 统计复核

以下查询针对导出的数据库快照；连接使用 SQLite 只读模式，不读取用户配置或凭证：

```python
import re
import sqlite3

connection = sqlite3.connect("file:<private-export-dir>/typeless.db?mode=ro", uri=True)
connection.row_factory = sqlite3.Row
rows = connection.execute("""
    SELECT id, created_at, refined_text, mode
    FROM history_v2
    WHERE length(refined_text) > 0
""").fetchall()
texts = [row["refined_text"] for row in rows if row["mode"] == "voice_transcript"]
paragraphs = sum("\n\n" in text for text in texts)
numbered = sum(bool(re.search(r"(?m)^\s*\d+[.、)]\s*\S", text)) for text in texts)
mixed = sum(bool(re.search(r"[\u4e00-\u9fff]", text) and re.search(r"[A-Za-z]", text)) for text in texts)
uncertainty = sum(bool(re.search("好像|可能|我觉得|是不是|应该|如果", text)) for text in texts)
```

仓库只保存工具、合成测试、统计口径、匿名 ID 与研究结论；全文、录音、数据库和对照页面继续保留在仓库外。
