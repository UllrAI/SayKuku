# SayKuku

SayKuku 是一款使用 SwiftUI 与 AppKit 构建的原生 macOS 语音输入应用：

- `Fn`：Voice Input，支持轻整理口癖、原样听写和口述格式；转写后写入当前输入位置，可撤销经验证的写入。
- `Fn Fn`：Voice Agent，结合选中文字和当前应用上下文改写、翻译、生成或回答；支持修改上次写入。
- 记忆：SayKuku 记住的人名、项目、组织和术语，提高识别与处理准确度；听写后改掉的错词在浮层里点一下「记住」就收进记忆，也可以粘贴文本导入。
- History：在本机保存输入历史，失败听写可从录音重试；Voice Agent 的连续对话只在内存里保留 30 分钟。

项目要求 macOS 15+、Swift 6 和 Xcode 26 或更新，没有第三方 Swift 依赖。

## 开发

运行测试：

```bash
swift test
```

直接运行源码：

```bash
swift run SayKuku
```

需要验证权限、菜单栏、资源或其他 App Bundle 行为时，应生成签名开发包：

```bash
Scripts/package-app.sh debug
open Build/SayKuku.app
```

`swift run` 不具备稳定的 App Bundle 与签名身份，不能用于判断 TCC 权限或 Keychain ACL 行为；它使用开发版的 Keychain 服务和数据目录。

## 文档

- [产品与实现说明](SayKuku.md)：功能范围、交互、数据模型和当前实现状态。
- [本地打包与发布](docs/LOCAL_PACKAGING.md)：Release 构建、Developer ID 签名、发布脚本、公证、装订、最终 ZIP 和 dSYM。
- [写入兼容性实测](docs/COMPATIBILITY.md)：各应用的插入路径、校验、撤销、纠错检测结果和 Fn 到 Pill 延迟，以及真机测试步骤。
- [中英混说评测](docs/MIXED_LANGUAGE_EVAL.md)：听写 Prompt 的固定评测集、评测脚本和结果解读；改动 Prompt 后必须重跑。
- [Agent 协作约定](AGENTS.md)：代码修改、测试、Keychain、权限和发布约束。

## 隐私与权限

SayKuku 只在语音输入、语音 Agent 和麦克风测试时使用麦克风。语音输入和语音 Agent 的音频会发送到所选 Qwen 地域处理；开启“保存录音”后，录音保存在这台 Mac 上；麦克风测试只检测音量，不保存也不上传。辅助功能权限用于识别 Fn 手势和取消键、向其他 App 的当前输入位置写入文字，以及在使用语音 Agent 时读取选中文字；开启“浏览器页面”后，也用它读取 Safari 或 Chrome 当前页面的网址（每次辅助功能调用最多等 0.4 秒），不需要“自动化”权限。“屏幕上的文字”开启时（默认开启），语音 Agent 还会读取当前窗口里能看到的文字（最多 2000 字，不含密码框和密码管理器），只随这一次请求发送，不写入历史、不保存到磁盘，也不进日志；语音输入不读取。App 不会记录你的按键，也不申请输入监控权限。

Qwen API Key 保存在这台 Mac 的钥匙串中；输入历史、记忆、纠正建议和可选录音以 JSON 与 WAV 文件保存在本机，不额外加密；Voice Agent 的最近对话只在内存里，退出即清除。不想留下输入历史时，可在“设置 → 历史”中选择“不保存”，此后不再记录新的历史和录音。焦点在密码输入框（含系统安全输入状态）或已知密码管理器（1Password、Bitwarden、LastPass、Dashlane、KeePassXC、钥匙串访问、“密码”）中时，SayKuku 不会开始录音，也不读取或写入内容。无痕浏览窗口不会被单独识别，与普通窗口同样处理。

正式版启动后和之后每 24 小时，会向 `saykuku.ullrai.com` 请求一次版本号文件，请求不含任何个人数据；可在“设置 → 通用”中关闭“自动检查更新”。开发版不检查更新。

## 发布

正式包固定使用 Bundle ID `com.saykuku.app`，必须由稳定的 Developer ID Application 身份签名并完成 Apple 公证。不要分发 ad-hoc 签名或仅签名但未公证的构建。正式发布运行 `Scripts/release.sh`，它依次完成测试、构建签名、公证、装订、最终 ZIP 和 dSYM；前置条件和排查步骤见 [本地打包与发布](docs/LOCAL_PACKAGING.md)。

App 不在内部下载或安装更新：正式版读取 `https://saykuku.ullrai.com/ver.json`，发现更新的版本号时弹窗，引导用户到 GitHub Release 下载。发布脚本最后会生成 `Dist/ver.json`，发布 GitHub Release 后把它上传到该地址。

## License

仓库当前未提供 `LICENSE` 文件。在明确授权前，不应假定代码可按开源许可证复制、再分发或用于衍生项目。
