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

# Untracked files count too: SwiftPM and Xcode compile whatever sits in the
# source folders, so a stray file would ship code that exists in no commit.
[[ -z "$(git -C "$MACOS" status --porcelain --untracked-files=normal -- .)" ]] \
  || { echo "commit or set aside local changes (tracked or not) first: the release must match a commit" >&2; exit 1; }
COMMIT="$(git -C "$MACOS" rev-parse HEAD)"
gh api "repos/$FORK/commits/$COMMIT" --silent \
  || { echo "push $COMMIT to $FORK first" >&2; exit 1; }

rm -rf "$DIST" && mkdir -p "$DIST"
if gh release view "$TAG" --repo "$FORK" >/dev/null 2>&1; then
  # A previous run published the release but stopped before the tap: reuse the
  # published zip instead of building a different one, and only update the cask.
  echo "$TAG already exists on $FORK; updating the tap from its published zip."
  gh release download "$TAG" --repo "$FORK" --pattern "DailyWeb-$VERSION.zip" --dir "$DIST"
  SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
else
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
fi

TAPDIR="$(mktemp -d)"
trap 'rm -rf "$TAPDIR"' EXIT
gh repo clone "$TAP" "$TAPDIR" -- --quiet
# The tap may still be empty (no branch yet); publish to main either way.
git -C "$TAPDIR" checkout --quiet -B main
mkdir -p "$TAPDIR/Casks"
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA256/" "$HERE/daily-web.rb.tmpl" > "$TAPDIR/Casks/daily-web.rb"
git -C "$TAPDIR" add Casks/daily-web.rb
if git -C "$TAPDIR" diff --cached --quiet; then
  echo "The cask already points at $VERSION."
else
  git -C "$TAPDIR" commit --quiet -m "daily-web $VERSION"
  git -C "$TAPDIR" push --quiet origin main
fi
echo "Published $TAG and updated $TAP."
