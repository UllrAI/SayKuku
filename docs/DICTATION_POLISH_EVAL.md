# 听写润色评测

> 修改听写 Prompt 中与轻度整理有关的部分（口头禅、改口、列表、防扩写、目标 App 语气）时，在 Mac 上重跑本评测，并把改动前后两次的汇总贴进 PR。中英混排写法照旧由 [中英混说评测](MIXED_LANGUAGE_EVAL.md) 负责，两套都要跑。

准备工作（Xcode、开发版 Keychain 里的 Qwen API Key、普通话语音）与 [中英混说评测](MIXED_LANGUAGE_EVAL.md#怎么跑) 相同。

## 评测集

`Tests/SayKukuTests/Fixtures/dictation-polish.json` 共 58 条。与中英混说评测按原文完全一致计分不同，这里每条只检查它要测的行为，措辞或标点上的无害差别不算失败。

| 类别 | 条数 | 测什么 |
| --- | --- | --- |
| `fillers` | 11 | 去掉嗯、呃、那个、就是、然后、uh、um、you know，意外重复和起头重说；有 1 条“那个”“然后”是内容，必须保留。第 11 条（排在文件末尾，前面各条的缓存音频序号不变）来自真实试用：句中的“嗯”连同两侧逗号去掉，前后连成一句。 |
| `selfCorrection` | 19 | 中英改口提示词（不对、不是…是、我是说、算了改成、actually、I mean、scratch that、make that）只留最终说法，被放弃部分里没被推翻的信息要保留；3 条中“不对”“不是…是”“actually”是内容，不能合并。末尾 7 条是没有提示词的重说和自我修正：第 1 条来自真实试用（“这个，这客户端”“登录 Web 了，Web 端了”），其余覆盖“X 了，X Y 了”、“那个，那份”、半个词重说和英文 “we should, we need to”。 |
| `list` | 10 | 明确枚举 3 项及以上排成编号列表，每项一行，保留引子句和收尾句；2 项、连贯叙述、句内并列保持段落。 |
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

音频缓存在 `Build/eval-audio-polish/NN.wav`，与中英混说评测的 `Build/eval-audio` 分开，规则相同：句子没变就复用，换了语音全部重新合成。之后运行 `SAYKUKU_LIVE_QWEN_TEST=1 swift test --filter DictationPolishEvalTests`：逐条调用批处理 `transcribeAudio`（`chatTone` 传入 `targetApp`，其余用默认设置；都不带光标附近的文字），再经过 `SpeechDisfluencyCleaner.dictation` 整理。

## 怎么读结果

逐条输出，换行写成 `\n`，方便前后两次逐行 diff：

```text
[23] list FAIL (list: 0/3 items)
  spoken:   周末要做三件事，第一，打扫房间，第二，去超市买菜，第三，给爸妈打个电话
  expected: 周末要做 3 件事：\n1. 打扫房间\n2. 去超市买菜\n3. 给爸妈打个电话
  actual:   周末要做 3 件事：第一，打扫房间；第二，去超市买菜；第三，给爸妈打个电话。
```

`FAIL (…)` 里列出每项失败的检查及涉及的短语；`ERROR (…)` 表示请求失败，出现任何 `ERROR` 测试都会失败，这一次的结果不能拿来对比。

最后是汇总：

```text
Polish eval: 31/50 passed (62.0%), 0 errors; fillers 9/10, selfCorrection 8/12, list 3/10, noExpansion 9/10, chatTone 2/8
Check failures: mustContain 3, mustNotContain 4, list 7, length 1, trailingPeriod 5, spacing 0, punctuation 1
Exact matches: 12/50
```

对比方法与中英混说评测的「前后对比」一节相同：同一份音频、改 Prompt 前后各跑一次，按类别看变化，差一两条不足以下结论。
