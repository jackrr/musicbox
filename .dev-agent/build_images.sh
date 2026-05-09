#!/usr/bin/env bash
# Build (or rebuild) the musicbox sandbox + runner container images.
#
# Run from the repo root, or from anywhere — the script cd's to the repo root
# itself. The runner image FROMs the sandbox image, so they must be built in
# this order.
#
# Usage:
#   .dev-agent/build_images.sh              # build both
#   .dev-agent/build_images.sh sandbox      # just the sandbox image
#   .dev-agent/build_images.sh runner       # just the runner image (assumes sandbox exists)
#   .dev-agent/build_images.sh --no-cache   # force a full rebuild of both

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${ENGINE:-podman}"

EXTRA_ARGS=()
TARGETS=()
for arg in "$@"; do
    case "$arg" in
        --no-cache|--pull|--quiet|-q) EXTRA_ARGS+=("$arg") ;;
        sandbox|runner)               TARGETS+=("$arg") ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=(sandbox runner)

cd "$REPO_ROOT"

build_sandbox() {
    echo "==> Building musicbox-sandbox:latest"
    "$ENGINE" build "${EXTRA_ARGS[@]}" \
        -t musicbox-sandbox:latest \
        -f .dev-agent/Dockerfile.sandbox \
        .
}

build_runner() {
    echo "==> Building musicbox-runner:latest"
    "$ENGINE" build "${EXTRA_ARGS[@]}" \
        -t musicbox-runner:latest \
        -f .dev-agent/runner/Dockerfile \
        .dev-agent
}

for target in "${TARGETS[@]}"; do
    case "$target" in
        sandbox) build_sandbox ;;
        runner)  build_runner  ;;
    esac
done

echo "==> Done."
