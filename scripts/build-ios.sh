#!/usr/bin/env bash
# Build kothon-core for iPhone (device + Apple Silicon simulator), wrap it in
# an XCFramework, and generate the Xcode project.
#
#   ./scripts/build-ios.sh            # release build (what you want on a phone)
#   ./scripts/build-ios.sh --debug    # faster to compile, much slower to run
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=release
CARGO_FLAGS=(--release)
if [[ "${1:-}" == "--debug" ]]; then PROFILE=debug; CARGO_FLAGS=(); fi

for tool in cargo xcodebuild cmake; do
  command -v "$tool" >/dev/null || { echo "Missing $tool (cmake: brew install cmake)"; exit 1; }
done
command -v xcodegen >/dev/null || { echo "Installing XcodeGen…"; brew install xcodegen; }

rustup target add aarch64-apple-ios aarch64-apple-ios-sim

export IPHONEOS_DEPLOYMENT_TARGET=17.0
# Build ggml for a generic iPhone CPU, never for the Mac doing the build.
export TRANSCRIBE_CMAKE_ARGS="-DGGML_NATIVE=OFF"

for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  echo "==> kothon-core for $target ($PROFILE)"
  cargo build --manifest-path core/Cargo.toml --target "$target" "${CARGO_FLAGS[@]}"
done

OUT=ios/Frameworks/KothonCore.xcframework
rm -rf "$OUT"
xcodebuild -create-xcframework \
  -library "core/target/aarch64-apple-ios/$PROFILE/libkothon_core.a" -headers core/include \
  -library "core/target/aarch64-apple-ios-sim/$PROFILE/libkothon_core.a" -headers core/include \
  -output "$OUT"

(cd ios && xcodegen)
echo
echo "Done. Open ios/Kothon.xcodeproj, pick your iPhone, and press Run."
