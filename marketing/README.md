# SayKuku 宣发资料

官网：`https://say.anikuku.com/`。产品表达以 [事实与措辞](strategy/positioning.md) 为准。主标识是用户提供的橙色鸟形、深色 `SayKuku` 与末尾橙红点；正文中名称仍写 SayKuku。

## 从哪里找

| 目录 | 内容 |
| --- | --- |
| `site/dist/` | 中文首页、英文页、配置指南、隐私、FAQ、媒体资料的可部署静态站 |
| `assets/brand/` | 官方横向字标与带 Just Say It 的字标原图 |
| `assets/generated/` | 小红书、公众号/朋友圈、X、Product Hunt 的带字成品图 |
| `assets/screenshots/` | 开发版真实界面截图及来源说明 |
| `platforms/` | 每个平台直接可用的正文、标题和配图建议 |
| `copy/press-kit.md` | 产品简介、事实清单、媒体短介绍与演示分镜 |
| `strategy/` | 定位、渠道节奏、发布与复盘清单 |
| `issues/` | GitHub issues 对应的任务说明 |

## 先讲什么

1. **Fn 是 Voice Input**：把说的话写到当前光标。
2. **Fn Fn 是 Voice Agent**：改写或翻译选区、提问、继续对话。
3. 记忆只讲人名、项目和术语，手动添加、从粘贴文字中挑选或确认纠正。没有文件/截图提取与关系知识库。
4. App 免费，安装包 4.9 MB；使用 Qwen3.8 Omni Flash 系列，用户自备 API Key 并承担模型费用。源代码已在 [GitHub](https://github.com/UllrAI/SayKuku) 公开，采用 Apache-2.0 许可。

官网交互区是**预设网页演示**，不调用麦克风或模型。1.0.4 正式安装包从官网版本区下载；真实 App 录屏与正式版截图由 [#158](https://github.com/UllrAI/SayKuku/issues/158) 跟踪。发布时不要把网页演示说成实际识别结果。

## 渠道顺序

- 小红书、朋友圈、X：场景和交互先行；提问收集用户常用 App。
- 公众号：把动机、实际操作、配置门槛与隐私讲清楚。
- V2EX、Product Hunt：安装包公开后再核对当时的平台字段、配上真实操作演示并集中发布。

相关事项：[域名与正式试用入口 #157](https://github.com/UllrAI/SayKuku/issues/157)、[真实演示素材 #158](https://github.com/UllrAI/SayKuku/issues/158)、[首轮渠道与复盘 #159](https://github.com/UllrAI/SayKuku/issues/159)。
