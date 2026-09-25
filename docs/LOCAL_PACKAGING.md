# SayKuku 本地打包与发布

本文记录 SayKuku macOS App 的本地构建、Developer ID 签名、公证、装订、验证和 Sparkle 更新源（appcast）生成流程。默认在 macOS 15+、仓库根目录执行。

发布链路如下：

```text
测试 → Release 构建 → Developer ID 签名 → 生成公证 ZIP
    → Apple 公证 → Staple 票据 → Gatekeeper 验证 → 重新生成最终 ZIP
    → 生成并签名 appcast
```

公证前生成的 ZIP 只能用于上传 Apple；用户最终下载的 ZIP 必须从已经装订票据的 `.app` 重新生成。

## 快速命令

日常开发直接运行源码：

```bash
swift run SayKuku
```

需要测试权限、菜单栏和独立开发版 App 时，生成开发包：

```bash
Scripts/package-app.sh debug
open Build/SayKuku.app
```

开发包的文件路径仍是 `Build/SayKuku.app`，Finder 显示名称为 `SayKuku Dev`。开发版默认使用 `com.saykuku.dev`；正式版固定使用 `com.saykuku.app`，不能混用。日常开发不要覆盖 Bundle ID；给开发构建指定 `com.saykuku.app` 时脚本会直接报错退出。

## 1. 一次性准备

本机需要：

- Xcode 26 或更新及 Command Line Tools。首次 `swift build` 会解析 Sparkle 并生成 `Package.resolved`，必须提交到仓库，否则依赖版本不固定，`Scripts/release.sh` 的干净工作区检查也会失败。
- 钥匙串中带私钥的 `Developer ID Application` 证书。
- App Store Connect API Key，或 Apple ID 的 App 专用密码。
- Sparkle 发行包（从 [Sparkle Releases](https://github.com/sparkle-project/Sparkle/releases) 下载与 `Package.swift` 同一大版本的 `Sparkle-<版本>.tar.xz`），解压后把其中的 `bin/` 加入 `PATH`，发布脚本需要 `generate_appcast`。

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

### 配置 Sparkle 更新签名

App 通过 Sparkle 2 检查更新，每个更新包都要用 EdDSA 私钥签名，App 用 `Info.plist` 里的公钥验证。首次发布前在发布机上生成密钥：

```bash
generate_keys
```

私钥只保存在本机登录钥匙串中，命令会打印对应的公钥。把公钥填入 `Scripts/Resources/Info.plist` 的 `SUPublicEDKey` 并提交；`SUPublicEDKey` 为空时 `Scripts/package-app.sh release` 会直接报错退出。之后可随时查看公钥：

```bash
generate_keys -p
```

私钥绝不进仓库。换一台发布机时用 `generate_keys -x <文件>` 导出、在新机器上 `generate_keys -f <文件>` 导入，导入后立即删除导出的文件。私钥一旦丢失，已安装的用户就再也收不到更新，备份要求见第 9 节。

更新源地址是 `Info.plist` 里的 `SUFeedURL`，当前指向 `https://github.com/UllrAI/SayKuku/releases/latest/download/appcast.xml`，也就是最新一个正式 GitHub Release 中的 `appcast.xml`。换托管地址时只改这个值，并确保旧版本能访问的地址继续可用。

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
- `CFBundleVersion`：构建号，由 `Scripts/package-app.sh` 打包时写入，取值为当前提交的提交数（`git rev-list --count HEAD`）。它随主分支单调递增，同一提交重复打包得到同一个号。仓库里的 `Info.plist` 固定写 `0`，不用手动修改。Sparkle 按构建号判断是否有新版本，所以要在完整（非 shallow）的 Git 仓库里打包，浅克隆会被脚本拒绝。

版本号属于源代码。需要变更时应先修改、测试并提交，再生成发布包。

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

如果本机有多个 Apple Development 证书，可以显式指定：

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

开发版同样启用 Hardened Runtime，`flags` 中应包含 `runtime`。这样 entitlement 缺失之类的问题在开发阶段就会暴露，不必等到正式包。脚本会为开发版额外加上 `com.apple.security.get-task-allow`（写入临时文件 `Build/SayKuku.debug.entitlements`），以便 lldb 和 Instruments 附加调试；正式版不能带这项 entitlement，否则公证会失败。开发版只构建本机架构。

## 4. 正式版本地构建与签名

正式版固定使用 Bundle ID `com.saykuku.app`，不能改成开发 Bundle ID。稳定的 Bundle ID 加稳定的 Developer ID 签名身份，才能让 macOS 在更新后正确识别原有权限记录。

```bash
export SAYKUKU_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
Scripts/package-app.sh release
```

如果证书位于非默认钥匙串，可额外指定完整路径：

```bash
export SAYKUKU_KEYCHAIN='/path/to/signing.keychain-db'
Scripts/package-app.sh release
```

脚本会：

1. 以 release 配置同时编译 `arm64` 和 `x86_64`，生成通用二进制。
2. 用 `dsymutil` 从编译产物提取调试符号到 `Dist/SayKuku-<版本>.dSYM`，再把二进制复制进 App 并执行 `strip -S`；随后用 `lipo -archs` 确认两个架构都在。
3. 生成 `Build/SayKuku.app`，资源包放在 `Contents/Resources/SayKuku_SayKuku.bundle`，`Sparkle.framework` 放在 `Contents/Frameworks`（二进制带 `@executable_path/../Frameworks` rpath）。
4. 写入正式 Bundle ID 和资源（App 图标见本节末尾），并把 `Scripts/Resources/Licenses` 中的第三方许可证复制到 `Contents/Resources/Licenses`；`SUPublicEDKey` 为空时直接退出。
5. 由内向外签名：先签 `Sparkle.framework/Versions/B` 下的 `XPCServices/*.xpc`、`Autoupdate`、`Updater.app`（保留它们自带的 entitlement），再签框架，最后用 `Scripts/Resources/SayKuku.entitlements` 签 App。不用 `--deep`，否则 App 的 entitlement 会被盖到 Sparkle 的辅助程序上。
6. 全部使用同一签名身份、Hardened Runtime 和时间戳，并执行严格签名验证。

开发版走同一套嵌套签名，只是换成 Apple Development 身份且不加时间戳。开发版和 `swift run` 不启动 Sparkle，也不显示“检查更新…”，避免开发包被正式版替换。

脚本到此为止，只生成已签名的 `Build/SayKuku.app` 和 dSYM；它不会提交 Apple 公证、装订票据或生成 `Dist/` ZIP。正式发布请直接运行第 5 节的 `Scripts/release.sh`，它会先调用本脚本。

同版本的 dSYM 会被本脚本直接覆盖；`Scripts/release.sh` 会先把旧 dSYM 加时间戳备份。

正式 entitlement 至少要包含：

- `com.apple.security.device.audio-input`：允许正式版向 macOS 请求麦克风权限。

检查签名和 entitlement：

```bash
codesign -dvvv Build/SayKuku.app 2>&1 | \
  rg 'Identifier|Authority|TeamIdentifier|flags'
codesign -d --entitlements - Build/SayKuku.app
codesign --verify --deep --strict --verbose=2 Build/SayKuku.app
codesign -dvvv Build/SayKuku.app/Contents/Frameworks/Sparkle.framework 2>&1 | \
  rg 'Authority|TeamIdentifier|flags'
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
| `Scripts/Resources/AppIcon.icns` | `Contents/Resources/AppIcon.icns` | `CFBundleIconFile = AppIcon` | macOS 15 |

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

## 5. 公证、装订与最终 ZIP

完成第 2 节的版本号修改并提交后，在干净的工作区运行：

```bash
export SAYKUKU_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
Scripts/release.sh
```

`SAYKUKU_KEYCHAIN` 的用法与第 4 节相同。脚本任何一步失败都会立即退出，不重试，也不会等待输入。它按顺序执行：

1. 前置检查：`git status --porcelain` 为空、已设置 `SAYKUKU_SIGNING_IDENTITY`、`v<版本>` 标签尚不存在、`xcrun notarytool history --keychain-profile 'SayKuku-Notary'` 能正常执行、`generate_appcast` 在 `PATH` 中。
2. 运行 `swift test`。
3. 若 `Dist/` 已有同版本的 ZIP 或 dSYM，先加时间戳后缀备份。
4. 调用 `Scripts/package-app.sh release`，生成已签名的 App 和 dSYM。
5. 生成公证 ZIP 并提交 Apple；状态不是 `Accepted` 时打印 `notarytool log` 后退出。结果保存在 `Build/notarization-result.json`，其中有 submission `id`。
6. `stapler staple`、`stapler validate`；`spctl` 输出里没有 `source=Notarized Developer ID` 就退出。
7. 从装订后的 App 重新生成最终 ZIP，确认不含 AppleDouble 文件，并输出 SHA-256。
8. 清空并重建 `Dist/appcast/`，放入最终 ZIP 后运行 `generate_appcast`，用钥匙串中的 EdDSA 私钥签名，生成只含本版本的 `appcast.xml`；下载地址指向 `https://github.com/UllrAI/SayKuku/releases/download/v<版本>/`。首次读取私钥时 macOS 可能弹出钥匙串授权。
9. 给构建时的提交打 `v<版本>` 标签。脚本不会推送，确认产物无误后手动执行 `git push origin v<版本>`。

成功后 `Dist/` 中有：

| 文件 | 用途 |
| --- | --- |
| `SayKuku-<版本>.zip` | 分发给用户的最终包 |
| `SayKuku-<版本>.dSYM` | 符号化崩溃日志，必须和对应 ZIP 一起长期保存 |
| `SayKuku-<版本>-notarization.zip` | 只用于提交 Apple，不要分发 |
| `appcast/appcast.xml` | Sparkle 更新源，与最终 ZIP 一起上传到 GitHub Release |

脚本不修改 `CFBundleShortVersionString`，也不上传 GitHub Release。推送标签后手动发布：

```bash
gh release create "v${VERSION}" \
  "Dist/SayKuku-${VERSION}.zip" Dist/appcast/appcast.xml
```

不要把它标成 draft 或 prerelease：`SUFeedURL` 使用 `releases/latest/download/`，只认最新的正式 Release。发布后已安装的 App 会在下一次自动检查时提示更新，用户也可从菜单或设置 › 通用的“检查更新…”立即检查。

### 脚本出错时的手动排查步骤

以下命令与脚本执行的步骤一致，可以从失败的环节开始逐条重跑，定位问题。

从 `Info.plist` 读取版本，并制作只用于提交 Apple 的 ZIP。`COPYFILE_DISABLE=1` 和 `--norsrc` 用于避免把无关的 AppleDouble 元数据写入压缩包：

```bash
mkdir -p Dist
VERSION=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  Scripts/Resources/Info.plist)
NOTARY_ARCHIVE="Dist/SayKuku-${VERSION}-notarization.zip"
FINAL_ARCHIVE="Dist/SayKuku-${VERSION}.zip"

ARCHIVE_BACKUP_SUFFIX=$(date +%Y%m%d-%H%M%S)
for ARCHIVE in "$NOTARY_ARCHIVE" "$FINAL_ARCHIVE"; do
  if [[ -e "$ARCHIVE" ]]; then
    mv "$ARCHIVE" "${ARCHIVE%.zip}-backup-${ARCHIVE_BACKUP_SUFFIX}.zip"
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

最后从已经装订票据的 App 重新生成用户拿到的 ZIP。上面的准备命令已经为同名旧包添加时间戳后缀，避免新旧产物混淆：

```bash
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent \
  Build/SayKuku.app "$FINAL_ARCHIVE"
unzip -tq "$FINAL_ARCHIVE"
shasum -a 256 "$FINAL_ARCHIVE"
```

`spctl` 应输出：

```text
accepted
source=Notarized Developer ID
```

发布前最后检查压缩包不含 AppleDouble 文件：

```bash
if unzip -l "$FINAL_ARCHIVE" | rg -q '(^|/)\._'; then
  echo '错误：ZIP 含有 AppleDouble 元数据' >&2
  exit 1
fi
```

确认 dSYM 与 App 中的二进制对应：两条命令输出的每个架构 UUID 必须一致。

```bash
dwarfdump --uuid Build/SayKuku.app/Contents/MacOS/SayKuku
dwarfdump --uuid "Dist/SayKuku-${VERSION}.dSYM"
```

终端变量只对当前 shell 有效；打开新终端后需重新设置 `VERSION`、`NOTARY_ARCHIVE` 和 `FINAL_ARCHIVE`。

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
- `SayKuku-Notary` profile：保存在本机钥匙串中，不需要也不应导出到仓库。
- Sparkle EdDSA 私钥：由 `generate_keys` 存在本机登录钥匙串中。用 `generate_keys -x` 导出后放进密码管理器或加密离线备份，再删除导出的文件；丢失后已安装的 App 无法再验证任何更新。

当前项目的签名脚本是 `Scripts/package-app.sh`，发布脚本是 `Scripts/release.sh`，正式权限声明是 `Scripts/Resources/SayKuku.entitlements`。`Build/` 和 `Dist/` 都是本地产物，不是源代码；但已发布版本的 dSYM 需要另行长期备份。

## 10. 常见错误

### 正式版仍显示“麦克风未开启”

优先检查正式包是否包含 `com.apple.security.device.audio-input`，以及是否真的运行了 `/Applications/SayKuku.app`。重新打包只有在修复 entitlement、签名或代码后才有意义；单纯重复压 ZIP 不会自动获得权限。

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

### ZIP 已公证但解压后的 App 没有票据

提交 Apple 的 ZIP 不会自动被改写。必须对本地 `Build/SayKuku.app` 执行 `stapler staple`，然后从该 App 重新生成最终 ZIP。
