# 官网 CI runner 规则

[Site CI/CD](../.github/workflows/site.yml) 负责官网测试、私有 GHCR 镜像和 Coolify 部署。macOS App 的测试、打包、签名和公证按[本机发布流程](LOCAL_PACKAGING.md)执行。

## 路由

| 触发方式 | 测试和镜像 | Coolify 部署 |
| --- | --- | --- |
| PR（含同仓库 PR） | GitHub-hosted Linux，仅运行测试 | 跳过 |
| `UllrAI/SayKuku` 的 `main` 推送或手动运行 | 默认 GitHub-hosted Linux，设置 `PVE_BUILDS=true` 并提供标签后使用 PVE | 默认 GitHub-hosted Linux，单独设置 `PVE_DEPLOY=true` 并提供标签后使用 PVE |
| 非 `main` 的手动运行 | GitHub-hosted Linux，仅运行测试 | 跳过 |

两项开关均为仓库 Actions variables。PVE 还要求 `PVE_RUNNER_LABELS` 为非空 JSON 字符串数组，例如 `["self-hosted","linux","x64","pve-101","saykuku-isolated"]`，最后一项须使用现场登记的 SayKuku 专用标签。GitHub 按全部标签匹配。开关未设为 `true`，或标签变量为空时，使用原有 GitHub-hosted 路由。

## 启用前验收

截至 2026-11-14，仓库 runner API 返回 0 台可用自托管 runner。现有生产工作流继续使用 GitHub-hosted runner。

1. 由组织管理员确认 GitHub runner 组的仓库及工作流权限。SayKuku 是公开仓库，使用仅向 SayKuku 开放的隔离 runner 组，并在 GitHub 侧将工作流访问限定为 `UllrAI/SayKuku/.github/workflows/site.yml@refs/heads/main`。YAML 的事件条件和标签只负责路由。
2. 在隔离的 Linux x64 环境验证 runner、Ubuntu 24.04、工作流所需 Node/Python、`gh`、rootless Docker/Buildx 与 GHA 缓存。使用独立工作目录、容器、端口、缓存及凭据，确认 PVE 主机总并发容量。网站 smoke test 会由 Docker 分配回环端口，并在结束时清理自己的容器。
3. 先用相同源码完成发布、站点和部署单元测试及真实镜像 smoke test，核对 GitHub 显示 runner 在线及标签齐全。验收后只启用 `PVE_BUILDS`，确认可信 `main` 上的镜像测试、私有 GHCR 发布及托管部署通过。
4. 再单独验收部署权限和网络。确认能使用现有作用域的 `COOLIFY_WEBHOOK`、`COOLIFY_TOKEN`，完成部署状态轮询和公开 `/revision.txt` 校验，再决定是否启用 `PVE_DEPLOY`。

## 重试与监控

- 工作流不按运行次数切换 runner，也没有新的 GitHub-hosted 轮询任务。需要回退时，先处理已排队或进行中的运行，再关闭对应开关，并在确认当前 `main` 后手动运行 `site.yml`。
- 官方发布按提交校验镜像与公开站点。Coolify 状态读取发生暂时错误时重试读取。遇到部署结果不确定，先核对 Coolify 部署状态和公开版本，再决定是否重试，避免重复触发。
- 统一规则约定由独立的 Coolify `ci-watchdog` 每两分钟检查 GitHub 队列和 runner 状态。监控部署及告警需独立验收。本仓库无额外 watcher 凭据或托管预算。在线且忙碌时等待，API 错误时状态未知，连续离线时告警去重。测试失败按原失败原因处理。
