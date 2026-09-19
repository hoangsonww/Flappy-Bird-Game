#!/usr/bin/env bash
#
# Poll a health endpoint until it answers or the attempts run out.
#
#   ./scripts/wait-for-health.sh http://localhost:4000/healthz [attempts]
set -euo pipefail

URL="${1:-http://localhost:4000/healthz}"
ATTEMPTS="${2:-60}"

printf '▸ Waiting for %s ' "$URL"
for attempt in $(seq 1 "$ATTEMPTS"); do
  if curl -fsS --max-time 2 "$URL" >/dev/null 2>&1; then
    printf ' ready\n'
    exit 0
  fi
  printf '.'
  sleep 1
done

printf '\n✖ %s did not become healthy after %s attempts\n' "$URL" "$ATTEMPTS" >&2
exit 1
