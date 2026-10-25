# SayKuku 官网

主域名：<https://say.anikuku.com/>。源代码仓库：<https://github.com/UllrAI/SayKuku>。站点源码在仓库的 `dist/`，部署到 Zeabur 时以该目录为站点根。部署标识只保存在本机，后续部署必须复用服务；步骤见 `CLAUDE.md`。

## 页面

- `/`：中文首页与预设交互，下载按钮进入独立下载页
- `/en/`：英文介绍，供 X 与 Product Hunt 引用
- `/download/`、`/en/download/`：当前安装包、系统要求、安装步骤与文件校验
- `/guide/`：配置、权限与两种 Fn 操作
- `/privacy/`：音频、Agent 上下文、本机保存与权限说明
- `/faq/`：系统、费用与兼容性
- `/press/`：媒体简介、官方鸟形 Logo 与宣传图
- `/ver.json`：旧版 App 使用的更新版本文件，与 R2 的 `saykuku/ver.json` 保持一致；引入 Sparkle 后仍保留

首页上的预设演示不请求麦克风，也不调用模型。首页下载按钮进入 `/download/`；下载页连接 R2 的版本化 `SayKuku-<版本>.dmg`，当前版本来自 `dist/ver.json`。Sparkle 更新源位于 R2 的 `appcast.xml`。

App 上线统一从仓库根目录运行 `Scripts/release.sh --notes FILE`：先完成签名、公证和公开 DMG 哈希校验，再生成并部署官网版本、大小、下载链接、哈希和说明，最后同步更新清单。官网与 R2 的 `ver.json` 必须保留并来自同一份发布元数据。失败恢复与上线核对步骤见 [本地打包与发布](../../docs/LOCAL_PACKAGING.md)。仅修改官网内容时按 [CLAUDE.md](CLAUDE.md) 部署现有服务。

页面浏览与关键点击使用自建 Umami 统计，事件和归因规则见 [ANALYTICS.md](ANALYTICS.md)。

## 本机预览

```bash
python3 -m http.server 8765 --directory marketing/site/dist
```

打开 `http://127.0.0.1:8765/`。站内资源使用绝对路径，部署时须以域名根目录为站点根。
