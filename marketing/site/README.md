# SayKuku 官网

主域名：<https://say.anikuku.com/>。页面以用户提供的 `~/Downloads/SayKuku.html` 为视觉与交互基准，源码在仓库的 `dist/`，部署到 Zeabur 时以该目录为站点根。`CLAUDE.md` 记录已有项目与服务 ID，后续部署必须复用服务。

## 页面

- `/`：中文首页、预设交互和 1.0.1 下载区（`#download`）
- `/en/`：英文介绍与下载入口，供 X 与 Product Hunt 引用
- `/guide/`：配置、权限与两种 Fn 操作
- `/privacy/`：音频、Agent 上下文、本机保存与权限说明
- `/faq/`：系统、费用与兼容性
- `/press/`：媒体简介、官方鸟形 Logo 与宣传图
- `/ver.json`：1.0.1 起 App 使用的更新版本文件；旧版镜像保存在 R2 的 `saykuku/ver.json`

首页上的预设演示不请求麦克风，也不调用模型。下载按钮直达 `https://saykuku.ullrai.com/SayKuku-1.0.1.dmg`，由 Cloudflare R2 的 `saykuku` bucket 公开域名提供。发布前核对版本号、签名、公证、公开文件哈希及下载状态；发布流程见 `docs/LOCAL_PACKAGING.md`。

## 本机预览

```bash
python3 -m http.server 8765 --directory marketing/site/dist
```

打开 `http://127.0.0.1:8765/`。站内资源使用绝对路径，部署时须以域名根目录为站点根。
