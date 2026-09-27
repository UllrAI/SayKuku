# Zeabur Deployment

- Project: SayKuku
- Project ID: `ZEABUR_PROJECT_ID`
- Service: `saykuku-site`
- Service ID: `ZEABUR_SERVICE_ID`
- Environment ID: `ZEABUR_ENVIRONMENT_ID`
- Region: `ZEABUR_REGION` (`ZEABUR_SERVER_ID`)
- Source directory: `marketing/site/dist`
- Domain: `https://say.anikuku.com/`

Redeploy from `marketing/site/dist` with `npx zeabur@latest deploy --project-id ZEABUR_PROJECT_ID --service-id ZEABUR_SERVICE_ID --json`. Always pass the service ID to avoid creating a duplicate.
