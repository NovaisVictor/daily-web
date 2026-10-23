#!/usr/bin/env bash
set -euo pipefail

APP_URL="${DAILY_WEB_HEALTH_URL:-http://127.0.0.1:8010/login}"
OAUTH_URL="${DAILY_WEB_OAUTH_HEALTH_URL:-http://127.0.0.1:8011/health}"
TRIES="${DAILY_WEB_HEALTH_TRIES:-30}"
DELAY="${DAILY_WEB_HEALTH_DELAY:-2}"
if [[ ! "$TRIES" =~ ^[1-9][0-9]*$ || "$TRIES" -gt 120 || ! "$DELAY" =~ ^[0-9]+$ || "$DELAY" -gt 30 ]]; then
  echo "invalid health retry configuration" >&2
  exit 1
fi

for ((attempt=1; attempt<=TRIES; attempt++)); do
  app_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$APP_URL" || true)"
  oauth_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$OAUTH_URL" || true)"
  if [[ "$app_code" == "200" && "$oauth_code" == "200" ]]; then
    echo "Application and OAuth companion are healthy on attempt $attempt"
    exit 0
  fi
  if [[ "$attempt" -lt "$TRIES" ]]; then sleep "$DELAY"; fi
done

echo "Application or OAuth companion did not become healthy after $TRIES attempts" >&2
exit 1
