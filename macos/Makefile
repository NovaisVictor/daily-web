# Entry points for people and agents. Run from macos/.
PKG := Packages/DailyKit
SCRATCH ?= .build/spm
# Compile jobs at a time. Unbounded parallel Swift builds exhausted memory and
# froze the machine (2026-11-05); keep this low.
JOBS ?= 4
XCODE := xcodebuild -project DailyWeb.xcodeproj -scheme DailyWeb -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode -quiet -jobs $(JOBS)

.PHONY: build test lint format app check clean release

build:
	Scripts/guarded.sh swift build --package-path $(PKG) --scratch-path $(SCRATCH) -j $(JOBS)

test:
	Scripts/guarded.sh swift test --package-path $(PKG) --scratch-path $(SCRATCH) -j $(JOBS)

lint:
	swift format lint --strict --recursive --parallel App $(PKG)/Package.swift $(PKG)/Sources $(PKG)/Tests

format:
	swift format format --in-place --recursive --parallel App $(PKG)/Package.swift $(PKG)/Sources $(PKG)/Tests

# The Keychain hands the session token only to the signing identity that saved
# it, so an ad hoc Debug build and the brew release would each ask for the login
# password. When this Mac has the release identity, the Debug app is re-signed
# with it (xcodebuild overrides would also hit the package resource bundles,
# which then demand a development team).
SIGN_IDENTITY ?= Daily Web Self-Signed
HAS_IDENTITY := $(shell security find-identity -p codesigning 2>/dev/null | grep -q '"$(SIGN_IDENTITY)"' && echo yes)

app:
	Scripts/guarded.sh $(XCODE) -configuration Debug build
	@if test "$(HAS_IDENTITY)" = yes; then DAILY_WEB_SIGN_IDENTITY="$(SIGN_IDENTITY)" Scripts/sign.sh .build/xcode/Build/Products/Debug/DailyWeb.app; fi

check: lint test app

# Publishes a version: make release VERSION=0.2.0. The checks run first, so a
# release never ships code that fails them.
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=0.2.0" >&2; exit 1; }
	$(MAKE) check
	Scripts/release.sh $(VERSION)

# After a change to a public struct's stored properties in a core target,
# incremental SwiftPM builds can keep stale layouts in dependents and the test
# binary crashes (seen with Endpoint.idempotencyKey). Start from scratch then.
clean:
	rm -rf .build/spm .build/xcode
