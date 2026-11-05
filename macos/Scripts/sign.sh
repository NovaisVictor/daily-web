#!/usr/bin/env bash
# Signs DailyWeb.app with the project's stable self-signed identity.
#
# Why not ad-hoc: an ad-hoc signature changes with every build, so macOS treats
# each release as a different app and asks again for access to the session
# token in the Keychain. A self-signed certificate kept in the maintainer's
# login keychain gives every release the same identity. It does not pass
# Gatekeeper (that needs a paid Developer ID and notarization): users still
# confirm the first launch of each version (see macos/README.md).
#
# Usage: Scripts/sign.sh path/to/DailyWeb.app
set -euo pipefail

IDENTITY="${DAILY_WEB_SIGN_IDENTITY:-Daily Web Self-Signed}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ENTITLEMENTS="$HERE/../Config/DailyWeb.entitlements"
APP="${1:?usage: sign.sh path/to/DailyWeb.app}"

has_identity() {
  security find-identity -p codesigning | grep -q "\"$IDENTITY\""
}

create_identity() {
  echo "Creating the signing identity \"$IDENTITY\" in the login keychain (one time)."
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  cat > "$dir/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$dir/cert.cnf" -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
  local pass
  pass="$(/usr/bin/openssl rand -hex 16)"
  /usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" \
    -name "$IDENTITY" -out "$dir/identity.p12" -passout "pass:$pass"
  security import "$dir/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$pass" -T /usr/bin/codesign >/dev/null
  has_identity || { echo "The identity was imported but codesign cannot see it." >&2; exit 1; }
}

has_identity || create_identity

codesign --force --options runtime --timestamp=none \
  --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"
echo "Signed $APP as \"$IDENTITY\"."
