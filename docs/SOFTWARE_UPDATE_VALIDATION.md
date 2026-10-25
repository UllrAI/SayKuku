# 软件更新验证记录

验证日期：2026-10-25。对应 #169，固定 Sparkle 2.10.0；正式版本候选为 1.0.10。未向正式更新源或官网发布候选版本。

| 范围 | 结果 |
| --- | --- |
| Swift 离线测试 | 349 项、44 个 suite 通过；覆盖旧偏好迁移、开发版禁用、忙碌等待、等待期间重新开始任务、最终保存暂停新工作、保存失败取消退出、未领取结果确认 |
| Python 离线测试 | 21 项通过，包括既有样本导出测试；覆盖版本/构建号、旧 DMG 构建号读取、产物篡改、同名远端冲突、官网两种语言信息和说明、发布顺序、中途失败与清单生成失败后的恢复 |
| 真实安装 | 独立 UUID 测试 Bundle ID，旧/新版 App 与 DMG 均经 Developer ID 签名、公证、Gatekeeper 验证；使用回环更新源和临时测试密钥 |
| 安装过程 | 后台下载时旧版继续工作；忙碌时 Quit 等待；保存失败后恢复使用；再次 Quit 保存成功后替换；无自动重新打开；下一次手动启动为新版 |
| 签名不符 | 提供错误 EdDSA 签名，旧版保持运行、可正常退出，安装路径没有被替换 |
| R2 实际上传 | 向独立 UUID 路径上传测试 DMG，公开回读 SHA-256 一致，再删除临时对象；未修改正式 appcast/ver.json |
| 正式发布前检查 | 线上版本与构建号单调性、旧签名 DMG 读取、Wrangler / Zeabur 现有登录和部署配置通过；未创建新服务 |
| 正式候选产物 | 通用 arm64 / x86_64 App、完整 Sparkle framework 与 helpers；App 和 DMG 的签名、公证、staple、Gatekeeper 及最终 EdDSA 校验通过 |
| 官网生成 | 使用实际候选元数据在本机生成两种语言下载页、实际大小、链接、SHA-256 和更新说明；未部署正式官网 |

## 实装测试发现并修复的问题

- 忙碌任务结束的 Swift 异步回调直接触发 AppKit 退出，会阻塞最后保存：改为经主 RunLoop 发起退出，再验证保存失败和重试退出。
- CDN 拒绝默认 Python User-Agent：发布回读使用明确的 `SayKuku-Release/1.0`；R2 上传与公开哈希回读已实际复验通过。
- 公证成功后，旧更新源读取失败原先没有恢复入口：在网络操作前保存产物检查点，可继续生成清单，无需重做构建或公证。
- 语言切换重新打开沿用任务等待、未领取结果确认和新任务暂停；已下载更新时使用 Sparkle 标准确认流程。

## 候选包

- App 构建提交：`81bb5be620db0901fb1e427e0743c2a93c59c102`，构建号 `382`。
- DMG：`Dist/SayKuku-1.0.10.dmg`，6,613,825 字节（6.61 MB）。
- SHA-256：`2a56e892e03caa43928c345d282eef2e981cb8a0027e09bed15fbee09533e18d`。
- 上一版 1.0.9：5,641,540 字节（5.64 MB）；本次净增加约 0.97 MB、17.2%。
- 两种架构的 Mach-O 最低系统版本均为 macOS 14.0。当前 Xcode 27 对通用构建的 Intel 架构有工具链弃用提示；相同参数的无第三方依赖最小包也出现该提示。现有 hdiutil 操作同样有工具弃用提示，无新增 Swift 源码警告。

后续提交只修复发布工具、增加脚本回归测试和文档，没有改变候选 App 的代码、资源或依赖。正式发布仍需以主分支当次验证后的产物为准。

## 复验与边界

```bash
swift test
python3 -m unittest discover -s Scripts/tests
SAYKUKU_UPDATE_INTEGRATION=1 python3 Scripts/tests/test_updater_integration.py
Scripts/release.sh --prepare --notes /absolute/path/release-notes.txt
Scripts/release.sh --prepare --resume Dist/releases/1.0.10/release.json
```

安装测试的历史/记忆标记文件留存；临时测试私钥、独立偏好与缓存清理。没有读取正式用户 store、API Key、麦克风或辅助功能权限，不能把隔离测试当作正式用户 TCC / Keychain 跨版本实测。只读安装位置的系统授权与取消 UI、真实生产官网部署仍需随首发验收；发布前应把 Sparkle 私钥备份到密码管理器或加密离线存储，不能依赖 iCloud 自动同步。

本机原始记录在 `Build/sparkle-*.log`、`Build/updater-*/` 和 `Dist/releases/1.0.10/`，均不提交仓库。发布流程见 [本地打包与发布](LOCAL_PACKAGING.md)。
