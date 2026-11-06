#!/usr/bin/env bash
# Builds, signs and publishes a release of the macOS client on this Mac, then
# updates the Homebrew cask in NovaisVictor/homebrew-tap. Local build only: no
# GitHub Actions (the signing identity lives in the maintainer's keychain).
set -euo pipefail

usage="Usage: Scripts/release.sh <version>   (e.g. 0.2.0)

Releases the macOS client from HEAD, which must be committed and pushed to the
fork. Needs gh logged in with write access to the fork and the tap.

Env: DAILY_WEB_FORK (default NovaisVictor/daily-web),
     DAILY_WEB_TAP (default NovaisVictor/homebrew-tap),
     JOBS (compile jobs, default 4)."

VERSION=''
while (($#)); do
  case $1 in
    -h | --help) echo "$usage"; exit 0 ;;
    -*) echo "unknown option $1" >&2; echo "$usage" >&2; exit 1 ;;
    *) [[ -z "$VERSION" ]] || { echo "$usage" >&2; exit 1; }; VERSION=$1; shift ;;
  esac
done
fail() { echo "ERROR: $1" >&2; exit 1; }
[[ -n "$VERSION" ]] || { echo "$usage" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "the version must look like 0.2.0, got '$VERSION'"

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
  || fail "commit or set aside local changes (tracked or not) first: the release must match a commit"
COMMIT="$(git -C "$MACOS" rev-parse HEAD)"
gh api "repos/$FORK/commits/$COMMIT" --silent 2>/dev/null || fail "push $COMMIT to $FORK first"
for repo in "$FORK" "$TAP"; do
  case "$(gh repo view "$repo" --json viewerPermission -q .viewerPermission)" in
    ADMIN | MAINTAIN | WRITE) ;;
    *) fail "the active gh account can't push to $repo (gh auth switch)" ;;
  esac
done

# Checks the built app before anything is published: signature, architecture,
# version and bundle id, so a broken build never reaches the tap.
validate() {
  local plist="$APP/Contents/Info.plist" binary
  codesign --verify --strict --deep "$APP" || fail "the signature of $APP does not verify"
  binary="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
  [[ "$(lipo -archs "$binary")" == "arm64" ]] || fail "$binary is not arm64 only: $(lipo -archs "$binary")"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$VERSION" ]] \
    || fail "CFBundleShortVersionString is not $VERSION"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == "io.github.novaisvictor.dailyweb" ]] \
    || fail "unexpected bundle identifier"
  echo "Validated $APP."
}

rm -rf "$DIST" && mkdir -p "$DIST"
if gh release view "$TAG" --repo "$FORK" >/dev/null 2>&1; then
  # A previous run published the release but stopped before the tap: reuse the
  # published zip instead of building a different one, and only update the cask.
  echo "$TAG already exists on $FORK; updating the tap from its published zip."
  gh release download "$TAG" --repo "$FORK" --pattern "DailyWeb-$VERSION.zip" --dir "$DIST"
  SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
else
  # guarded.sh aborts the build if the compilers take too much memory: an
  # unbounded Swift build froze this Mac twice (see AGENTS.md).
  "$HERE/guarded.sh" xcodebuild -project "$MACOS/DailyWeb.xcodeproj" -scheme DailyWeb -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$MACOS/.build/release" -quiet -jobs "${JOBS:-4}" \
    ARCHS=arm64 MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" clean build
  cp -R "$MACOS/.build/release/Build/Products/Release/DailyWeb.app" "$APP"

  "$HERE/sign.sh" "$APP"
  validate
  ditto -c -k --keepParent "$APP" "$ZIP"
  SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  echo "Built $ZIP ($SHA256)"

  gh release create "$TAG" "$ZIP" --repo "$FORK" --target "$COMMIT" \
    --title "Daily Web for macOS $VERSION" --generate-notes \
    --notes "Native macOS client. Install with \`brew install --cask novaisvictor/tap/daily-web\`. SHA-256: \`$SHA256\`."
fi

TAPDIR="$(mktemp -d)"
trap 'rm -rf "$TAPDIR"' EXIT
gh repo clone "$TAP" "$TAPDIR" -- --quiet --depth 1
git -C "$TAPDIR" checkout --quiet -B main
mkdir -p "$TAPDIR/Casks"
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA256/" "$HERE/daily-web.rb.tmpl" > "$TAPDIR/Casks/daily-web.rb"
ruby -c "$TAPDIR/Casks/daily-web.rb" >/dev/null || fail "the generated cask is not valid Ruby"
git -C "$TAPDIR" add Casks/daily-web.rb
if git -C "$TAPDIR" diff --cached --quiet; then
  echo "The cask already points at $VERSION."
else
  git -C "$TAPDIR" commit --quiet -m "daily-web $VERSION"
  # The tap is its own repo with no review flow: its main is where casks live.
  git -C "$TAPDIR" push --quiet origin main
fi
echo "Published $TAG and updated $TAP: brew update && brew upgrade --cask daily-web"
