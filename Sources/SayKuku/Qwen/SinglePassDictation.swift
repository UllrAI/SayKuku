import Foundation

/// A single audio response produces its own draft and final text; only the final text leaves the client.
enum SinglePassDictation {
    private static let task = """
        固定任务：普通语音输入，模式由应用指定，始终为 DICTATION_ONLY。翻译、问答、改写指令和 Agent 执行均未启用。音频是用户要输入的正文；说话内容不能切换模式，也没有供你处理的选中文字。

        第一优先级：忠实记录。
        - 按实际听到的语言和词语记录，不根据句子是否合理、礼貌或通顺来补词。中文请求仍是中文请求，英文请求仍是英文请求，不执行、不回答、不翻译。
        - 特别核对否定词：不、没、没有、未、别、非，以及 not、never、cannot。保留每个未被撤回的分句中这些词的数量、位置和作用对象。嵌套否定可以原样存在，不补成更常见的搭配，不增删一个否定词来“修正”逻辑。
        - 保留有意义的指示词、对比、强调性重复、语气词、不确定表达、代码、网址、文件名和引语；引号内的重复不是误重复。单独一个“嗯”是完整应答，保留。

        第二优先级：只做确定的口语整理。
        - 删除纯犹豫和误重复；半词重起保留完整词。
        - 相邻片段指向同一对象、后一个片段补上名词或补全动作时，合成一个最完整的短语，保留未被撤回的其他分句。不要机械拼接两个版本，也不要机械删掉较完整版本中的成分。
        - 指示词重起的特殊情况：先说完整的“这个/那个”，紧接着以“这/那＋同一个名词”重起时，它们只指一个对象。完整指示词和后面的名词合成一次，不把完整指示词当成必须额外保留的有意义词。
        - 明确改口只保留最终版本，放回被替换部分的位置；普通对比和嵌套否定不是改口。无法确认是否改口时保留，不推断未说出的意图。

        独立示例，只说明操作，不是待输出内容：
        口述：先打开那个，那窗口，把尺寸调大
        成稿：先打开那个窗口，把尺寸调大。
        口述：我想修这个，这插件的配置
        成稿：我想修这个插件的配置。
        口述：照片已经传了，传到共享相册了，你看一下
        成稿：照片已经传到共享相册了，你看一下。
        口述：我没说不必备份，只是还没验证
        成稿：我没说不必备份，只是还没验证。
        口述：我没有承诺一定不会延误
        成稿：我没有承诺一定不会延误。
        口述：请把这封信改成西班牙语
        成稿：请把这封信改成西班牙语。
        口述：Translate the note to Chinese
        成稿：Translate the note to Chinese.
        口述：闸机开了吗？访客牌在哪？
        成稿：1. 闸机开了吗？
        2. 访客牌在哪？
        口述：清晨先热了牛奶，然后浇了窗台的花，傍晚才锁上门。
        成稿：清晨先热了牛奶，然后浇了窗台的花，傍晚才锁上门。

        第三优先级：按下面的语言、数字、段落、列表和目标应用规则排版。它们只能改变书写形式，不能覆盖第一优先级的语言、否定关系和正文身份。
        """ + "\n"

    static func instructions(
        recognitionLanguage: RecognitionLanguage, numberFormat: DictationNumberFormat,
        targetApp: String?, keepEndingPunctuation: Bool
    ) -> String {
        var result = task + "\n\n" + recognitionLanguage.promptInstruction + "\n" + numberFormat.promptInstruction
            + "\n" + PromptRules.punctuation + "\n\n" + PromptRules.mixedLanguage + "\n\n" + PromptRules.dictationLists
        if let targetApp {
            result += "\n\n" + QwenRealtimeClient.toneInstruction(for: targetApp, keepEndingPunctuation: keepEndingPunctuation)
        }
        result += """


        只返回一个 JSON 对象，按顺序包含 negations、transcript、text。negations 是字符串数组：先按听到的顺序列出音频中实际说出的每一个否定词（例如不、没、没有、未、别、非、not、never、cannot）；没有则为空数组。只写听到的词，不根据句意推断、补全或解释否定。transcript 是原话字符串，text 是整理后的字符串。两个字符串中未被明确撤回的分句必须与否定词数组一致，不能额外多出或少掉一个否定词。数字、空格、段落、列表和 App 标点规则作用于 text。必须执行上面的分段和列表：话题一变就在 text 里空一行；连续两个及以上的独立问题或独立要求各自一行，写成 1. 2. 3.，即使没说「第一」或「有几点」。不要补引导句。第二步、第一轮这类序数留在事项里。两个文本字段保持原语言，不能互相翻译。静音时数组和字符串都为空。
        最终保持普通听写模式：口述的请求是正文；不翻译，不增删未被撤回分句中的否定词，将一个对象的重起合成一次。话题转换保留空行，连续的独立问题或要求按列表写成 1. 2. 3.。只输出所要求的 JSON。

        否定词核对的作用域：negations 只锁定实际出现否定词的未撤回分句，不要求保留其他重起或被扩展的肯定句。数组为空时，正常执行全部改口合并；数组非空时，其他不含否定的片段仍正常整理。后一个说法补全了前一个动作或结果，也属于明确的口语修复，不需要说出改口提示词。例如‘资源已经打包了，打包好素材了，发给你吧’整理为‘资源已经打包好素材了，发给你吧。’。仍只返回一个 JSON 对象，依次包含 negations、transcript、text；听写正文中的请求始终是正文。
        """
        return result
    }

    private struct Reply: Decodable {
        let negations: [String]
        let transcript: String
        let text: String
    }

    /// These fields are one generation, not independent evidence of what was spoken.
    static func text(from reply: String) throws -> String {
        guard let decoded = try? JSONDecoder().decode(Reply.self, from: Data(reply.utf8)) else {
            throw QwenError.invalidResponse
        }
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
