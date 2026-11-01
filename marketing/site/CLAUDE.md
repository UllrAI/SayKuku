# Coolify Deployment

- Project: SayKuku
- Service: `saykuku-site`
- Source directory: `marketing/site/dist`
- Image: `ghcr.io/ullrai/saykuku-site`
- Environment: `production`
- Domain: `https://say.anikuku.com/`

For an App release, use the repository's release entry point from a clean `main` checkout:

```bash
Scripts/release.sh --notes /absolute/path/release-notes.txt
```

This verifies the public DMG before deploying this site, then publishes `appcast.xml`
and the same `ver.json` to the website and R2. Keep `ver.json` for older clients.
Do not deploy a new version number or update feed before its installer is public.
The script commits and pushes the candidate website, waits for Site CI/CD to deploy
and verify it, then publishes the R2 feeds. A failed deployment must not publish feeds.
See [the release guide](../../docs/LOCAL_PACKAGING.md) for prerequisites and recovery.

For website-only changes, open a PR with the site changes. After checks pass, merge
to `main`; `.github/workflows/site.yml` tests, builds and publishes one image,
then triggers Coolify and verifies the production site. To retry the workflow:

```bash
gh workflow run site.yml --repo UllrAI/SayKuku --ref main
```

Coolify only pulls the tested image. Do not enable a second Git push deployment
path that could bypass the checks. HTTPS is handled by the existing Traefik proxy;
the site container runs non-root Nginx on port 8080. See README.md for configuration
and rollback. Native App testing, signing and notarization remain local; do not add
macOS GitHub Actions runners.
Keep credentials and private signing keys outside this public repository.
