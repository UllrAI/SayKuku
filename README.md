# SayKuku

SayKuku 是一款使用 SwiftUI 与 AppKit 构建的原生 macOS 语音输入应用：

- `Fn`：Voice Input，支持轻整理口癖、原样听写和口述格式；转写后写入当前输入位置，可撤销经验证的写入。
- `Fn Fn`：Voice Agent，结合选中文字和当前应用上下文改写、翻译、生成或回答；支持修改上次写入。
- Knowledge：管理人名、项目、组织和术语，提高识别与处理准确度。
- History / Memory：在本机保存历史、短期 Agent Session 和用户确认的纠错记忆；失败听写可从录音重试。

项目要求 macOS 15+、Swift 6 和完整 Xcode。当前 Swift Package 没有第三方依赖。

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
- [本地打包与发布](docs/LOCAL_PACKAGING.md)：Release 构建、Developer ID 签名、公证、装订和最终 ZIP。
- [Agent 协作约定](AGENTS.md)：代码修改、测试、Keychain、权限和发布约束。

## 隐私与权限

SayKuku 需要麦克风权限完成录音，需要辅助功能权限监听 Fn 手势并向其他 App 的当前输入位置写入文字。App 不申请输入监控权限。

Qwen API Key 保存在这台 Mac 的钥匙串中；输入历史、知识、记忆和可选录音保存在本机。

## 发布

正式包固定使用 Bundle ID `com.saykuku.app`，必须由稳定的 Developer ID Application 身份签名并完成 Apple 公证。不要分发 ad-hoc 签名或仅签名但未公证的构建；完整命令见 [本地打包与发布](docs/LOCAL_PACKAGING.md)。

## License

仓库当前未提供 `LICENSE` 文件。在明确授权前，不应假定代码可按开源许可证复制、再分发或用于衍生项目。
