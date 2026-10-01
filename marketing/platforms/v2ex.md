# V2EX 发帖稿

在 V2EX 发帖时选择 **Markdown** 语法。标题填入标题栏，正文从配图开始复制。配图是官网托管的宣传图，点击图片会打开带 V2EX 来源参数的官网首页；图片加载本身不计为官网页面浏览。

## 标题

Typeless 降低额度后，我 Vibe Coding 了一个 4.8 MB 的原生 Mac 语音输入 App

## 正文

[![SayKuku 宣传图：Fn 输入，Fn Fn 唤起 Voice Agent](https://say.anikuku.com/assets/wechat-cover.png)](https://say.anikuku.com/?utm_source=v2ex&utm_medium=community&utm_campaign=launch_102&utm_content=cover)

之前一直用 Typeless。额度降低后，我试了几款替代品，都没找到适合自己输入习惯的，就 Vibe Coding 了 SayKuku。想要的操作很简单：光标在哪儿，就在哪儿说话；选中一句话，还能直接让它改短或翻译。

现在有两个入口：

1. 按 Fn 语音输入，识别结果尝试写回当前光标位置。可选按住说话或单击开关。
2. 连按两次 Fn 打开 Voice Agent，说出你的要求。不选文字也能提问、起草内容或继续对话；选中文字可改写或翻译。没有输入光标时也能提问，回答显示在卡片里。

这是用 SwiftUI 和 AppKit 做的 macOS 15+ 原生 App，1.0.2 的通用 DMG 是 4.8 MB，同时支持 Apple 芯片和 Intel Mac。Fn 手势、选区读取与跨 App 写回依赖辅助功能；写回前会核对目标。不同 App 的文本控件行为不一样，遇到不能写入或焦点跑掉的情况，欢迎告诉我 App 名称和复现步骤。

App 免费。当前用 Qwen3.8 Omni Flash 系列直接处理语音和指令，不走「先纯 ASR、再交给另一模型」的固定两段流程。需要自己配置阿里云百炼 API Key，音频会发送到所选地域，模型调用由自己的账号计费。按官方当前北京地域单价，默认实时模型的 **1 小时音频输入约 0.15 元**；输出文字、其他请求和地域差异另计，实际以账单为准。历史、记忆和可选录音留在本机，本地文件没有额外加密。源代码已在 [GitHub](https://github.com/UllrAI/SayKuku) 公开，采用 Apache-2.0 许可。

- [下载 SayKuku 1.0.2](https://say.anikuku.com/download/?utm_source=v2ex&utm_medium=community&utm_campaign=launch_102&utm_content=download)
- [配置指南](https://say.anikuku.com/guide/?utm_source=v2ex&utm_medium=community&utm_campaign=launch_102&utm_content=guide)
- [隐私与权限说明](https://say.anikuku.com/privacy/?utm_source=v2ex&utm_medium=community&utm_campaign=launch_102&utm_content=privacy)

官网首页的交互演示是预设内容，不是实时识别。最想收集两类反馈：你常用哪个 Mac App 输入？哪些输入框里 Fn 识别了，却没能正确写回？
