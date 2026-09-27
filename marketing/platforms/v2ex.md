# V2EX 发帖稿

发布时附官网 1.0.1 下载链接和真实 App 截图；说明海报只作配图。

**标题：** 做了个 Mac 上的语音输入和 Voice Agent：Fn 输入，Fn Fn 做下一步

做 SayKuku，是因为一个经常遇到的场景：光标已经在输入框了，却还得切到别处听写，再复制回来。

现在的交互分成两种：

1. Fn 是 Voice Input。在当前输入框说话，文字尝试写回原位置。
2. Fn Fn 是 Voice Agent。选中文字可以说“改短一点”“翻成英文”，也可以直接提问，接着上一轮对话继续。

Fn 手势用 AppKit 监听，辅助功能负责选区与写回；写回前会核对目标。不同 App 的文本控件差异很大，这块我还在实测，尤其想知道哪些输入框会丢焦点或写不进去。

当前版本需要 macOS 15+ 和自己的模型 API Key；语音走云端。历史、记忆和可选录音在本机，没有额外加密。配置与权限说明写在 https://say.anikuku.com/guide/ 和 https://say.anikuku.com/privacy/。

1.0.1 可以从 https://say.anikuku.com/download/?utm_source=v2ex&utm_medium=community&utm_campaign=launch_101 下载；官网首页的交互演示使用预设内容。想先请教大家：你最常在哪个 Mac App 里用语音输入？如果愿意帮忙测，最想先测哪种输入框？
