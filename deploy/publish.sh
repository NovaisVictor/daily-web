#!/usr/bin/env bash
# Publishes what the runner just built and tested.
#
# Runs from the runner's workspace, which by this point already has
# node_modules installed and .next built — so publishing copies rather than
# rebuilding: what reaches production is exactly the artifact the tests
# approved, not a second, similar compilation.
set -euo pipefail

TARGET="${DAILY_WEB_DEPLOY_DIR:-/srv/daily-web}"
SERVICE="${DAILY_WEB_SERVICE:-daily-web}"

if [[ ! -d "$TARGET" ]]; then
  echo "deployment directory does not exist: $TARGET" >&2
  exit 1
fi

OAUTH_SERVICE="${DAILY_WEB_OAUTH_SERVICE:-daily-web-oauth}"
OAUTH_INSTALLED=0
if systemctl cat "$OAUTH_SERVICE" >/dev/null 2>&1; then
  OAUTH_INSTALLED=1
  sudo systemctl stop "$OAUTH_SERVICE"
fi

ARTIFACT_READY=0
recover() {
  local status=$?
  if [[ "$status" != "0" && "$OAUTH_INSTALLED" == "1" ]]; then
    if [[ "$ARTIFACT_READY" == "1" ]] && systemctl is-active --quiet "$SERVICE"; then
      sudo systemctl start "$OAUTH_SERVICE" || echo "OAuth recovery failed; inspect the companion service" >&2
    else
      echo "Publish failed; OAuth remains stopped. Restore a complete compatible artifact and a healthy application before starting $OAUTH_SERVICE." >&2
    fi
  fi
  exit "$status"
}
trap recover EXIT

echo "publishing to $TARGET"

# --delete so the target does not accumulate files that left the repository.
# data/ is excluded: it holds the production database, which is not from git.
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'data/' \
  ./ "$TARGET/"

ARTIFACT_READY=1
echo "restarting $SERVICE"
sudo systemctl restart "$SERVICE"
if [[ "$OAUTH_INSTALLED" == "1" ]]; then
  sudo systemctl start "$OAUTH_SERVICE"
fi
