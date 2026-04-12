#!/usr/bin/env bash
# Build the Rust engine for Android (arm64-v8a and armeabi-v7a)
# Requires: cargo-ndk (`cargo install cargo-ndk`) and Android NDK

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
ENGINE_DIR="$ROOT/engine"
OUTPUT_DIR="$ROOT/app/android/app/src/main/jniLibs"

# Default to release build; pass --dev to build debug
BUILD_TYPE="--release"
if [[ "${1:-}" == "--dev" ]]; then
  BUILD_TYPE=""
fi

echo "Building Rust engine for Android..."
cd "$ENGINE_DIR"

cargo ndk \
  -t arm64-v8a \
  -t armeabi-v7a \
  -o "$OUTPUT_DIR" \
  build $BUILD_TYPE

echo "Done. Libraries written to $OUTPUT_DIR"
