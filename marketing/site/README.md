# SayKuku 官网

主域名：<https://say.anikuku.com/>。源代码仓库：<https://github.com/UllrAI/SayKuku>。本站是纯静态 HTML/CSS/JS，文件在本目录的 `dist/`。GitHub Actions 测试并构建 GHCR 镜像，由 Coolify 拉取部署。

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

## Coolify 与 CI/CD

验证地址：<https://saykuku-preview.ullrai.com/>，与正式域名运行同一个镜像。Coolify 项目 `SayKuku`、环境 `production`、应用 `saykuku-site`。入口 Traefik 统一管理 HTTPS，站点使用官方非 root Nginx Alpine slim，监听 `8080`，无需 Node.js、数据库或持久卷。

[Site CI/CD](../../.github/workflows/site.yml) 只使用 Linux runner：

1. PR 和相关 `main` 提交运行已有发布顺序单元测试、站内链接与下载页检查、部署状态处理测试。
2. `main` 测试通过后构建一次 `linux/amd64` 镜像，运行实际容器检查页面、资源、404、版本文件与 Git 提交标识。
3. 将同一镜像发布为 `ghcr.io/ullrai/saykuku-site:sha-<完整提交号>` 和 `:main`，确认无需凭据即可拉取后才触发 Coolify。
4. Coolify 仅拉取镜像，不再构建源码。工作流等待部署完成，再验证公开站点的内容与 `/revision.txt`，失败会使工作流失败。

仓库配置：Actions secrets `COOLIFY_WEBHOOK`、`COOLIFY_TOKEN`；Actions variable `SAYKUKU_SITE_URL` 为 `https://say.anikuku.com`。令牌只需 `read` 和 `deploy` 权限，不保存到仓库。GHCR package 首次发布后设为 Public，镜像只含这个公开仓库中的站点文件。部署令牌需在到期前轮换。

官网所在仓库为 Public，标准 GitHub-hosted Linux runner 的计算不消耗私有仓库额度；GHCR 容器镜像存储和带宽目前免费。迁移其他私有仓库时，新增构建时间仍计入所属账号或组织额度，复用 workflow 不能免除计费。

手动重试使用 `gh workflow run site.yml`。回退可在 Coolify 将镜像标签从 `main` 改为之前验证过的 `sha-<提交号>` 并重新部署；健康检查路径为 `/healthz`，容器端口为 `8080`。验证域名带 `X-Robots-Tag: noindex, nofollow`，页面 canonical 和安装包地址保持正式域名。

## 本机预览

```bash
python3 -m http.server 8765 --directory marketing/site/dist
```

打开 `http://127.0.0.1:8765/`。站内资源使用绝对路径，部署时须以域名根目录为站点根。
