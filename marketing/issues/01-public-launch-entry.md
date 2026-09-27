# 接通 say.anikuku.com 并发布正式试用入口

## 背景

官网源码保存在 `marketing/site/dist/`，部署于 Zeabur 新加坡服务器。下载入口固定到首页 `#download`，安装包使用 Cloudflare R2 的 `saykuku` bucket 与公开域名 `saykuku.ullrai.com`。仓库可保持私有；公开下载不依赖 GitHub Release。

## 完成标准

- [ ] 官网 `say.anikuku.com` 的 HTTPS、中文/英文、指南、隐私、FAQ、媒体页和版本下载区均公开可访问。
- [ ] `Scripts/release.sh` 产出的最新 DMG 已完成 Developer ID 签名、App 和 DMG 双重公证与装订、Gatekeeper 校验；包内版本与官网一致。
- [ ] 最新 DMG 上传到 R2，未登录浏览器可下载；公开文件的 SHA-256 与本机一致。
- [ ] 官网 `/ver.json` 与旧版读取的 R2 `/ver.json` 均指向 `https://say.anikuku.com/#download`，版本号与公开包一致。
- [ ] 下载页说明 macOS 15+、Apple 芯片/Intel、自备当前模型服务 API Key、云端处理和可能产生的模型费用。
- [ ] 对外渠道统一引用官网版本区，不再传播旧下载入口。

## 参考

`marketing/site/README.md`、`marketing/strategy/launch-checklist.md`、`docs/LOCAL_PACKAGING.md`
