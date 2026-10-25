# 听写润色评测

当前生产方案、完整长短回归与配置说明见 [2026-10-25 复验](DICTATION_UNIFIED_EVAL_2026-10-25.md)。下方保留各轮探索的原始结果，已弃用的保护规则不代表当前实现。

> 修改听写 Prompt 中与轻度整理有关的部分（口头禅、改口、列表、防扩写、目标 App 语气）时，在 Mac 上重跑本评测，并把改动前后两次的汇总贴进 PR。中英混排写法照旧由 [中英混说评测](MIXED_LANGUAGE_EVAL.md) 负责，两套都要跑。

准备工作（Xcode、开发版 Keychain 里的 Qwen API Key、普通话语音）与 [中英混说评测](MIXED_LANGUAGE_EVAL.md#怎么跑) 相同。

## 评测集

`Tests/SayKukuTests/Fixtures/dictation-polish.json` 共 58 条。与中英混说评测按原文完全一致计分不同，这里每条只检查它要测的行为，措辞或标点上的无害差别不算失败。

| 类别 | 条数 | 测什么 |
| --- | --- | --- |
| `fillers` | 11 | 去掉嗯、呃、那个、就是、然后、uh、um、you know，意外重复和起头重说；有 1 条“那个”“然后”是内容，必须保留。第 11 条（排在文件末尾，前面各条的缓存音频序号不变）来自真实试用：句中的“嗯”连同两侧逗号去掉，前后连成一句。 |
| `selfCorrection` | 19 | 中英改口提示词（不对、不是…是、我是说、算了改成、actually、I mean、scratch that、make that）只留最终说法，被放弃部分里没被推翻的信息要保留；3 条中“不对”“不是…是”“actually”是内容，不能合并。末尾 7 条是没有提示词的重说和自我修正：第 1 条来自真实试用（“这个，这客户端”“登录 Web 了，Web 端了”），其余覆盖“X 了，X Y 了”、“那个，那份”、半个词重说和英文 “we should, we need to”。 |
| `list` | 10 | 明确枚举 2 项及以上排成编号列表，每项一行，保留引子句和收尾句；连贯叙述、句内并列保持段落。 |
| `noExpansion` | 10 | 普通句子和口述的问题、指令（写邮件、翻译、写诗、列方法）只转写，不回答、不执行、不明显变长。 |
| `chatTone` | 8 | 目标 App 为 `微信 (com.tencent.xinWeChat)`：短消息句末不加句号，保留吧、呢、啦、哈等语气词。 |

每条字段：

| 字段 | 含义 |
| --- | --- |
| `spoken` | 说话内容的文字稿，用来合成语音。口头禅写成汉字，让普通话语音读出来。 |
| `expected` | 参考写法，按默认听写设置书写（自动识别语言、优先数字、轻度整理、完整标点）。只用于对照阅读，不决定通过与否。 |
| `category` | 上表中的类别。 |
| `targetApp` | 可选，作为听写的目标 App 传入；只有 `chatTone` 有。 |
| `mustContain` | 必须保留的短语。 |
| `mustNotContain` | 必须去掉的短语，每一个都出现在 `spoken` 里。 |
| `listItems` | 可选，编号列表项数（`1.`、`1、`、`1)`、`(1)` 开头的行）；`0` 表示必须是一段话，不能有列表标记或换行。 |
| `maxLengthRatio` | 可选，输出的字母、汉字和数字个数最多是 `expected` 的多少倍。 |
| `noTrailingPeriod` | 可选，句末不能是 `。` 或 `.`；问号、感叹号和省略号不算。 |

短语匹配规则：含汉字的短语去掉空白和标点、忽略大小写后按子串匹配，所以 `11点` 能匹配 `11 点`；纯英文短语按整词匹配，所以 `um` 不会匹配 `summary`。

此外每条都按行（去掉列表标记后）检查中英混说评测的 `spacing` 与 `punctuation` 两条格式规则。`casing` 与 `translation` 要求英文词与 `expected` 完全对应，本评测允许改写措辞，所以不检查。

普通 `swift test` 会运行 `DictationPolishRuleTests`：检查字段与各类条数，`spoken` 不重复且只有一行，`expected` 能通过自己的检查，`mustNotContain` 都在 `spoken` 里，要求整理或排列表的样本原样照抄 `spoken` 时会失败；另有计分函数的单元测试。增删样本时要同步修改测试里的条数。

Prompt 里的示例句不能取自评测集，否则测到的是记忆而不是规则：示例要换领域、换句式，`DictationPromptTests` 会检查示例句与两套评测集的 `spoken`、`expected` 互不包含（只能发现照抄，句式雷同要靠改 Prompt 时自查）。

## 怎么跑

```bash
mkdir -p Build
Scripts/eval-dictation.sh dictation-polish 2>&1 | tee Build/eval-polish-before.txt
```

音频缓存在 `Build/eval-audio-polish/NN.wav`，与中英混说评测的 `Build/eval-audio` 分开，规则相同：句子没变就复用，换了语音全部重新合成。之后运行 `SAYKUKU_LIVE_QWEN_TEST=1 swift test --filter DictationPolishEvalTests`：逐条调用批处理 `transcribeAudio`（`chatTone` 传入 `targetApp`，其余用默认设置；都不带光标附近的文字），再经过 `SpeechDisfluencyCleaner.dictation` 整理，最后和 App 一样走一遍听写二次整理（`DictationRefinement.refine`，带同样的 `targetApp`）。设 `SAYKUKU_EVAL_TWO_PASS=0` 可跳过二次整理，作为单步对照。

## 怎么读结果

逐条输出，换行写成 `\n`，方便前后两次逐行 diff：

```text
[18] selfCorrection FAIL (mustNotContain: Friday, scratch that)
  spoken:   The deadline is Friday, scratch that, Monday next week
  expected: The deadline is Monday next week.
  pass 1:   The deadline is Friday... scratch that, Monday next week.  (kept: timeout)
  actual:   The deadline is Friday... scratch that, Monday next week.
```
`pass 1` 是二次整理前的结果；二次整理没被采用时后面注明原因，如上例的 `(kept: timeout)`，这时 `actual` 就是第一步结果。关闭二次整理时它与 `actual` 相同。

`FAIL (…)` 里列出每项失败的检查及涉及的短语；`ERROR (…)` 表示请求失败，出现任何 `ERROR` 测试都会失败，这一次的结果不能拿来对比。

最后是汇总：

```text
Polish eval: 49/58 passed (84.5%), 0 errors; fillers 10/11, selfCorrection 14/19, list 8/10, noExpansion 10/10, chatTone 7/8
Check failures: mustContain 4, mustNotContain 4, list 2, length 0, trailingPeriod 1, spacing 1, punctuation 0
Exact matches: 41/58
Refinement: changed 19/58, kept the first pass 3 (timeout 3); p50 745 / p90 1484 / max 2013 ms
```

`Refinement` 一行统计二次整理改动了几条、几条因超时、出错或兜底检查保留了第一步结果，以及这一步的耗时。

对比方法与中英混说评测的「前后对比」一节相同：同一份音频、改 Prompt 前后各跑一次，按类别看变化，差一两条不足以下结论。

## 长段真实语音第一轮探索（2026-10-25，已由后续 Realtime 复验替代）

使用本机 `Typeless-Longform-Dataset-2026-10-24-cleaned-20261024-225733-805646`，不把私有音频、参考稿或识别结果复制进仓库。757 条听写参考中，738 条含段间空行、329 条含编号列表；参考是编辑后的成稿，不是逐字金标，不能把相似度或分段数量当作质量通过率。

在同一组 11 条既有 Realtime 识别文本上，分别回放旧版二次整理、新版关闭结构化、新版开启结构化。模型均为 `qwen3.8-flash`，自动识别语言、优先数字、保留结尾标点，不带 App、光标或记忆。每组一次，网络耗时有波动。

| 二次整理 | 含段间空行 | 中位耗时 | 最大耗时 | 结构/长度/英文检查回退 |
| --- | --- | --- | --- | --- |
| 旧版 | 1/11 | 2.31 秒 | 9.67 秒 | 0/11 |
| 新版，关闭结构化 | 1/11 | 1.82 秒 | 2.78 秒 | 0/11 |
| 新版，开启结构化（最终复验） | 6/11 | 3.74 秒 | 5.43 秒 | 1/11 |

文本回放为了完整测量回复，没有施加生产等待时限。旧版固定 2 秒会有 6/11 超时；新版按长度计算的 2～10 秒预算在最终复验中没有超时；有一条因清理正文与排版正文不一致触发保真回退，表中已按首轮结果计算。改口样本已合并被撤回的“第二步”为“第三步”，同时保留后面让对方评估第二步还是第三步的问题。仍有多条长段没有明显分段，不声称全部达到参考稿的组织程度。上一轮同架构回放为 9/11 含分段，最终细化枚举规则后为 6/11，说明小样本结构效果仍存在明显波动。

独立取 `splits/holdout.json` 前四条原始 OGG，临时解码为 16 kHz 单声道 PCM16 WAV，通过当前批量识别及实际二次整理流程分别开启/关闭结构化，共 8 次音频识别、8 次文本整理。开启组有两条形成明确的两项列表，一条叙述保持普通正文，一条因清理文本和排版文本不一致而触发保真回退；关闭组四条均保持普通正文。没有请求错误。首轮专名误识别仍可见，不能用参考成稿替换来掩盖识别问题。此处验证的是批量路径，未重跑这四条的 Realtime WebSocket 音频。

优化由同一次文本请求返回 `cleaned` 与 `paragraphs`，先清口误、再排版；本地校验两份正文的字符顺序一致后才接受，不新增请求次数。正文较长时收紧长度下限为 0.8，避免接受大段摘要；短句仍允许真实改口带来的较大压缩。它提高了长段阅读性，也增加了输出 token 和等待时间，关闭结构化可保留单字段的纯文本整理。

回放入口：

```bash
SAYKUKU_LIVE_QWEN_TEST=1 \
SAYKUKU_LONGFORM_EVAL=1 \
SAYKUKU_LONGFORM_DATASET=/path/to/cleaned-dataset \
SAYKUKU_LONGFORM_ARMS=structured,off \
SAYKUKU_LONGFORM_RESULT=my-comparison.jsonl \
swift test --filter DictationLongformEvalTests.replay
```

结果和当次 Prompt 保存在忽略提交的 `Build/longform-eval/`。`SAYKUKU_LONGFORM_SAMPLES` 可指定逗号分隔的样本 ID 前缀；若改动前使用 `SAYKUKU_LONGFORM_SNAPSHOT=1` 留下 `baseline.txt`，可在 `SAYKUKU_LONGFORM_ARMS` 加入 `baseline`。已有快照和结果不会覆盖。默认 `swift test` 不访问数据集、网络或真实 Keychain。

音频验证另用 `SAYKUKU_LONGFORM_AUDIO=1`、`SAYKUKU_LONGFORM_WAV=/path/to/decoded-wav` 和同一数据集变量，执行 `DictationLongformEvalTests.audioHoldout`；WAV 文件名须为留出集样本 ID。解码在仓库外或忽略目录进行，结束后清理本次生成的 WAV，保留原始 OGG。

在线回归补充：完整短句整理评测为 48/58（82.8%），中英混排为 35/40（87.5%），均无接口错误。失败项仍包含首轮漏词/专名误识别、数字格式、部分无提示词改口、列表和聊天句尾。随后仅细化“短消息与明确枚举”的优先级及两个响应字段的枚举标记要求，10 条列表专项复验为 4/10；严格保真检查会拒绝两份正文中的连接词、编号词或大小写差异，有效保护内容，但也会错过部分本来合理的列点。此项作为已知限制保留，不通过放松内容一致性检查换取漂亮分数。未对最终细化后的全部 98 条再次跑全量在线回归；本地测试全部复验。


## 长短语音统一复验（2026-10-25）

当前实现与完整的方案对照见 [长短语音优化复验](DICTATION_UNIFIED_EVAL_2026-10-25.md)。第一轮探索里的双字段 Flash JSON 和字符一致性检查已移除；当前结构化在音频模型的一次回复内完成；可选Flash为短句保留既有纯文本清理，长段使用较短的低档推理清稿。已移除长段80%字数及分词覆盖硬门槛。默认离线测试不访问真实数据集或模型。
