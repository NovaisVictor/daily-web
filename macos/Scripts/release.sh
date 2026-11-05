#!/usr/bin/env bash
# Builds, signs and publishes a release of the macOS client, then updates the
# Homebrew cask in NovaisVictor/homebrew-tap.
#
# Usage: Scripts/release.sh 0.1.0
# Needs: a clean git tree whose HEAD is pushed to the fork, `gh` logged in with
# write access to NovaisVictor/daily-web and NovaisVictor/homebrew-tap.
set -euo pipefail

VERSION="${1:?usage: release.sh <version, e.g. 0.1.0>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3" >&2; exit 1; }

FORK="${DAILY_WEB_FORK:-NovaisVictor/daily-web}"
TAP="${DAILY_WEB_TAP:-NovaisVictor/homebrew-tap}"
TAG="macos-v$VERSION"
HERE="$(cd "$(dirname "$0")" && pwd)"
MACOS="$(cd "$HERE/.." && pwd)"
DIST="$MACOS/dist"
APP="$DIST/DailyWeb.app"
ZIP="$DIST/DailyWeb-$VERSION.zip"

git -C "$MACOS" diff --quiet && git -C "$MACOS" diff --cached --quiet \
  || { echo "commit or set aside local changes first: the release must match a commit" >&2; exit 1; }
COMMIT="$(git -C "$MACOS" rev-parse HEAD)"
gh api "repos/$FORK/commits/$COMMIT" --silent \
  || { echo "push $COMMIT to $FORK first" >&2; exit 1; }
if gh release view "$TAG" --repo "$FORK" >/dev/null 2>&1; then
  echo "$TAG already exists on $FORK" >&2; exit 1
fi

rm -rf "$DIST" && mkdir -p "$DIST"
xcodebuild -project "$MACOS/DailyWeb.xcodeproj" -scheme DailyWeb -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$MACOS/.build/release" -quiet \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" build
cp -R "$MACOS/.build/release/Build/Products/Release/DailyWeb.app" "$APP"

"$HERE/sign.sh" "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "Built $ZIP ($SHA256)"

gh release create "$TAG" "$ZIP" --repo "$FORK" --target "$COMMIT" \
  --title "Daily Web for macOS $VERSION" \
  --notes "Native macOS client. Install with \`brew install --cask novaisvictor/tap/daily-web\`. SHA-256: \`$SHA256\`."

TAPDIR="$(mktemp -d)"
trap 'rm -rf "$TAPDIR"' EXIT
gh repo clone "$TAP" "$TAPDIR" -- --quiet
# The tap may still be empty (no branch yet); publish to main either way.
git -C "$TAPDIR" checkout --quiet -B main
mkdir -p "$TAPDIR/Casks"
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA256/" "$HERE/daily-web.rb.tmpl" > "$TAPDIR/Casks/daily-web.rb"
git -C "$TAPDIR" add Casks/daily-web.rb
git -C "$TAPDIR" commit --quiet -m "daily-web $VERSION"
git -C "$TAPDIR" push --quiet origin main
echo "Published $TAG and updated $TAP."
