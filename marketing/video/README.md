# SayKuku 宣传视频源码

两套项目并列存放，分别安装依赖和渲染，不混用 composition、配乐或 lockfile。

| 项目 | 名称与用途 | 规格 |
| --- | --- | --- |
| [product-overview/](product-overview/) | 产品概览宣传片：快速介绍品牌、Fn 语音输入与 Voice Agent | 20 秒 · 1080p · 60 fps · 120 BPM |
| [voice-workflow/](voice-workflow/) | 语音工作流演示：单击 Fn 听写、同键双击、选区翻译、完成与撤销 | 15 秒 · 1080p · 60 fps · 128 BPM |

每套目录都包含源码、依赖锁文件、原创音频生成脚本和运行说明。成片和音频生成物不提交 Git。界面演示为动效，实际录屏与开发版截图的区分见各项目说明。

原 `marketing/video/` 根目录的 20 秒项目已迁入 `product-overview/`，原操作命令需先进入该目录；输出仍在仓库根目录 `Dist/marketing/`。
