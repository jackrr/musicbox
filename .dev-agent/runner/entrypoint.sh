#!/usr/bin/env bash
# Entrypoint for the musicbox self-hosted GitHub Actions runner.
#
# Required env:
#   REPO_URL       e.g. https://github.com/<owner>/musicbox
#   RUNNER_TOKEN   short-lived token from repo Settings → Actions → Runners → Add new runner
# Optional env:
#   RUNNER_NAME    default: musicbox-runner-<hostname>
#   RUNNER_LABELS  default: musicbox-builder
#   RUNNER_GROUP   default: Default
#
# The runner is registered as ephemeral (--ephemeral) so it deregisters
# itself after each job, and the container should be run with --rm. Use a
# process supervisor (systemd, docker-compose with restart=always) to
# spawn replacements between jobs.

set -euo pipefail

: "${REPO_URL:?REPO_URL is required}"
: "${RUNNER_TOKEN:?RUNNER_TOKEN is required}"

RUNNER_NAME="${RUNNER_NAME:-musicbox-runner-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-musicbox-builder}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"

cd "${RUNNER_HOME:-/home/agent/actions-runner}"

cleanup() {
    echo "Removing runner registration..."
    ./config.sh remove --token "${RUNNER_TOKEN}" || true
}
trap cleanup EXIT INT TERM

./config.sh \
    --unattended \
    --ephemeral \
    --url "${REPO_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --runnergroup "${RUNNER_GROUP}" \
    --replace

exec ./run.sh
