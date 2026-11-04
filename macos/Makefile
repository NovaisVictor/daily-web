# Entry points for people and agents. Run from macos/.
PKG := Packages/DailyKit
SCRATCH ?= .build/spm
XCODE := xcodebuild -project DailyWeb.xcodeproj -scheme DailyWeb -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode -quiet

.PHONY: build test lint format app check clean

build:
	swift build --package-path $(PKG) --scratch-path $(SCRATCH)

test:
	swift test --package-path $(PKG) --scratch-path $(SCRATCH)

lint:
	swift format lint --strict --recursive --parallel App $(PKG)/Package.swift $(PKG)/Sources $(PKG)/Tests

format:
	swift format format --in-place --recursive --parallel App $(PKG)/Package.swift $(PKG)/Sources $(PKG)/Tests

app:
	$(XCODE) -configuration Debug build

check: lint test app

# After a change to a public struct's stored properties in a core target,
# incremental SwiftPM builds can keep stale layouts in dependents and the test
# binary crashes (seen with Endpoint.idempotencyKey). Start from scratch then.
clean:
	rm -rf .build/spm .build/xcode
