# CI runner policy

This project participates in the Coolify/PVE unified runner policy.

## Activation is staged, not automatic

As of 2026-11-14 the repository runner API returned no registered self-hosted runners.
This change therefore **does not activate PVE** and keeps the existing hosted route.
Do not enable PVE until a repository-scoped, isolated runner is registered, online,
and has passed the same checks and image smoke tests as the hosted baseline.

Repository variables:

- `PVE_BUILDS=true`: opt trusted main-branch push/manual verification and image jobs into PVE.
- `PVE_DEPLOY=true`: separately opt the deployment job into PVE after deployment verification.
- `PVE_RUNNER_LABELS`: JSON array of verified matching labels, including `self-hosted`, `linux`,
  `x64`, `pve-101`, and this repository's dedicated isolation label. Do not select another
  project's production runner. Missing labels or false/unset switches retain hosted execution.

Pull requests remain hosted (including same-repository PRs); this intentionally avoids
running proposed code with persistent production-level access. Reruns retain their selected
policy and never automatically move to another pool based on `run_attempt`. There is no
repository-owned hosted watcher or automatic paid fallback. With no hosted allowance, a
hosted job may remain blocked; this is not evidence of PVE failure.

## Runner acceptance checklist

- Ubuntu 24.04, current runner, required Node/Python/gh tooling, isolated workspace and
  rootless Docker/Buildx are verified before enabling routing.
- Preinstall browser system dependencies and CJK fonts where used; do not grant blanket
  passwordless sudo just to make hosted-only package install steps work.
- Limit cross-repository capacity at the shared host; repository concurrency is not a
  global capacity limit. Isolate temporary containers, ports, caches and credentials.
- Preserve tests, dependency audits, actual-image smoke checks, immutable commit images,
  existing production environment secrets and public revision verification.
- Deployment retries reuse the tested commit image. Never automatically repeat a partially
  executed deployment or database migration.

## Monitoring and recovery

The separate Coolify-managed `ci-watchdog` observes queue and runner status every two minutes.
It must be deployed and verified independently; this document is not evidence it is live.
Online/busy means wait, API errors mean unknown, and repeated offline observations warrant
one deduplicated incident. Ordinary test failures do not trigger pool changes.
Automatic fallback is disabled until a real backup pool and any cost have been approved.
This repository requires no monitor credentials, host Docker socket, or new polling workflow.
