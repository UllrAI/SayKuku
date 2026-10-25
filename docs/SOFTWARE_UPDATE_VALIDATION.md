# 软件更新验证记录

验证日期：2026-10-25。对应 #169，固定 Sparkle 2.10.0；[1.0.10 已正式发布](https://github.com/UllrAI/SayKuku/releases/tag/v1.0.10)，官网、R2 更新源和旧版版本文件均已上线。

| 范围 | 结果 |
| --- | --- |
| Swift 离线测试 | 349 项、44 个 suite 通过；覆盖旧偏好迁移、开发版禁用、忙碌等待、等待期间重新开始任务、最终保存暂停新工作、保存失败取消退出、未领取结果确认 |
| Python 离线测试 | 24 项通过，包括既有样本导出测试；覆盖版本/构建号、旧 DMG 构建号读取、产物篡改、同名远端冲突、官网两种语言信息和说明、发布顺序、中途失败与清单生成失败后的恢复、R2 源站对象检查与 CDN 404 缓存回归 |
| 真实安装 | 独立 UUID 测试 Bundle ID，旧/新版 App 与 DMG 均经 Developer ID 签名、公证、Gatekeeper 验证；使用回环更新源和临时测试密钥 |
| 安装过程 | 后台下载时旧版继续工作；忙碌时 Quit 等待；保存失败后恢复使用；再次 Quit 保存成功后替换；无自动重新打开；下一次手动启动为新版 |
| 签名不符 | 提供错误 EdDSA 签名，旧版保持运行、可正常退出，安装路径没有被替换 |
| R2 实际上传 | 独立测试对象公开回读后清理；正式 DMG 上传成功，公开下载大小与 SHA-256 一致，已有同名包通过源站哈希检查后复用 |
| 正式发布前检查 | 线上版本与构建号单调性、旧签名 DMG 读取、Wrangler / Zeabur 现有登录和部署配置通过；未创建新服务 |
| 正式发布产物 | 通用 arm64 / x86_64 App、完整 Sparkle framework 与 helpers；App 和 DMG 的签名、公证、staple、Gatekeeper 及最终 EdDSA 校验通过 |
| 官网部署 | 现有 Zeabur 服务上线成功，运行日志正常；公开中英文下载页和首页均与已部署源码一致 |
| 更新说明更正 | 旧版 `ver.json` 改为三条简短中文；appcast 分别提供 `zh-Hans` / `en` 的 Markdown 说明，按用户语言选择；两种语言下载页分别显示对应说明；安装包版本、构建号、哈希与签名不变 |

## 实装测试发现并修复的问题

- 忙碌任务结束的 Swift 异步回调直接触发 AppKit 退出，会阻塞最后保存：改为经主 RunLoop 发起退出，再验证保存失败和重试退出。
- CDN 拒绝默认 Python User-Agent：发布回读使用明确的 `SayKuku-Release/1.0`；R2 上传与公开哈希回读已实际复验通过。
- 公证成功后，旧更新源读取失败原先没有恢复入口：在网络操作前保存产物检查点，可继续生成清单，无需重做构建或公证。
- 语言切换重新打开沿用任务等待、未领取结果确认和新任务暂停；已下载更新时使用 Sparkle 标准确认流程。
- 首次正式上传前的公开 404 被 CDN 缓存：停止后续发布，通过精确 URL 清理恢复；存在性检查改走认证 R2 接口，并新增 3 项回归测试，避免再次制造负缓存或误覆盖同名包。

## 已发布的 1.0.10

- App 构建提交：`38ea8a7442d437f92b8f95b46097c62f7d8e3d5e`，构建号 `382`。
- DMG：`Dist/SayKuku-1.0.10.dmg`，6,613,105 字节（6.61 MB）。
- SHA-256：`573203e9b0de2d1719fbd0358fac08c286b372320ac6db9f15a0a56a942f2fa8`。
- 上一版 1.0.9：5,641,540 字节（5.64 MB）；本次净增加约 0.97 MB、17.2%。
- 两种架构的 Mach-O 最低系统版本均为 macOS 14.0。当前 Xcode 27 对通用构建的 Intel 架构有工具链弃用提示；相同参数的无第三方依赖最小包也出现该提示。现有 hdiutil 操作同样有工具弃用提示，无新增 Swift 源码警告。

Git 标签 `v1.0.10` 指向实际构建提交；GitHub Release 的 DMG 资产摘要与 R2 公开安装包一致。官网、R2、仓库官网目录、`Dist/ver.json` 与发布目录中的 `ver.json` 字节完全一致，均为版本 `1.0.10`、构建号 `382`；公开 appcast 的版本、构建号、URL、大小及 EdDSA 签名已核对。后续发布工具与文档修复没有改变已发布 App 的代码、资源或依赖。

## 复验与边界

```bash
swift test
python3 -m unittest discover -s Scripts/tests
SAYKUKU_UPDATE_INTEGRATION=1 python3 Scripts/tests/test_updater_integration.py
Scripts/release.sh --prepare --notes /absolute/path/release-notes.txt
Scripts/release.sh --prepare --resume Dist/releases/1.0.10/release.json
```

安装测试的历史/记忆标记文件留存；临时测试私钥、独立偏好与缓存清理。没有读取正式用户 store、API Key、麦克风或辅助功能权限，不能把隔离测试当作正式用户 TCC / Keychain 跨版本实测。只读安装位置的系统授权与取消 UI 仍属于人工兼容性验收；Sparkle 私钥已按持有人授权在仓库外完成备份，回读公钥一致，系统确认云盘上传完成；钥匙串条目本身仍不依赖 iCloud 自动同步。

已检查发布时的 Git 跟踪文件与相关提交，未发现导出的私钥、本机部署配置值或常见真实凭据模式；仓库仅保留客户端验证更新所需的公钥。新增私钥、PEM 与环境配置文件忽略规则。

本机原始记录在 `Build/sparkle-*.log`、`Build/updater-*/` 和 `Dist/releases/1.0.10/`，均不提交仓库。发布流程见 [本地打包与发布](LOCAL_PACKAGING.md)。
