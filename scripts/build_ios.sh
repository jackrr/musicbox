#!/usr/bin/env bash
# Build the Rust engine for iOS (arm64 device + x86_64 simulator)
# Requires: cargo-lipo (`cargo install cargo-lipo`) and Xcode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
ENGINE_DIR="$ROOT/engine"
OUTPUT_DIR="$ROOT/app/ios"

BUILD_TYPE="--release"
if [[ "${1:-}" == "--dev" ]]; then
  BUILD_TYPE=""
fi

echo "Building Rust engine for iOS..."
cd "$ENGINE_DIR"

# Build universal static library (device + simulator)
cargo lipo $BUILD_TYPE

cp "target/universal/release/libmusicbox_engine.a" "$OUTPUT_DIR/libmusicbox_engine.a" 2>/dev/null || \
  cp "target/universal/debug/libmusicbox_engine.a" "$OUTPUT_DIR/libmusicbox_engine.a"

echo "Done. Static lib written to $OUTPUT_DIR/libmusicbox_engine.a"
echo "Remember to link libmusicbox_engine.a in Xcode under Build Phases > Link Binary With Libraries."
