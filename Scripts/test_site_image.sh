#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
  printf 'Usage: %s IMAGE REVISION\n' "$0" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
container=$(docker create --publish 127.0.0.1::8080 "$1")
trap 'docker logs "$container" || true; docker rm --force "$container"' EXIT
docker start "$container"
address=$(docker port "$container" 8080/tcp)
export SAYKUKU_SITE_URL="http://$address"
export SAYKUKU_SITE_REVISION="$2"
for _ in $(seq 1 30); do
  if curl --fail --silent --max-time 2 "$SAYKUKU_SITE_URL/healthz" >/dev/null; then
    python3 -m unittest discover -s Scripts/tests -p test_site.py
    exit
  fi
  sleep 1
done
printf 'Site container did not become healthy at %s\n' "$SAYKUKU_SITE_URL" >&2
exit 1
