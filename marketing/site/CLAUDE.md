# Zeabur Deployment

- Project: SayKuku
- Service: `saykuku-site`
- Source directory: `marketing/site/dist`
- Domain: `https://say.anikuku.com/`

For an App release, use the repository's release entry point from a clean `main` checkout:

```bash
Scripts/release.sh --notes /absolute/path/release-notes.txt
```

This verifies the public DMG before deploying this site, then publishes `appcast.xml`
and the same `ver.json` to the website and R2. Keep `ver.json` for older clients.
Do not deploy a new version number or update feed before its installer is public.
The script also updates and commits `marketing/site/dist` after public verification.
See [the release guide](../../docs/LOCAL_PACKAGING.md) for prerequisites and recovery.

For website-only changes, run from `marketing/site/dist`. Deployment IDs are kept
locally in `~/.config/saykuku/deploy.env`. Check authentication and deploy to the existing service:

```bash
source "$HOME/.config/saykuku/deploy.env"
: "${ZEABUR_PROJECT_ID:?}" "${ZEABUR_SERVICE_ID:?}"
npx zeabur@latest auth status -i=false
npx zeabur@latest deploy --project-id "$ZEABUR_PROJECT_ID" --service-id "$ZEABUR_SERVICE_ID" --json -i=false
```

Always pass the service ID to avoid creating a duplicate.
Keep credentials and private signing keys outside this public repository.
