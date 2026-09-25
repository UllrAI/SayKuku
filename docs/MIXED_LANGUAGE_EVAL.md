# 中英混说评测

> 每次修改听写 Prompt（`QwenRealtimeClient.makeDictationInstructions`、`PromptRules`，或 `RecognitionLanguage`、`DictationNumberFormat`、`DictationCleanup` 的 `promptInstruction`），或者更换默认模型，都要在 Mac 上重跑本评测，并把改动前后两次的汇总贴进 PR。

写法规则见 [SayKuku.md](../SayKuku.md)「Dictation 与 Agent 必须严格分开」一节下 Fn Dictation 的「中英混合写法规则」。

## 评测集

`Tests/SayKukuTests/Fixtures/mixed-language.json` 共 40 句，每句两个字段：

- `spoken`：说话内容的文字稿，用来合成语音。
- `expected`：SayKuku 应该写出的文本。

| 类别 | 句数 |
| --- | --- |
| 术语大小写 | 6 |
| 中英空格 | 5 |
| 人名 | 5 |
| 数字与单位 | 6 |
| 英文短语 | 5 |
| 纯英文句 | 5 |
| 纯中文句（确认规则没有副作用） | 4 |
| 口语填充词（叠加轻度整理） | 4 |

`expected` 按默认听写设置书写：自动识别语言、优先数字、轻度整理、没有目标 App（使用完整标点）、没有记忆条目或领域预设。

普通 `swift test` 会检查评测集的格式：正好 40 句，只有这两个字段，`spoken` 不重复，首尾没有空白，并且每句 `expected` 本身能通过下面的规则检查。增删句子时要同步修改测试里的句数。

## 怎么跑

准备：

- macOS 15+、Xcode 26。
- Qwen API Key 存在开发版 Keychain 服务 `com.saykuku.dev.secure-storage` 中，与 `QwenRequestContractTests` 的实时测试读取同一处。用 `Scripts/package-app.sh debug` 打出的开发包在设置里保存一次即可；首次读取时 macOS 可能会询问是否允许访问钥匙串。
- 一个普通话语音。优先使用 Tingting，没有时使用本机列出的第一个 `zh_CN` 语音；都没有时，到「系统设置 > 辅助功能 > 朗读内容 > 系统语音」里添加。

运行：

```bash
mkdir -p Build
Scripts/eval-mixed-language.sh 2>&1 | tee Build/eval-before.txt
```

可选环境变量：`SAYKUKU_TEST_REGION`（`beijing` 或 `singapore`，默认 `beijing`）、`SAYKUKU_TEST_WORKSPACE_ID`（批处理识别不需要，可以不设）。

脚本做三件事：

1. 用 `say` 把每句 `spoken` 合成为 AIFF，再用 `afconvert` 转成 16 kHz 单声道 16-bit PCM WAV，与 App 录音上传的格式一致。
2. 音频缓存在 `Build/eval-audio/NN.wav`，旁边的 `NN.txt` 记着它对应的句子。句子没变就复用；换了语音会全部重新合成。
3. 运行 `SAYKUKU_LIVE_QWEN_TEST=1 swift test --filter MixedLanguageEvalTests`：逐句调用批处理 `transcribeAudio`（与 Realtime 共用同一份听写指令），再经过 App 写入前同样的 `SpeechDisfluencyCleaner.dictation` 整理。

不设 `SAYKUKU_LIVE_QWEN_TEST=1` 时，这个测试直接跳过，默认 `swift test` 不会访问网络。

## 怎么读结果

逐句输出：

```text
[07] FAIL (spacing)
  spoken:   这个 feature 下周能 ready 吗
  expected: 这个 feature 下周能 ready 吗？
  actual:   这个feature下周能ready吗？
```

- `PASS`：去掉首尾空白后与 `expected` 完全一致。
- `FAIL (…)`：括号里是违反的规则。没有括号表示规则检查都通过，但文字不一致，多半是识别错字、数字写法或标点选择不同。
- `ERROR (…)`：请求失败。出现任何 `ERROR` 测试都会失败，这一次的结果不能拿来对比。

最后是汇总：

```text
Mixed-language eval: 29/40 passed (72.5%), 0 errors
Rule failures: spacing 4, casing 3, translation 2, punctuation 3
```

规则失败数按句计，一句可以同时计入多条规则：

| 规则 | 检查什么 |
| --- | --- |
| `spacing` | 汉字与英文字母或数字直接相连，中间没有空格。 |
| `casing` | 某个英文词在 `expected` 里有，实际输出只有大小写不同的写法，例如 `Github`。 |
| `translation` | 与 `expected` 相比，英文词少了或多了：被翻译成中文、中文被翻译成英文，也可能是 TTS 发音导致的识别错误。 |
| `punctuation` | 中文标点前后有空格，英文标点紧挨汉字，或纯英文句里出现全角标点。 |

规则检查的实现与单元测试在 `Tests/SayKukuTests/MixedLanguageRules.swift` 和 `MixedLanguageEvalTests.swift`。

## 前后对比

- TTS 的发音不如真人自然，绝对通过率会偏低，不代表真实使用效果。只看同一套音频上改动前后的变化。
- 改 Prompt 前跑一次，改完再跑一次，两次使用同一份 `Build/eval-audio`；中途不要换语音或改句子。
- 模型输出有少量随机性，个别句子可能在两次之间来回变化。差一两句不足以下结论，必要时前后各多跑一次。
- PR 正文附上前后两次的汇总行。
- 修改评测集会让旧结果失去基准：先单独提交评测集的改动，跑出新的基线，再改 Prompt。
