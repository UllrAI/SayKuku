# 官网 CI runner 规则

[Site CI/CD](../.github/workflows/site.yml) 负责官网测试、私有 GHCR 镜像和 Coolify 部署。macOS App 的测试、打包、签名和公证按[本机发布流程](LOCAL_PACKAGING.md)执行。

## 路由

| 触发方式 | 测试和镜像 | Coolify 部署 |
| --- | --- | --- |
| PR（含同仓库 PR） | GitHub-hosted Linux，仅运行测试 | 跳过 |
| `UllrAI/SayKuku` 的 `main` 推送或手动运行 | VM 101，读取 `PVE_BUILDS` 和 `PVE_RUNNER_LABELS` | GitHub-hosted Linux |
| 非 `main` 的手动运行 | GitHub-hosted Linux，仅运行测试 | 跳过 |
| 手动运行 `PVE website build check` | 仅接受 `UllrAI/SayKuku` 的 `main`，在 VM 101 上构建并测试容器 | 无部署任务 |

两项开关均为仓库 Actions variables。构建读取 `PVE_RUNNER_LABELS`，部署读取 `PVE_DEPLOY_RUNNER_LABELS`。标签值为非空 JSON 字符串数组，使用 Coolify-Ops 为 `UllrAI` 的 VM 101 worker 确认的标签。通用的 `self-hosted`、`linux`、`x64` 和 `pve-101` 只描述运行环境，需搭配 Ops 确认的调度标签。GitHub 按全部标签匹配。开关未设为 `true` 或对应变量为空时，使用原有 GitHub-hosted 路由。

## 当前状态与信任边界

2026-11-14 核实 SayKuku 是公开仓库。Coolify-Ops 将 SayKuku 加入 VM 101 的 `PVE-VM101` 组织 runner 组，组允许选定的公开仓库使用，工作流访问范围为 All workflows。组织级 runner 已从 GitHub 作业记录验证。仓库 fork 工作流只要求首次贡献者获批，`GITHUB_TOKEN` 默认只读，`main` 当前没有生效的保护规则。

本仓库现有 YAML 将 PR 测试调度到 GitHub-hosted Linux。共享组的 All workflows 设置仍适用于选定仓库，审查工作流改动时需核对 fork 触发条件和凭据范围。生产构建仅使用当次 `GITHUB_TOKEN` 上传私有镜像，`PVE_DEPLOY` 保持未设置，Coolify 凭据仅供 GitHub-hosted 部署 job 使用。标准托管 runner 的公开仓库用量适用 GitHub 免费规则。

参考 [runner 组访问控制](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/manage-access)、[公开 fork 工作流审批](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)和 [Actions 计费规则](https://docs.github.com/en/actions/concepts/billing-and-usage)。

## VM 101 与现场验收

SayKuku 使用 `UllrAI` 的共享 VM 101 runner `pve-101-ullrai`。`PVE_RUNNER_LABELS` 为 `["self-hosted","linux","x64","pve-101","pve-101-ullrai"]`。VM 101 的容量、注册、标签和网络由 Coolify-Ops 统一协调。跨仓库构建按 Ops 的共享容量安排。

2026-11-14，以 `f5b6ce5203eec67b50c73d257bcb24a6f75074ed` 完成[首次验收](https://github.com/UllrAI/SayKuku/actions/runs/43600974542/attempts/1)及[同一运行重跑](https://github.com/UllrAI/SayKuku/actions/runs/43600974542/attempts/2)。两次均由 `pve-vm101` 组的 `pve-101-ullrai` 执行，加载 `linux/amd64` 镜像并通过 9 项容器内站点检查。验收通过后启用 `PVE_BUILDS=true`。

- **调度。** 核对组织 runner 的仓库和工作流访问控制，确认可信 `main` 的测试和镜像任务可以使用 PVE，普通重跑按原路由运行。按现有边界，同仓 PR 和 fork PR 只跑托管测试。启用前记录实际 runner 名称、可匹配的标签及 `main` 的可信写入者范围。单独验收部署路由及凭据范围。
- **构建。** 以可信 `main` 验证 `linux/amd64` 镜像、随机回环端口、容器清理、GHCR 私有性和 digest 回拉。构建 job 使用当次 `GITHUB_TOKEN`（`contents: read`、`packages: write`）。网络验收涵盖 [GitHub 所需域名](https://docs.github.com/en/actions/reference/runners/self-hosted-runners#accessible-domains-by-function)、GHCR 和基础镜像下载。构建无需访问 Coolify 控制面。
- **部署。** 单独核对构建和部署 job 的凭据可见范围。部署 job 使用现有 `COOLIFY_WEBHOOK` 和 `COOLIFY_TOKEN`，访问 `c.ullrai.com` 与 `say.anikuku.com`。Coolify 服务端用现有只读 GHCR 凭据拉取镜像。验收需确认一次触发、状态读取和公开 `/revision.txt`。
- **运行记录。** 保留 run 链接、提交 SHA、attempt、各 job 的 `runner_name` 和结论。若托管 job 因账单或组织策略受阻，保留原失败记录。运行条件就绪后，从当前可信 `main` 发起新运行。PR 继续等待现有检查结果。

[PVE website build check](../.github/workflows/pve-build-check.yml) 可从 GitHub Actions 手动运行。工作流使用 runner 的 Docker 上下文和 Buildx builder。也可以在现场从仓库根目录执行同一检查。

```bash
bash Scripts/check_pve_runner.sh
```

脚本检查工具和 Docker 服务可用性，运行发布、站点、部署测试，构建并加载 `linux/amd64` 镜像，核对镜像平台，再用 CI 共用的 smoke test 验证容器和回环端口连通性。本次镜像和容器在结束时清理。私有镜像推送、digest 回拉以及公开站点版本由生产 Site CI/CD 验证。

## 重试与监控

- 工作流不按运行次数切换 runner，也没有 GitHub-hosted 轮询任务。切回 GitHub-hosted runner 需由负责人明确选择，并确认运行在现有获批预算或可用免费额度内。先处理已排队或进行中的运行，再关闭对应开关，确认当前 `main` 后手动运行 `site.yml`。
- 官网 CI 按 digest 回拉并核对测试过的镜像，再更新部署标签。Coolify 部署与固定 digest 的权限边界见[官网部署说明](../marketing/site/README.md#coolify-与-cicd)。遇到部署结果不确定，先核对 Coolify 部署状态和公开版本，再决定是否重试，避免重复触发。
- Coolify `ci-watchdog` 每两分钟只读检查 GitHub 队列和 runner 状态。已有的只读观察须保留到中央 watcher 覆盖本仓库、外部心跳缺失告警以及故障与恢复通知均通过验收。在线且忙碌时等待，API 错误时状态未知，连续离线时告警去重。测试失败按原失败原因处理。
