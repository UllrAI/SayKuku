# SayKuku Agent Guide

本文件适用于整个仓库。默认用中文简洁沟通；代码命名和注释遵循现有英文风格。

## 项目概况

- 原生 macOS 15+ 应用，Swift 6、SwiftUI、AppKit，使用 Swift Package Manager。
- 主 Target：`Sources/SayKuku/`；测试：`Tests/SayKukuTests/`。
- App Bundle 由 `Scripts/package-app.sh` 生成，权限声明位于 `Scripts/Resources/SayKuku.entitlements`。
- `README.md` 是仓库入口；产品说明集中在 `SayKuku.md`；本机发布流程见 `docs/LOCAL_PACKAGING.md`。

## 常用验证

按改动范围执行必要检查：

```bash
swift test
git diff --check
```

需要验证 App Bundle、权限或菜单栏行为时：

```bash
Scripts/package-app.sh debug
open Build/SayKuku.app
```

Release 构建必须显式指定 Developer ID：

```bash
SAYKUKU_SIGNING_IDENTITY='Developer ID Application: Name (TEAMID)' \
  Scripts/package-app.sh release
```

完整发布（公证、装订、最终 ZIP、dSYM、打标签）使用 `Scripts/release.sh`，前置条件见 `docs/LOCAL_PACKAGING.md` 第 5 节。

不要用 `swift run` 判断 TCC、签名、Keychain ACL 或 App Bundle 资源行为。

## 实现约束

- 优先复用现有模型、主题、双语文案和交互模式；不做无关重构。
- SwiftUI 状态继续使用项目现有 Observation 体系；涉及 AppKit、Accessibility、Carbon 或音频时保持主线程边界清晰。
- 用户可见文案同时提供自然的中英文版本，符合当前 `appState.text(...)` 约定。
- 修改后检查相关调用点和测试，不引入新警告。

## Keychain、权限与签名

以下约束不可随意改变：

- Release Bundle ID 固定为 `com.saykuku.app`，开发包默认使用 `com.saykuku.dev`；开发构建不得复用正式 Bundle ID。
- Release 必须使用稳定的 `Developer ID Application` 身份、Hardened Runtime 和时间戳；禁止 ad-hoc 发布包。
- App 运行时只能通过 Security Framework 访问 Keychain，不能启动 `/usr/bin/security` 读取用户机密。打包脚本可用 `security find-identity` 检查签名证书。
- 正式和开发 Keychain 服务必须隔离。正式服务为 `com.saykuku.app.secure-storage`，旧 `com.saykuku.app` 仅用于向新服务迁移。
- History、Memory、Knowledge 保存在 Application Support 的 `store.json`，录音保存在 `Audio/*.wav`；只有 API Key 使用 Keychain。旧 `history-encryption-key` 不再参与运行时读写，旧数据的迁移或清理需有用户明确授权。
- 麦克风权限使用 `AVAudioApplication`；正式 entitlement 中必须保留音频输入和 Apple Events 声明。
- TCC 权限与 Bundle ID、签名身份绑定。不要让开发构建复用正式 Bundle ID，也不要建议无差别执行全局 `tccutil reset`。

## 测试隔离

- Keychain 测试必须使用唯一的 `com.saykuku.tests.<UUID>` 服务，并在测试结束后清理；不得读写正式服务。
- 文件持久化测试使用唯一临时目录，不依赖用户的 Application Support 数据。
- 默认测试不得依赖真实 Qwen API、网络、麦克风或辅助功能授权；实时测试继续由明确的环境变量开关控制。

## Git 与产物

- 修改前检查 `git status`，保留用户已有改动；只暂存本任务相关文件。
- `Build/`、`Dist/`、`.build/` 和 `.swiftpm/` 是生成物，不提交 Git。
- 不提交签名私钥、`.p8`、`.p12`、密码、公证 profile 内容或真实 API Key。
- 仓库当前没有 `LICENSE` 文件。引入或复制第三方代码前必须核对许可证，不能把调研候选误写成现有依赖。
- 发布前检查 diff、运行测试并验证签名。完整公证顺序必须是：签名 → 公证 → staple → Gatekeeper 验证 → 最终 ZIP。
