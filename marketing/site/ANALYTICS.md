# SayKuku 官网统计

Umami：<https://track.pixmiller.com/websites/2cabd56c-0309-4ffb-a63a-11abd23f7195>。统计网站为 `say.anikuku.com`，Website ID 是 `2cabd56c-0309-4ffb-a63a-11abd23f7195`。页面源码位于 `dist/`，所有 HTML 页面都加载同一追踪脚本。

## 看哪些数据

| 指标 / 事件 | 触发时机 | 用途 |
| --- | --- | --- |
| 页面浏览 | Umami 自动记录所有官网页面 | 看首页、下载页、指南、FAQ 等页面的到达量 |
| `download_page_click` | 首页 Hero、尾部 CTA 或导航进入下载页 | 比较下载入口的位置；`location` 为 `hero`、`closing` 或 `nav` |
| `installer_download_click` | 点击中英文下载页的 DMG 按钮 | 主要转化目标；附 `version` 与 `language`。只表示点击，不能当作下载完成或安装成功 |
| `demo_started` | 首页预设 Fn 演示实际启动 | 看 Voice Input / Voice Agent 的使用兴趣；附 `mode`、`input_style` |
| `contact_click` | 点击页脚邮箱 | 看联系意向；不记录邮件内容 |
| `press_asset_download_click` | 点击媒体资料页的 PNG 链接 | 看素材使用需求；只附站内静态文件名 |
| `related_site_click` | 点击页脚的 AniKuku 或 Ullr AI Lab 链接 | 看相关站点的引流；`site` 为 `anikuku` 或 `ullrai` |

Umami 中已建立目标「安装包下载点击」，条件为 `installer_download_click`。日常观察可按「进入下载页 → 点击 DMG」理解漏斗，但下载完成、安装和激活不在官网统计范围内。统计站点不公开共享。

## 来源与隐私

官网只在 `say.anikuku.com` 上发送事件，本机预览不会污染数据。浏览器的 DNT 设置会被尊重。`assets/analytics.js` 在发送前移除 URL 查询参数，只保留值为简短字母、数字、下划线或连字符的五种 UTM 参数，并去掉片段及来源 URL 的查询参数。事件只使用固定枚举和静态资源名，不采集演示文字、录音、API Key 或邮件内容。官网隐私说明在 `/privacy/` 同步披露 Umami。

发布稿可使用 `utm_source`、`utm_medium`、`utm_campaign=launch_102`，同平台不同稿件用 `utm_content` 区分。X、V2EX、公众号与 Product Hunt 发布稿已加入对应参数；朋友圈、小红书和微博的可见短网址保持简洁，访问来源可从 Umami 的来源报告查看，缺失来源的流量不能强行归因。

## 核验

1. 查看首页及下载页源代码，确认只加载一次 `https://track.pixmiller.com/script.js`，且 Website ID 一致。
2. 在正式域名访问首页、点击下载入口，再点击 DMG；Umami 的实时、事件和目标中应出现对应数据。页面浏览与点击是测试事件，检查报表时需留意。
3. 用带 UTM 与任意其他查询参数的地址测试；Umami 应只收到 UTM。浏览器启用 DNT 或在 localhost 预览时不应发送事件。
