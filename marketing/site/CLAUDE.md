# Zeabur Deployment

- Project: SayKuku
- Service: `saykuku-site`
- Source directory: `marketing/site/dist`
- Domain: `https://say.anikuku.com/`

Deployment IDs are kept locally in `~/.config/saykuku/deploy.env`. Load them before deploying:

```bash
source "$HOME/.config/saykuku/deploy.env"
: "${ZEABUR_PROJECT_ID:?}" "${ZEABUR_SERVICE_ID:?}"
npx zeabur@latest deploy --project-id "$ZEABUR_PROJECT_ID" --service-id "$ZEABUR_SERVICE_ID" --json
```

Always pass the service ID to avoid creating a duplicate.
