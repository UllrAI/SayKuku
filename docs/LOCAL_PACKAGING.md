# SayKuku 本地打包与发布

本文记录 SayKuku macOS App 的本地构建、Developer ID 签名、公证、装订、验证、DMG 制作、Sparkle 更新源和官网的自动发布流程。App 最低运行版本为 macOS 14；构建与发布仍需在支持 Xcode 26 或更新版本的 macOS 上、仓库根目录执行。

发布链路如下：

```text
测试 → Release 构建 → Developer ID 签名 → 生成公证 ZIP
    → App 公证 → Staple 票据 → Gatekeeper 验证
    → 用装订后的 App 制作 DMG → DMG 签名 → DMG 公证 → Staple → Gatekeeper 验证
    → 签名 appcast、生成统一元数据 → 上传并公开校验 DMG
    → 部署官网 → 发布 appcast 与旧 ver.json → 公开回读校验 → 提交官网、推送标签
```

公证 ZIP 只用于上传 Apple；用户下载的是 DMG，它必须用已经装订票据的 `.app` 制作。

## 快速命令

日常开发直接运行源码：

```bash
swift run SayKuku
```

打包只有两个对外入口。正式发布运行以下命令，得到已公证、装订的 App 和 DMG（前置条件见第 1 节，流程见第 5 节）：

```bash
Scripts/release.sh --notes /absolute/path/release-notes.txt
```

需要测试权限、菜单栏和独立开发版 App 时，只生成开发包：

```bash
Scripts/package-app.sh debug
open Build/SayKuku.app
```

开发包的文件路径仍是 `Build/SayKuku.app`，Finder 显示名称为 `SayKuku Dev`。开发版默认使用 `com.saykuku.dev`；正式版固定使用 `com.saykuku.app`，不能混用。日常开发不要覆盖 Bundle ID；给开发构建指定 `com.saykuku.app` 时脚本会直接报错退出。

两条命令都会把本次 App 放在 `Build/SayKuku.app`；正式发布还会在 `Dist/` 留下 `SayKuku-<版本>.dmg`、同版本 App / Sparkle dSYM，以及 `releases/<版本>/` 内的元数据、appcast 和旧版本文件。成功后会清理图标编译目录、临时签名权限文件、DMG 工作目录、公证上传 ZIP 和公证结果 JSON；失败时保留公证结果供排查。`.build/` 是 SwiftPM 编译缓存，不随打包清理。

## 1. 一次性准备

本机需要：

- Xcode 26 或更新及 Command Line Tools。
- 钥匙串中带私钥的 `Developer ID Application` 证书。
- App Store Connect API Key，或 Apple ID 的 App 专用密码。

确认工具链和签名身份：

```bash
xcode-select -p
swift --version
xcrun notarytool --version
security find-identity -v -p codesigning
```

`security find-identity` 必须能看到类似：

```text
Developer ID Application: Your Name (TEAMID)
```

只有证书、没有对应私钥时不能签名。可以在“钥匙串访问”中展开证书，确认下面存在私钥。

### 配置公证凭据

推荐把公证凭据保存为本机钥匙串 profile，之后的发布命令不再直接接触凭据。使用 App Store Connect Team API Key 时执行：

```bash
xcrun notarytool store-credentials 'SayKuku-Notary' \
  --key '/secure/path/AuthKey_KEYID.p8' \
  --key-id 'KEYID' \
  --issuer 'ISSUER-UUID'
```

Individual API Key 不需要 `--issuer`。也可以使用 Apple ID；不要把 App 专用密码直接写在命令行中，让 `notarytool` 交互式询问：

```bash
xcrun notarytool store-credentials 'SayKuku-Notary' \
  --apple-id 'developer@example.com' \
  --team-id 'TEAMID'
```

命令默认会在线验证凭据，成功后可再次检查：

```bash
xcrun notarytool history --keychain-profile 'SayKuku-Notary'
```

保存并验证 `SayKuku-Notary` 后，后续提交、查询历史和下载公证日志都使用这个 profile，不需要再把 `.p8` 路径写进命令：

```bash
xcrun notarytool submit Dist/SayKuku-1.0.0-notarization.zip \
  --keychain-profile 'SayKuku-Notary' \
  --wait
```

不要把 `.p8`、`.p12`、私钥密码、Apple ID App 专用密码或 API Key 提交到仓库。

## 2. 每次打包前检查

确认工具链和工作区状态：

```bash
xcode-select -p
swift --version
git status --short
```

确认当前提交就是要发布的版本，并先处理所有意外的未提交修改。`Build/` 和 `Dist/` 是忽略的本地产物，不应提交。

正式发布前检查并按需更新版本号：

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  Scripts/Resources/Info.plist
```

- `CFBundleShortVersionString`：用户看到的版本，例如 `1.0.0`。发布者只需要维护这一项。
- `CFBundleVersion`：构建号，由 `Scripts/package-app.sh` 打包时写入，取值为当前提交的提交数（`git rev-list --count HEAD`）。它随主分支单调递增，同一提交重复打包得到同一个号。仓库里的 `Info.plist` 固定写 `0`，不用手动修改。要在完整（非 shallow）的 Git 仓库里打包，浅克隆会被脚本拒绝。

Sparkle 用 `CFBundleVersion` 比较版本；旧客户端仍比较 `CFBundleShortVersionString`。每次正式发布都必须提高显示版本，构建号也必须严格大于线上版本；脚本在构建前检查两者。历史 `ver.json` 没有构建号时，脚本读取已公证的公开旧 DMG 获取实际构建号。

版本号属于源代码。需要变更时应先修改、测试并提交，再生成发布包。提交前检查 `git diff` 和 `git diff --check`，只暂存本次 App 代码、测试、版本号与相关技术文档。官网页面和宣发素材按当次发布要求决定是否提交；即使暂不提交，也要更新并部署实际要交付的页面。

先运行测试：

```bash
swift test
```

正式版必须使用 Developer ID Application 证书。再次确认本机可用签名身份：

```bash
security find-identity -v -p codesigning
```

## 3. 本地开发版

开发版使用独立的 Bundle ID `com.saykuku.dev`，显示名称为 `SayKuku Dev`。这样开发版与正式版的 macOS TCC 权限记录不会互相污染。

```bash
Scripts/package-app.sh debug
open Build/SayKuku.app
```

脚本会优先选名称里带当前用户名的 Apple Development 证书，否则取第一个。需要指定别的证书时：

```bash
SAYKUKU_SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' \
  Scripts/package-app.sh debug
```

验证开发版身份：

```bash
plutil -p Build/SayKuku.app/Contents/Info.plist | \
  rg 'CFBundleIdentifier|CFBundleDisplayName'
codesign -dvvv Build/SayKuku.app 2>&1 | \
  rg 'Identifier|Authority|TeamIdentifier|flags'
```

开发版应显示：

```text
CFBundleIdentifier = com.saykuku.dev
CFBundleDisplayName = SayKuku Dev
```

开发版同样启用 Hardened Runtime，`flags` 中应包含 `runtime`。这样 entitlement 缺失之类的问题在开发阶段就会暴露，不必等到正式包。脚本会为开发版临时加入 `com.apple.security.get-task-allow`，以便 lldb 和 Instruments 附加调试，签名成功后清理临时 entitlement；正式版不能带这项 entitlement，否则公证会失败。开发版只构建本机架构。

## 4. 正式版 App 构建与签名（发布脚本内部步骤）

正式版固定使用 Bundle ID `com.saykuku.app`，不能改成开发 Bundle ID。稳定的 Bundle ID 加稳定的 Developer ID 签名身份，才能让 macOS 在更新后正确识别原有权限记录。

`Scripts/release.sh` 会调用 `Scripts/package-app.sh release` 生成尚未公证的正式版 App；这只是内部构建步骤，不是可分发的发布产物。

签名身份由 `Scripts/signing-identity.sh` 选定，并在编译前检查，证书有问题几秒内就会报错：

- 钥匙串里恰好有一个带私钥的 `Developer ID Application` 身份时，直接使用它。
- 一个都没有时报错退出；有多个时列出全部并退出，这时用环境变量指定其中一个：

  ```bash
  export SAYKUKU_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
  ```

- 指定的身份不是 `Developer ID Application`，或钥匙串里找不到时，同样报错退出。

如果证书位于非默认钥匙串，可额外指定完整路径（自动选择也只在这个钥匙串里找），随后运行 `Scripts/release.sh`：

```bash
export SAYKUKU_KEYCHAIN='/path/to/signing.keychain-db'
```

脚本会：

1. 以 release 配置同时编译 `arm64` 和 `x86_64`，生成通用二进制。
2. 用 `dsymutil` 从编译产物提取调试符号到 `Dist/SayKuku-<版本>.dSYM`，再把二进制复制进 App 并执行 `strip -S`；随后用 `lipo -archs` 确认两个架构都在，并用 `dwarfdump --uuid` 确认 dSYM 与 App 二进制每个架构的 UUID 一致。
3. 生成 `Build/SayKuku.app`，资源包放在 `Contents/Resources/SayKuku_SayKuku.bundle`。
4. 写入正式 Bundle ID 和资源（App 图标见本节末尾），并把 `Scripts/Resources/Licenses` 中的第三方许可证复制到 `Contents/Resources/Licenses`。
   目前只有 `Lucide.txt`（App 图标、菜单栏图标和 `SayKuku.svg` 用到的 Lucide Bird 路径，ISC 许可证，原文取自 [lucide-icons/lucide 的 LICENSE](https://github.com/lucide-icons/lucide/blob/main/LICENSE)）。新增第三方代码或素材时，把许可证原文放进这个目录。
5. 用 `Scripts/Resources/SayKuku.entitlements` 签名 App。
6. 使用 Developer ID 签名身份、Hardened Runtime 和时间戳，并执行严格签名验证。

开发版走同样的签名流程，只是换成 Apple Development 身份且不加时间戳。开发版和 `swift run` 不检查更新，也不显示“检查更新…”。

脚本到此为止，只生成已签名的 `Build/SayKuku.app` 和 dSYM；它不会提交 Apple 公证、装订票据或生成 DMG。正式发布请直接运行第 5 节的 `Scripts/release.sh`，它会先调用本脚本。

同版本的 dSYM 会被本脚本直接覆盖；`Scripts/release.sh` 会先把旧 dSYM 加时间戳备份。

正式 entitlement 至少要包含：

- `com.apple.security.device.audio-input`：允许正式版向 macOS 请求麦克风权限。

检查签名和 entitlement：

```bash
codesign -dvvv Build/SayKuku.app 2>&1 | \
  rg 'Identifier|Authority|TeamIdentifier|flags'
codesign -d --entitlements - Build/SayKuku.app
codesign --verify --deep --strict --verbose=2 Build/SayKuku.app
lipo -archs Build/SayKuku.app/Contents/MacOS/SayKuku
```

`lipo` 应输出 `x86_64 arm64`。

还应确认版本和 Bundle ID：

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  Build/SayKuku.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  Build/SayKuku.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  Build/SayKuku.app/Contents/Info.plist
git rev-list --count HEAD
```

最后两条命令的输出应相同。

此时 `spctl` 显示 `Unnotarized Developer ID` 是正常的，因为公证尚未完成；不要把这个阶段的包交给用户。

### App 图标

App 带两份图标，各给不同系统用：

| 源文件 | 打进 App 的形式 | Info.plist 键 | 谁在用 |
| --- | --- | --- | --- |
| `Scripts/Resources/AppIcon.icon` | `Contents/Resources/Assets.car` | `CFBundleIconName = AppIcon` | macOS 26 及以后，显示为分层（Liquid Glass）图标 |
| `Scripts/Resources/AppIcon.icns` | `Contents/Resources/AppIcon.icns` | `CFBundleIconFile = AppIcon` | macOS 14 / 15 |

`AppIcon.icon` 是 Icon Composer 的文件包：`icon.json` 描述底色和分组，`Assets/Bird.svg` 是鸟形图层。底色用珊瑚红 `#F04A3A` 的自动渐变，鸟形沿用 `SayKuku.svg` 的 Lucide Bird 路径和 `.icns` 里的比例。要调整时在 Mac 上用 Icon Composer（Xcode › Open Developer Tool › Icon Composer）打开这个包修改并保存，文件名保持 `AppIcon`，因为它必须和 `actool --app-icon` 的名字一致。

每次打包，脚本都会先复制 `AppIcon.icns`，再用 `xcrun actool` 把 `AppIcon.icon` 编译成 `Assets.car`。部署目标写的是 26.0，这样 actool 只产出 macOS 26 用的分层图标，不会为旧系统另生成一套图标去顶替手工调好的 `.icns`；actool 顺带生成的 `AppIcon.icns` 也不会被使用。

以下情况脚本会打印一行 `warning: actool could not compile AppIcon.icon ...`，照常继续打包，只是不带 `Assets.car` 和 `CFBundleIconName`，所有系统都显示 `.icns`：

- 找不到 `actool`，或 `actool` 返回失败；
- 没有生成 `Assets.car`；
- 生成的 partial Info.plist 里没有 `CFBundleIconName = AppIcon`。

actool 的完整输出保存在 `Build/AppIcon.actool/actool.log`。删掉 `AppIcon.icon` 时脚本直接跳过这一步，不会有警告。

确认分层图标已经打进去：

```bash
ls Build/SayKuku.app/Contents/Resources/Assets.car
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' \
  Build/SayKuku.app/Contents/Info.plist
```

Dock 会缓存图标。换图标后看到的还是旧样子时，执行 `killall Dock` 刷新。

## 5. 公证、装订与 DMG

完成版本号修改、测试并提交后，在干净的 `main` 工作区运行：

```bash
Scripts/release.sh --notes /absolute/path/release-notes.txt
```

更新说明只输入一次：UTF-8 文本，每行一条，可用 `- ` 开头；会同步到 Sparkle、两个下载页和旧 `ver.json`。两种语言页面共享这份内容，发布时可在同一文件中填写中英双语；HTML 会转义，不能嵌入脚本。

本机需安装并登录 Wrangler 与 Zeabur（`wrangler whoami`、`npx zeabur@latest auth status -i=false`）。沿用已有 R2 bucket `saykuku` 和官网服务，不创建新服务。`~/.config/saykuku/deploy.env` 应为权限 `600` 的本机文件，提供 `CLOUDFLARE_ACCOUNT_ID`、`ZEABUR_PROJECT_ID`、`ZEABUR_SERVICE_ID`，可选 `ZEABUR_ENVIRONMENT_ID`；环境变量优先，不在仓库保存凭据。

Sparkle 固定为 2.10.0，保留完整 framework 和许可证；发布工具按相同版本和官方 SHA-256 下载到 `Build/`。Ed25519 发布私钥保存在登录 Keychain 的 Sparkle 条目中，account 为 `com.saykuku.app`；公钥在 Info.plist。已有钥匙不要重新生成或替换。新机器应从安全备份恢复：

```bash
Build/sparkle-tools-2.10.0/bin/generate_keys --account com.saykuku.app -p
# 需要恢复时，用 -f 指定密码管理器导出的临时密钥文件，使用后删除临时文件。
```

发布顺序：

1. 检查工作区、分支、显示版本和构建号、签名身份、公证 profile、更新签名公钥与本机私钥是否配对、部署配置和登录状态。
2. 运行 Swift 测试；备份已有同版本产物；构建通用架构 App 和 dSYM，完整嵌入 Sparkle，所有 helper 由内向外签名并验证架构。
3. App 签名 → 公证 → staple → Gatekeeper；用装订后的 App 制作 DMG → DMG 签名 → 公证 → staple → Gatekeeper。
4. 对最终不再修改的 DMG 运行 `generate_appcast --maximum-deltas 0 --maximum-versions 0`，保留历史条目且不生成增量包。生成 `Dist/releases/<版本>/release.json`、`appcast.xml` 与 `ver.json`。
5. 先通过 Wrangler 的 R2 接口检查版本化对象：同名文件相同则复用，不同则停止，只有明确不存在才上传；避免提前访问公开的不存在 URL 而触发 CDN 404 缓存。上传后公开回读大小与 SHA-256，禁止覆盖已发布版本。
6. 从同一元数据更新官网版本、链接、实际大小、SHA-256 和更新说明，部署现有 Zeabur 服务；公开校验两种语言下载页和官网 `ver.json`。
7. 上传 R2 的 `appcast.xml` 和同一份旧 `ver.json`，公开回读校验。官网及清单都只能在 DMG 公开可下载后发布。
8. 公开校验全部成功后回写本地官网和兼容旧工具的 `Dist/ver.json` 副本，提交官网变更，为实际构建提交打标签并推送 `main` 与标签；标签已存在时必须指向同一构建提交。

任何一步失败立即停止。上传、公证和部署无需重复执行：保留原产物，修复原因后从干净的 `main` 继续：

```bash
Scripts/release.sh --resume Dist/releases/1.0.10/release.json
```

更新清单生成前就会保存可恢复的 `release.json`；即使读取旧更新源或生成清单失败，也不必重新构建、公证。只恢复本地候选包可运行 `Scripts/release.sh --prepare --resume Dist/releases/1.0.10/release.json`。

恢复时重新验证产物哈希、EdDSA、代码签名、票据、公开版本与提交关系；禁止回滚已发布的新版本。已成功上传的相同 DMG 会复用。若 Git 提交或推送失败，先处理其明确报错，再恢复；不要修改签名后的 DMG 或元数据。

只在本机验证、不触碰线上服务时，可从已提交的功能分支准备候选包：

```bash
Scripts/release.sh --prepare --notes /absolute/path/release-notes.txt
```

`--prepare` 完成测试、正式签名、公证、DMG 和更新签名；不部署、上传或打标签。确认候选包后合并源码，再在 `main` 发布；合并引起代码差异时应重新构建，不能拿不对应的提交强行恢复。

长期保留 `SayKuku-<版本>.dmg`、App dSYM、Sparkle dSYM 和 `Dist/releases/<版本>/` 元数据。发布说明和哈希不再手工维护多个副本。首次带 Sparkle 的版本，旧客户端仍需从官网下载并手动安装；以后通过 `https://saykuku.ullrai.com/appcast.xml` 更新。旧 `ver.json` 继续在官网根目录和 R2 根目录提供，`url` 指向官网 `/download/`。

### 上线核对

发版前完成 `swift test`、`python3 -m unittest discover -s Scripts/tests`，确认待发布提交已合并到 `main`。本机准备过同版本候选时，先把候选 DMG、dSYM 和元数据一起移入独立归档目录，避免正式构建覆盖旧候选或误用其构建号。

正式脚本成功后核对以下公开内容，全部来自本次 `Dist/releases/<版本>/release.json`：

- R2 版本化 DMG 的版本、构建号、大小和 SHA-256，App / DMG 的签名及票据；不覆盖已发布的同名包。
- 中英文下载页、首页等当前版本展示，以及官网 `/ver.json`。
- R2 `/appcast.xml` 的构建号、显示版本、DMG URL、大小和 EdDSA 签名。
- R2 `/ver.json` 与官网 `/ver.json` 字节一致，版本、构建号、下载页 URL 和说明均正确；Sparkle 上线后不能省略这个旧客户端入口。
- Git 标签指向实际构建提交；官网同步提交已推送到 `main`。在 GitHub 创建对应版本 Release，附已验证的同一份 DMG 和更新说明，不上传私钥、本机元数据或凭据。

验证结果与人工验收边界记录在 [软件更新验证记录](SOFTWARE_UPDATE_VALIDATION.md)。发布失败时保持已验证产物不变，从 `--resume` 继续；不要先改清单来“补版本号”。

若 R2 对象已存在但公开 URL 仍返回带 `Age` / `CF-Cache-Status: HIT` 的 404，应先在 Cloudflare 的域名缓存配置中自定义清除该文件的精确 URL，再公开回读并恢复发布。Wrangler 的 R2 权限不等于 `Cache Purge` 权限；使用 API 清理需具备对应域名的权限，不能为绕过缓存而覆盖安装包或提前发布清单。

### App 更新行为与隔离测试

自动检查、自动下载默认开启；用户已有的显式选择会保留。自动下载完成后，仅在普通退出（菜单“退出”或 ⌘Q）时安装，不自动重新打开；关窗、隐藏和切换应用不算退出。手动“安装并重新打开”先等待录音、模型和文本写入结束。未领取的结果先由用户确认，最终保存失败则取消退出。自动提醒不抢输入焦点；手动检查使用 Sparkle 标准 UI。开发版与 `swift run` 不构造更新器、不访问更新源。

离线验证：

```bash
swift test
python3 -m unittest discover -s Scripts/tests
```

完整安装测试显式开启，使用独立 UUID Bundle ID、临时 Ed25519 密钥、回环 HTTP 更新源、已签名公证的旧/新版测试 App 与 DMG，不读取正式用户数据和权限，也不发布正式更新源：

```bash
SAYKUKU_UPDATE_INTEGRATION=1 python3 Scripts/tests/test_updater_integration.py
```

测试日志和票据留在 `Build/updater-*/`。测试退出后删除临时私钥、独立偏好与缓存。测试需要本机 Developer ID、公证 profile 和 Finder 自动化权限；默认测试不会执行这些步骤。它验证真实 Sparkle 替换与正常退出后的下一次手动启动；正式用户的 TCC/Keychain 跨版本延续仍需在真实升级验收中确认，不能用测试包声称已覆盖。

### DMG 安装窗口

用户打开 DMG 后看到一个 660×400 的窗口：左边是 SayKuku，右边是“应用程序”文件夹的替身，中间一个珊瑚色箭头提示拖动。内部的 `Scripts/make-dmg.sh` 先把 App、指向 `/Applications` 的链接和背景图放进可写镜像，挂载后由 Finder 保存窗口布局，再转成只读 ULFO 格式。它在临时目录内完成签名、公证、装订和校验；任何一步失败都不会生成目标 DMG，成功后清理临时镜像与结果文件。开发版只生成 App，不制作 DMG。

- 第一次运行时 macOS 会询问是否允许终端控制 Finder，需要点“允许”。拒绝过的话，到“系统设置 → 隐私与安全性 → 自动化”里重新打开。
- Finder 按卷名找窗口，所以已经挂载了名为 SayKuku 的卷时脚本会直接退出，先推出它。
- 背景图是 `Scripts/Resources/DMG/background.png`（660×400）和 `background@2x.png`（1320×800），打包时用 `tiffutil` 合成一张多分辨率 TIFF。换图时两张都要换，尺寸不变；图标位置写在 `make-dmg.sh` 顶部，改背景布局时一并调整。

### 脚本出错时的手动排查步骤

以下命令与脚本执行的步骤一致，可以从失败的环节开始逐条重跑，定位问题。

从 `Info.plist` 读取版本，并制作只用于提交 Apple 的 ZIP。`COPYFILE_DISABLE=1` 和 `--norsrc` 用于避免把无关的 AppleDouble 元数据写入压缩包：

```bash
mkdir -p Dist
VERSION=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  Scripts/Resources/Info.plist)
NOTARY_ARCHIVE="Dist/SayKuku-${VERSION}-notarization.zip"
DMG="Dist/SayKuku-${VERSION}.dmg"

BACKUP_SUFFIX=$(date +%Y%m%d-%H%M%S)
for ARTIFACT in "$NOTARY_ARCHIVE" "$DMG"; do
  if [[ -e "$ARTIFACT" ]]; then
    mv "$ARTIFACT" "${ARTIFACT%.*}-backup-${BACKUP_SUFFIX}.${ARTIFACT##*.}"
  fi
done

COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent \
  Build/SayKuku.app "$NOTARY_ARCHIVE"
unzip -tq "$NOTARY_ARCHIVE"
```

使用之前保存的钥匙串 profile 提交并等待结果：

```bash
xcrun notarytool submit "$NOTARY_ARCHIVE" \
  --keychain-profile 'SayKuku-Notary' \
  --wait \
  --timeout 30m
```

必须看到 `status: Accepted` 才能继续。记录输出中的 submission `id`；如果状态为 `Invalid`，先下载日志定位原因：

```bash
xcrun notarytool log 'SUBMISSION-UUID' \
  --keychain-profile 'SayKuku-Notary'
```

状态为 `Accepted` 后，把票据装订到 App，并验证：

```bash
xcrun stapler staple Build/SayKuku.app
xcrun stapler validate Build/SayKuku.app
spctl --assess --type execute --verbose=4 Build/SayKuku.app
```

用装订后的 App 完成 DMG 制作与公证；正常发布请直接运行 `Scripts/release.sh`，这里仅用于从中断点排查：

```bash
Scripts/make-dmg.sh Build/SayKuku.app "$DMG"
shasum -a 256 "$DMG"
```

有多个 Developer ID 身份时，先按第 4 节设置 `SAYKUKU_SIGNING_IDENTITY`。App 和 DMG 的 `spctl` 验证都应输出：

```text
accepted
source=Notarized Developer ID
```

确认 dSYM 与 App 中的二进制对应（打包脚本已自动核对，这里用于手动复查）：两条命令输出的每个架构 UUID 必须一致。

```bash
dwarfdump --uuid Build/SayKuku.app/Contents/MacOS/SayKuku
dwarfdump --uuid "Dist/SayKuku-${VERSION}.dSYM"
```

终端变量只对当前 shell 有效；打开新终端后需重新设置 `VERSION`、`NOTARY_ARCHIVE` 和 `DMG`。

## 6. 安装本机正式版

安装前退出旧版本。不要直接把新 App 合并复制到现有 Bundle；残留文件可能破坏代码签名。先把旧 App 移到带时间戳的备份路径，再复制已公证的 App：

```bash
if pgrep -x SayKuku >/dev/null; then
  osascript -e 'tell application id "com.saykuku.app" to quit'
fi

if [[ -d /Applications/SayKuku.app ]]; then
  mv /Applications/SayKuku.app \
    "$HOME/Desktop/SayKuku-backup-$(date +%Y%m%d-%H%M%S).app"
fi

ditto Build/SayKuku.app /Applications/SayKuku.app
open /Applications/SayKuku.app
```

App Bundle 不包含用户历史数据；历史位于用户的 Application Support 与 Keychain。安装后再次检查：

```bash
plutil -p /Applications/SayKuku.app/Contents/Info.plist | \
  rg 'CFBundleIdentifier|CFBundleDisplayName'
codesign -dvvv /Applications/SayKuku.app 2>&1 | \
  rg 'Identifier|Authority|TeamIdentifier|flags'
```

正式版必须是 `com.saykuku.app`，签名必须是 `Developer ID Application`。

## 7. 麦克风和辅助功能权限

开发版和正式版的权限身份不同：

| 版本 | Bundle ID | 签名 | 用途 |
| --- | --- | --- | --- |
| Dev | `com.saykuku.dev` | Apple Development | 日常开发和测试 |
| Release | `com.saykuku.app` | Developer ID Application | 分发和正式使用 |

正式版首次使用时，在 App 的权限引导中点击麦克风“开启”，接受 macOS 系统弹窗，回到 App 后状态会自动刷新。辅助功能需要在“系统设置 → 隐私与安全性 → 辅助功能”中手动打开正式版。

如果设置中完全没有 SayKuku：

1. 确认运行的是 `/Applications/SayKuku.app`，不是 `Build/SayKuku.app` 或旧副本。
2. 退出并重新打开正式版。
3. 在 App 内点击“开启”，让 App 发起首次麦克风请求。
4. 如果之前曾使用错误签名或缺少 entitlement 的正式包，可只重置正式 Bundle ID 的麦克风缓存，然后重新启动：

   ```bash
   tccutil reset Microphone com.saykuku.app
   ```

   这只影响 SayKuku 正式版的麦克风授权，不会重置其他 App 的权限。

如果状态仍异常，可查看 TCC 日志：

```bash
/usr/bin/log show --last 2m --style compact \
  --predicate 'process == "tccd" AND eventMessage CONTAINS[c] "com.saykuku.app"'
```

日志中若出现 `requires entitlement com.apple.security.device.audio-input`，说明正式包没有使用最新的 `SayKuku.entitlements`，必须重新签名并重新公证。

## 8. Keychain 与签名身份

开发版和正式版使用不同的 Keychain 服务与本地数据目录：

| 版本 | 当前 Keychain service | 数据目录 | 旧 service |
| --- | --- | --- | --- |
| Dev（含 `swift run`） | `com.saykuku.dev.secure-storage` | `~/Library/Application Support/SayKuku Dev/` | 无 |
| Release | `com.saykuku.app.secure-storage` | `~/Library/Application Support/SayKuku/` | `com.saykuku.app`，仅用于迁移 |

正式版第一次读取旧 service 中的 API Key 时，会通过 Security Framework 把它移到当前 service：写入成功后删除旧 service 中的同一条目，其他旧条目不受影响。旧条目若由命令行工具或其他签名创建，迁移时可能出现一次授权提示；迁移成功后的读取不应持续提示。正式版沿用原有数据目录；开发版使用独立目录，不会读取或复制正式版数据。

Keychain 只保存 API Key。History、纠正建议与记忆（Knowledge）以 JSON 保存在数据目录的 `store.json`，录音保存在 `Audio/*.wav`，均不额外加密。旧版本留下的 `history-encryption-key` 已不参与运行时读写，App 不会用它解密或自动迁移旧数据。旧数据的迁移或清理必须先取得用户明确授权，不要为了消除弹窗或“整理环境”擅自删除该条目或旧文件。也不要用开发包读取或修改正式 service。

## 9. 签名材料与备份

以下材料需要分开保护：

- Developer ID 签名身份：必须连同私钥导出为有强密码保护的 `.p12`，保存到密码管理器或加密离线备份。只备份 CSR 或 `.cer` 无法恢复签名能力。
- App Store Connect `.p8` 私钥：通常只能下载一次，应放入密码管理器或加密离线备份；不放 Git，也不以明文放进共享网盘。
- Key ID、Issuer ID、Team ID：不是私钥，但应和 `.p8` 的备份说明一起保存。
- Sparkle Ed25519 私钥：与 Developer ID 不同；account 为 `com.saykuku.app`。通过 `generate_keys --account com.saykuku.app -x /安全临时目录/key` 导出到权限受限的临时文件，立即存入密码管理器或加密离线备份并删除临时文件；不得进入仓库、构建日志或 R2。迁移机器后先核对 `-p` 输出与 Info.plist 公钥一致。已按持有人授权在仓库外的私有存储完成备份，并回读校验公钥一致；2026-10-25 系统已确认云盘上传完成。备份位置不写入公开仓库。Sparkle 工具默认没有启用 iCloud 同步，不能把“保存在钥匙串”当作已有云备份。
- `SayKuku-Notary` profile：保存在本机钥匙串中，不需要也不应导出到仓库。

私钥丢失时先从备份用 `generate_keys --account com.saykuku.app -f` 恢复，并核对公钥。只有 Sparkle 私钥丢失、原 Developer ID 签名身份仍可用时，[官方允许通过已签名的 DMG 轮换 EdDSA 密钥](https://sparkle-project.org/documentation/#rotating-signing-keys)；我们使用的 DMG 分发和 `SUVerifyUpdateBeforeExtraction` 配置支持这一条件。不要同时更换两种签名凭据；无法延续旧客户端信任链时，提供官网手动安装路径。若首次 Sparkle 版本尚未公开发布，首发前重新生成密钥只需同步更换公钥，不影响已有旧版客户端。

当前项目的签名脚本是 `Scripts/package-app.sh`（签名身份选择在 `Scripts/signing-identity.sh`），发布脚本是 `Scripts/release.sh`，正式权限声明是 `Scripts/Resources/SayKuku.entitlements`。`Build/` 和 `Dist/` 都是本地产物，不是源代码；但已发布版本的 dSYM 需要另行长期备份。

## 10. 常见错误

### 正式版仍显示“麦克风未开启”

优先检查正式包是否包含 `com.apple.security.device.audio-input`，以及是否真的运行了 `/Applications/SayKuku.app`。重新打包只有在修复 entitlement、签名或代码后才有意义；单纯重复制作 DMG 不会自动获得权限。

### 设置里显示旧的 SayKuku，但 App 仍检测不到

macOS TCC 会把权限绑定到 Bundle ID 和代码签名身份。只在“系统设置 → 隐私与安全性”对应权限列表中移除指向旧 App 的授权项，再添加当前 `/Applications/SayKuku.app` 并重新启动。这里不应删除 Keychain 条目或 Application Support 数据。

### `codesign` 等待钥匙串授权

首次使用 Developer ID 私钥时，macOS 可能弹出钥匙串授权框。输入登录钥匙串密码并允许 `/usr/bin/codesign` 访问；不要把密码写进命令行、脚本或文档。

### 公证失败

先确认：

- 使用的是 Developer ID Application，而不是 Apple Development 或 ad-hoc。
- 开启了 Hardened Runtime。
- App 内所有嵌套代码都签名。
- `.p8`、Key ID、Issuer ID 匹配同一个 App Store Connect API Key。
- `xcrun notarytool` 返回的日志中没有缺失资源或无效 entitlement。

### `spctl` 显示 `Unnotarized Developer ID`

说明 App 已签名但尚未成功装订公证票据，或签名后又修改了 App。重新按顺序执行“提交公证 → 等待 Accepted → staple → validate”；装订后不要再修改 App 内容或重新签名。

### `notarytool` 找不到 profile

重新执行一次性 `store-credentials` 步骤，并确保提交时使用完全相同的 profile 名称：

```bash
xcrun notarytool history --keychain-profile 'SayKuku-Notary'
```

### 从 DMG 拖出的 App 没有票据

提交 Apple 的 ZIP 不会自动被改写，装订 DMG 也不会改动里面的 App。必须先对 `Build/SayKuku.app` 执行 `stapler staple`，再用它重新制作 DMG。

### DMG 窗口没有背景或图标位置不对

说明 Finder 的布局没有写进镜像。确认终端在“系统设置 → 隐私与安全性 → 自动化”里允许控制 Finder，再重新运行 `Scripts/release.sh`；脚本等不到 `.DS_Store` 时会报 `Finder did not save the window layout into the DMG`，且不会留下目标 DMG。
