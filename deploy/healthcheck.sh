#!/usr/bin/env bash
# Checks that the app answers again after the restart. Without this, a deploy
# that takes the service down still finishes green on GitHub.
set -euo pipefail

URL="${DAILY_WEB_HEALTH_URL:-http://127.0.0.1:8010/login}"
TRIES="${DAILY_WEB_HEALTH_TRIES:-30}"

for attempt in $(seq 1 "$TRIES"); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL" || true)"
  if [[ "$code" == "200" ]]; then
    echo "up: $URL answered 200 on attempt $attempt"
    if [[ -n "${DAILY_WEB_OAUTH_HEALTH_URL:-}" ]]; then
      curl --fail --silent --max-time 5 "$DAILY_WEB_OAUTH_HEALTH_URL" >/dev/null || exit 1
      echo "OAuth companion answered successfully"
    fi
    exit 0
  fi
  sleep 2
done

echo "the app did not answer 200 at $URL after $TRIES attempts" >&2
echo "--- last log lines ---" >&2
sudo journalctl -u "${DAILY_WEB_SERVICE:-daily-web}" -n 40 --no-pager >&2 || true
exit 1
