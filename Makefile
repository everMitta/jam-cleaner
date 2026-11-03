.PHONY: all build test coverage app universal run cli-summary lint format format-check clean

all: test app

## Build the release executable via Swift Package Manager
build:
	swift build -c release

## Run the full XCTest unit test suite
test:
	swift test

## Run the XCTest unit test suite with LLVM code coverage and print a summary table
coverage:
	swift test --enable-code-coverage
	@CODECOV_DIR=$$(swift test --enable-code-coverage --show-codecov-path | xargs dirname); \
	BIN_DIR=$$(swift build --show-bin-path); \
	PROFDATA="$$CODECOV_DIR/default.profdata"; \
	TEST_BUNDLE=$$(find "$$BIN_DIR" -maxdepth 1 -name "*Tests.xctest" | head -n 1); \
	TEST_BIN="$$TEST_BUNDLE/Contents/MacOS/$$(basename "$$TEST_BUNDLE" .xctest)"; \
	if [ -f "$$PROFDATA" ] && [ -f "$$TEST_BIN" ]; then \
		xcrun llvm-cov report "$$TEST_BIN" -instr-profile="$$PROFDATA" -ignore-filename-regex=".build|Tests"; \
	fi

## Package and sign "build/JAM Cleaner.app" (local ad-hoc signature by default)
app:
	./scripts/build_app.sh

## Package a Universal 2 (arm64 + x86_64) release app bundle
universal:
	BUILD_UNIVERSAL=1 ./scripts/build_app.sh

## Build and launch "JAM Cleaner.app"
run: app
	open "build/JAM Cleaner.app"

## Run a headless CLI storage scan summary in the terminal
cli-summary: build
	"$$(swift build -c release --show-bin-path)/MacSweep" --print-summary

## Validate Apple Privacy Manifest, Entitlement property lists, and Swift compilation warnings
lint:
	plutil -lint Config/PrivacyInfo.xcprivacy
	plutil -lint Config/MacSweep.Direct.entitlements
	plutil -lint Config/MacSweep.AppStore.entitlements
	swift build --build-tests

## Format Swift source and test files using Apple's toolchain swift-format
format:
	xcrun swift-format format --in-place --recursive --configuration .swift-format Sources Tests Package.swift

## Check Swift formatting and lint rules using Apple's toolchain swift-format
format-check:
	xcrun swift-format lint --recursive --configuration .swift-format Sources Tests Package.swift

## Remove local build directories
clean:
	rm -rf .build build
