# SayKuku 官网

主域名：<https://say.anikuku.com/>。页面以用户提供的 `~/Downloads/SayKuku.html` 为视觉与交互基准，源码在仓库的 `dist/`，部署到 Zeabur 时以该目录为站点根。部署标识只保存在本机，后续部署必须复用服务；步骤见 `CLAUDE.md`。

## 页面

- `/`：中文首页与预设交互，下载按钮进入独立下载页
- `/en/`：英文介绍，供 X 与 Product Hunt 引用
- `/download/`、`/en/download/`：1.0.2 安装包、系统要求、安装步骤与文件校验
- `/guide/`：配置、权限与两种 Fn 操作
- `/privacy/`：音频、Agent 上下文、本机保存与权限说明
- `/faq/`：系统、费用与兼容性
- `/press/`：媒体简介、官方鸟形 Logo 与宣传图
- `/ver.json`：1.0.1 起 App 使用的更新版本文件；旧版镜像保存在 R2 的 `saykuku/ver.json`

首页上的预设演示不请求麦克风，也不调用模型。首页下载按钮进入 `/download/`；下载页的 DMG 按钮连接 `https://saykuku.ullrai.com/SayKuku-1.0.2.dmg`，由 Cloudflare R2 的 `saykuku` bucket 公开域名提供。发布前核对版本号、签名、公证、公开文件哈希及下载状态；发布流程见 `docs/LOCAL_PACKAGING.md`。

页面浏览与关键点击使用自建 Umami 统计，事件和归因规则见 [ANALYTICS.md](ANALYTICS.md)。

## 本机预览

```bash
python3 -m http.server 8765 --directory marketing/site/dist
```

打开 `http://127.0.0.1:8765/`。站内资源使用绝对路径，部署时须以域名根目录为站点根。
