# 官网 CI runner 规则

[Site CI/CD](../.github/workflows/site.yml) 负责官网测试、私有 GHCR 镜像和 Coolify 部署。macOS App 的测试、打包、签名和公证按[本机发布流程](LOCAL_PACKAGING.md)执行。

## 路由

| 触发方式 | 测试和镜像 | Coolify 部署 |
| --- | --- | --- |
| PR（含同仓库 PR） | GitHub-hosted Linux，仅运行测试 | 跳过 |
| `UllrAI/SayKuku` 的 `main` 推送或手动运行 | 默认 GitHub-hosted Linux，设置 `PVE_BUILDS=true` 并提供标签后使用 PVE | 默认 GitHub-hosted Linux，单独设置 `PVE_DEPLOY=true` 并提供部署标签后使用 PVE |
| 非 `main` 的手动运行 | GitHub-hosted Linux，仅运行测试 | 跳过 |

两项开关均为仓库 Actions variables。构建读取 `PVE_RUNNER_LABELS`，部署读取 `PVE_DEPLOY_RUNNER_LABELS`。标签值为非空 JSON 字符串数组。构建示例为 `["self-hosted","linux","x64","pve-101","saykuku-build"]`，部署示例为 `["self-hosted","linux","x64","pve-101","saykuku-deploy"]`。使用现场验收后的标签，单台 runner 只带自己负责的角色标签。GitHub 按全部标签匹配。开关未设为 `true` 或对应变量为空时，使用原有 GitHub-hosted 路由。

## 当前状态与信任边界

2026-11-14 核实 SayKuku 是公开仓库，仓库 API 返回 0 台自托管 runner，PVE 变量均未设置。仓库 fork 工作流只要求首次贡献者获批，`GITHUB_TOKEN` 默认只读，`main` 当前没有生效的保护规则。当前凭据可管理仓库，组织 runner 和 runner 组查询返回 403。组织 API 报告 Free 计划，实际可用的工作流级 runner 组限制仍需组织所有者验证。当前生产工作流继续使用 GitHub-hosted runner。

YAML 的事件条件和标签负责调度。公开仓库的 fork 可以提出修改 YAML，必须由 GitHub 侧的 runner 组访问规则挡住这类工作流。给公开仓库配置的 repo 级 runner、共享组或仅靠难猜标签都无法替代工作流级隔离。若当前计划或组织设置无法提供下述限制，保持托管路由。标准托管 runner 的公开仓库用量适用 GitHub 免费规则。

参考 [runner 组访问控制](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/manage-access)、[公开 fork 工作流审批](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)和 [Actions 计费规则](https://docs.github.com/en/actions/concepts/billing-and-usage)。

## 接入与现场验收

1. **组织所有者确认 GitHub 调度边界。** 核对现有计划与组策略。批准后配置专用组，只向 `UllrAI/SayKuku` 开放，并将工作流访问限定为 `UllrAI/SayKuku/.github/workflows/site.yml@refs/heads/main`。同时确认 `main` 的可信写入者范围。若要改分支 ruleset、要求审核或限制绕过权限，先明确这些更改对现有本机发布脚本直接推送 `main` 的影响。
2. **PVE 管理员确认构建执行环境。** 在已有容量内划出 SayKuku 独立 Linux x86_64 环境（按 Ubuntu 24.04 验收），使用专用非 root 服务账号、工作目录及 rootless Docker/Buildx。注册在确认过的组织 runner 组内，优先使用单任务临时 runner 和清理后的环境。登记标签前先验收网络：GitHub Actions、runner 更新、Actions 下载及缓存域按 [GitHub 出站清单](https://docs.github.com/en/actions/reference/runners/self-hosted-runners#accessible-domains-by-function)放行 HTTPS，并允许 GHCR、Docker Hub 及镜像下载所需域名。构建环境无需访问 PVE 管理网、生产内网或 Coolify 控制面。任何新 VM、出口防火墙规则和 runner 注册都需对应管理员逐项确认。注册凭据由组织所有者在受控终端生成，只交给注册步骤，避免持久存放。
3. **先跑构建验收。** 在隔离环境以 runner 账号检出可信 `main`，运行下方脚本。由组织所有者确认 GitHub 上该 runner 在线、标签正确、组的仓库和工作流限制已生效。先只设置构建标签并启用 `PVE_BUILDS`。对当前 `main` 发起一轮新的 `site.yml`，检查测试与镜像 job 的 `runner_name` 和标签，核对 GHCR 私有性、按 digest 回拉和公开部署 revision。构建凭据只有本次 job 的 `GITHUB_TOKEN`（`contents: read`、`packages: write`）。部署阶段暂留 GitHub-hosted，Coolify 服务端继续用既有只读 GHCR 凭据拉取。
4. **部署 runner 单独验收。** 若要迁移部署阶段，另用专用执行环境、账号和 `saykuku-deploy` 标签。管理员需批准该 runner 接收现有 `COOLIFY_WEBHOOK`、`COOLIFY_TOKEN`，并放行 `c.ullrai.com` 与 `say.anikuku.com` 的 HTTPS。确认现有令牌只承担一次部署触发和状态读取，现场通过后才设置部署标签并启用 `PVE_DEPLOY`。增加令牌 `write`、扩大 Coolify 团队或 GHCR 权限、改变生产信任策略均是单独的授权决定。
5. **验证失败时保留原发布记录。** 查清 run 的失败步骤、应用队列和当前 `/revision.txt`。若托管 job 因账单或组织策略受阻，保留该 run 的失败结论。受控 PVE 可用后，以当前可信 `main` 发起新运行，走原有测试、镜像、部署和公开校验。若阻断发生在托管部署阶段，先恢复获批托管能力，或独立验收部署 runner 后再启用。既有 PR 仍走托管测试并等待检查结果。

现场命令（从仓库根目录，以构建 runner 账号执行）：

```bash
bash Scripts/check_pve_runner.sh
```

脚本检查 Linux x86_64、非 root 账号、本地 rootless Docker 和所需工具，运行发布、站点和部署测试，构建 `linux/amd64` 镜像，并调用 CI 共用的容器 smoke test。它使用随机镜像名和回环端口，执行后清理本次产物。这个检查无需 GHCR 写入、Coolify 或应用凭据。通过后仍需保留 GitHub 运行链接、提交 SHA、attempt、各 job 的 `runner_name` 与结论，以验证调度、GHA 缓存及完整发布。

## 重试与监控

- 工作流不按运行次数切换 runner，也没有 GitHub-hosted 轮询任务。切回 GitHub-hosted runner 需由负责人明确选择，并确认运行在现有获批预算或可用免费额度内。先处理已排队或进行中的运行，再关闭对应开关，确认当前 `main` 后手动运行 `site.yml`。
- 官网 CI 按 digest 回拉并核对测试过的镜像，再更新部署标签。Coolify 部署与固定 digest 的权限边界见[官网部署说明](../marketing/site/README.md#coolify-与-cicd)。遇到部署结果不确定，先核对 Coolify 部署状态和公开版本，再决定是否重试，避免重复触发。
- 统一规则约定由独立的 Coolify `ci-watchdog` 每两分钟检查 GitHub 队列和 runner 状态。监控部署及告警需独立验收。本仓库无额外 watcher 凭据或托管预算。在线且忙碌时等待，API 错误时状态未知，连续离线时告警去重。测试失败按原失败原因处理。
