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

OAUTH_SERVICE="${SERVICE}-oauth"
NODE="$(node -p 'process.execPath')"
sudo env DAILY_WEB_SERVICE="$SERVICE" "$NODE" ./deploy/install-services.mjs --check "$TARGET"
OAUTH_INSTALLED=0
if systemctl cat "$OAUTH_SERVICE" >/dev/null 2>&1; then
  OAUTH_INSTALLED=1
  sudo systemctl stop "$OAUTH_SERVICE"
fi

ARTIFACT_READY=0
APP_RESTARTED=0
recover() {
  local status=$?
  if [[ "$status" != "0" && "$OAUTH_INSTALLED" == "1" ]]; then
    if [[ "$ARTIFACT_READY" == "1" && "$APP_RESTARTED" == "1" ]] && systemctl is-active --quiet "$SERVICE"; then
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
sudo env DAILY_WEB_SERVICE="$SERVICE" "$NODE" "$TARGET/deploy/install-services.mjs" "$TARGET"
echo "restarting $SERVICE"
sudo systemctl restart "$SERVICE"
APP_RESTARTED=1
sudo systemctl start "$OAUTH_SERVICE"
"$TARGET/deploy/healthcheck.sh"
