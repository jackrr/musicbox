#!/usr/bin/env bash
# Build the Rust engine and run/install the Flutter app on Android.
#
# Usage:
#   ./scripts/run.sh                  # debug engine build + flutter run
#   ./scripts/run.sh --dev            # same (alias for clarity)
#   ./scripts/run.sh --release-run    # release engine build + flutter run --release
#   ./scripts/run.sh --release-install # release engine + flutter build apk + adb install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

MODE="dev"
if [[ "${1:-}" == "--release-run" ]]; then
  MODE="release-run"
elif [[ "${1:-}" == "--release-install" ]]; then
  MODE="release-install"
fi

# ---------------------------------------------------------------------------
# Step 1: Rust engine build
# ---------------------------------------------------------------------------

if [[ "$MODE" == "dev" ]]; then
  echo "==> Building Rust engine (debug)..."
  "$SCRIPT_DIR/build_android.sh" --dev
else
  echo "==> Building Rust engine (release)..."
  "$SCRIPT_DIR/build_android.sh"
fi

# ---------------------------------------------------------------------------
# Step 2: Flutter run / build / install
# ---------------------------------------------------------------------------

cd "$ROOT/app"

if [[ "$MODE" == "dev" ]]; then
  echo "==> Running flutter run..."
  flutter run

elif [[ "$MODE" == "release-run" ]]; then
  echo "==> Running flutter run --release..."
  flutter run --release

elif [[ "$MODE" == "release-install" ]]; then
  echo "==> Building release APK..."
  flutter build apk --release

  echo "==> Uninstalling existing app..."
  adb uninstall dev.musicbox.musicbox || true

  echo "==> Installing release APK..."
  adb install build/app/outputs/flutter-apk/app-release.apk

  echo "Done."
fi
