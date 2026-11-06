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

app:
	Scripts/guarded.sh $(XCODE) -configuration Debug build

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
