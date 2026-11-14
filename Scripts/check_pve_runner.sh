#!/usr/bin/env bash
set -euo pipefail

for tool in bash curl docker gh git python3 sha256sum; do
  command -v "$tool" >/dev/null || { printf 'Missing tool: %s\n' "$tool" >&2; exit 1; }
done

cd "$(dirname "$0")/.."
if [[ -n $(git status --porcelain -- .github/workflows/site.yml marketing/site Scripts) ]]; then
  printf 'Use a clean checkout of the website and its test scripts.\n' >&2
  exit 1
fi
export PYTHONDONTWRITEBYTECODE=1
unset SAYKUKU_SITE_URL SAYKUKU_SITE_REVISION
revision=$(git rev-parse HEAD)
printf 'Checking SayKuku %s on %s\n' "$revision" "$(hostname)"
python3 --version
gh --version
docker version --format 'Docker server {{.Server.Version}} ({{.Server.Os}}/{{.Server.Arch}})'
docker buildx version
for tests in test_release.py test_site.py test_deploy_site.py; do
  python3 -m unittest discover -s Scripts/tests -p "$tests"
done

image="saykuku-pve-preflight:$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
trap 'docker image rm "$image" >/dev/null 2>&1 || true' EXIT
docker buildx build --platform linux/amd64 --load --tag "$image" --build-arg "SOURCE_COMMIT=$revision" marketing/site
bash Scripts/test_site_image.sh "$image" "$revision"
