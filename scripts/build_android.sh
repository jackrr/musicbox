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

# Bundle libc++_shared.so — required by oboe (cpal's Android audio backend).
# cargo-ndk doesn't always copy it automatically; do it explicitly here.
NDK_HOST="linux-x86_64"
NDK_PREBUILT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${NDK_HOST}"

copy_libcpp() {
  local ABI="$1"
  local TRIPLE="$2"
  local SRC="${NDK_PREBUILT}/sysroot/usr/lib/${TRIPLE}/libc++_shared.so"
  if [[ -f "$SRC" ]]; then
    cp "$SRC" "${OUTPUT_DIR}/${ABI}/libc++_shared.so"
    echo "  Copied libc++_shared.so → ${ABI}"
  else
    echo "  WARNING: libc++_shared.so not found at $SRC"
  fi
}

copy_libcpp arm64-v8a   aarch64-linux-android
copy_libcpp armeabi-v7a arm-linux-androideabi

echo "Done. Libraries written to $OUTPUT_DIR"
